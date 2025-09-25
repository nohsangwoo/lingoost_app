import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:lingoost_app/services/google_auth_service.dart';
import 'package:lingoost_app/services/apple_auth_service.dart';
import 'package:lingoost_app/services/fcm_service.dart';

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _webViewController;
  final FcmService _fcmService = FcmService();
  bool _isLoading = true;
  bool _isSigningIn = false; // 로그인 진행 중 상태

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri('https://71c5fc1defa4.ngrok-free.app'),
              ),
              onReceivedError: (controller, request, error) {
                print('❌ WebView error: ${error.type} - ${error.description}');
              },
              onReceivedHttpError: (controller, request, response) {
                print(
                  '❌ HTTP error: ${response.statusCode} - ${response.reasonPhrase}',
                );
              },
              onConsoleMessage: (controller, consoleMessage) {
                print('📦 WebView Console: ${consoleMessage.message}');
              },
              initialSettings: InAppWebViewSettings(
                // User Agent에 MedikApp 식별자 추가
                userAgent: Platform.isIOS
                    ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) MedikApp/1.0 Mobile/15E148'
                    : 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 MedikApp/1.0 Mobile Safari/537.36',

                // 새 창/탭 열기 방지 설정 (중요!)
                supportMultipleWindows: false,
                javaScriptCanOpenWindowsAutomatically: false,

                mediaPlaybackRequiresUserGesture: false, // 자동 재생 허용
                allowsInlineMediaPlayback: true, // 인라인 재생 허용 (중요!)
                allowsPictureInPictureMediaPlayback: false, // PiP 비활성화
                iframeAllowFullscreen: false, // iframe 전체화면 비활성화
                // 확대/축소 차단 설정 (안드로이드 호환성 개선)
                supportZoom: false, // 줌 지원 비활성화
                builtInZoomControls: false, // 내장 줌 컨트롤 비활성화
                displayZoomControls: false, // 줌 컨트롤 표시 안함
                useWideViewPort: true, // 와이드 뷰포트 활성화 (안드로이드 필수)
                loadWithOverviewMode: true, // 오버뷰 모드 활성화 (안드로이드 필수)
                // iOS 설정
                disallowOverScroll: false, // 오버스크롤 허용 (안드로이드 호환)
                enableViewportScale: false, // 뷰포트 스케일 비활성화
                suppressesIncrementalRendering: false, // 점진적 렌더링 허용
                allowsBackForwardNavigationGestures: false, // 스와이프 네비게이션 비활성화
                // 안드로이드 전용 설정
                useHybridComposition:
                    false, // Hybrid Composition 비활성화 (터치 문제 해결)
                useShouldOverrideUrlLoading: true, // URL 로딩 오버라이드
                thirdPartyCookiesEnabled: true, // OAuth 필수
                mixedContentMode:
                    MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW, // 혼합 컨텐츠 허용
                javaScriptEnabled: true, // JavaScript 활성화
                domStorageEnabled: true, // DOM Storage 활성화
                hardwareAcceleration: true, // 하드웨어 가속
                transparentBackground: false, // 투명 배경 비활성화
                verticalScrollBarEnabled: false, // 세로 스크롤바 비활성화
                horizontalScrollBarEnabled: false, // 가로 스크롤바 비활성화
                disableDefaultErrorPage: false, // 기본 에러 페이지 사용
                algorithmicDarkeningAllowed: false, // 다크모드 자동 변환 비활성화
                geolocationEnabled: false, // 위치 정보 비활성화
                needInitialFocus: false, // 초기 포커스 불필요
                scrollbarFadingEnabled: true, // 스크롤바 페이딩
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
                _setupJavaScriptHandlers(controller);
              },
              onLoadStart: (controller, url) {
                print('🌐 WebView loading started: $url');
                setState(() {
                  _isLoading = true;
                });
              },
              onLoadStop: (controller, url) async {
                print('✅ WebView loading completed: $url');
                setState(() {
                  _isLoading = false;
                  _isSigningIn = false; // 페이지 로드 완료 시 로그인 로딩도 해제
                });

                try {
                  // WebView 로드 완료 후 디바이스 정보 전송
                  await _injectDeviceInfo(controller);
                  print('✅ Device info injected');
                } catch (e) {
                  print('❌ Failed to inject device info: $e');
                }

                try {
                  // 확대/축소 방지 JavaScript 주입
                  await _preventZoom(controller);
                  print('✅ Zoom prevention injected');
                } catch (e) {
                  print('❌ Failed to prevent zoom: $e');
                }
              },
              // 새 창 열기 요청 차단 (중요! Android에서 Chrome Custom Tabs 방지)
              onCreateWindow: (controller, createWindowAction) async {
                final url = createWindowAction.request.url?.toString();
                print('WebView: Blocking new window request: $url');

                // 애플 로그인 URL인 경우 처리
                if (url != null &&
                    (url.contains('appleid.apple.com') ||
                        url.contains('supabase.co/auth/v1/authorize') &&
                            url.contains('provider=apple'))) {
                  // Android에서는 현재 웹뷰에서 로드, iOS는 네이티브 처리
                  if (Platform.isAndroid) {
                    print(
                      'WebView: Android - loading Apple OAuth in current WebView',
                    );
                    await controller.loadUrl(
                      urlRequest: URLRequest(url: WebUri(url)),
                    );
                  } else {
                    print('WebView: iOS - handling Apple OAuth natively');
                    _handleNativeAppleSignIn();
                  }
                  return false;
                }

                // 그 외의 경우 현재 창에서 로드
                if (url != null) {
                  await controller.loadUrl(
                    urlRequest: URLRequest(url: WebUri(url)),
                  );
                }

                return false; // 새 창 생성 거부
              },

              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final url = navigationAction.request.url?.toString() ?? '';
                print('WebView: Navigating to: $url');

                // Google OAuth URL 감지
                if (url.contains('accounts.google.com/o/oauth2')) {
                  print(
                    'WebView: Google OAuth URL detected, using native login',
                  );
                  _handleNativeGoogleSignIn();
                  return NavigationActionPolicy.CANCEL;
                }

                // Apple OAuth URL 감지
                if (url.contains('appleid.apple.com/auth') ||
                    url.contains('apple.com/auth') ||
                    (url.contains('supabase.co/auth/v1/authorize') &&
                        url.contains('provider=apple'))) {
                  print('WebView: Apple OAuth URL detected');

                  // Android에서는 웹뷰 내에서 처리
                  if (Platform.isAndroid) {
                    print('WebView: Android - allowing Apple OAuth in WebView');
                    return NavigationActionPolicy.ALLOW; // 웹뷰 내에서 처리
                  } else {
                    // iOS에서는 네이티브 로그인
                    print('WebView: iOS - using native login');
                    _handleNativeAppleSignIn();
                    return NavigationActionPolicy.CANCEL;
                  }
                }

                // OAuth 콜백 URL 처리
                if (url.contains('supabase.co/auth/v1/callback')) {
                  print('WebView: OAuth callback detected');
                  return NavigationActionPolicy.ALLOW;
                }

                // 외부 브라우저 열기 방지 (Android)
                if (Platform.isAndroid) {
                  if (url.startsWith('intent://') ||
                      url.startsWith('market://')) {
                    print('WebView: Blocking external app URL');
                    return NavigationActionPolicy.CANCEL;
                  }
                }

                return NavigationActionPolicy.ALLOW;
              },
            ),
            if (_isLoading) Center(child: CircularProgressIndicator()),
            if (_isSigningIn)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Container(
                    padding: EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('로그인 중...', style: TextStyle(fontSize: 16)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// JavaScript 핸들러 설정
  void _setupJavaScriptHandlers(InAppWebViewController controller) {
    // WebView에서 Google 로그인 요청 받기
    controller.addJavaScriptHandler(
      handlerName: 'googleSignIn',
      callback: (args) async {
        print('WebView requested Google Sign-In');
        await _handleNativeGoogleSignIn();
      },
    );

    // WebView에서 Apple 로그인 요청 받기
    controller.addJavaScriptHandler(
      handlerName: 'appleSignIn',
      callback: (args) async {
        print('WebView requested Apple Sign-In');
        await _handleNativeAppleSignIn();
      },
    );

    // 디바이스 정보 요청 핸들러
    controller.addJavaScriptHandler(
      handlerName: 'deviceInfo',
      callback: (args) {
        return _getDeviceInfo();
      },
    );

    // 인증 완료 콜백 핸들러
    controller.addJavaScriptHandler(
      handlerName: 'authComplete',
      callback: (args) {
        print('WebView: Auth complete callback received');
        setState(() {
          _isSigningIn = false;
        });
      },
    );

    // FCM 토큰 요청 핸들러
    controller.addJavaScriptHandler(
      handlerName: 'getFcmToken',
      callback: (args) async {
        print('WebView requested FCM token');
        final token = _fcmService.currentToken;
        if (token != null) {
          return {
            'success': true,
            'token': token,
            'platform': _fcmService.getPlatform(),
          };
        } else {
          final newToken = await _fcmService.refreshToken();
          if (newToken != null) {
            return {
              'success': true,
              'token': newToken,
              'platform': _fcmService.getPlatform(),
            };
          }
        }
        return {'success': false, 'error': 'Failed to get FCM token'};
      },
    );

    // FCM 토픽 구독 핸들러
    controller.addJavaScriptHandler(
      handlerName: 'subscribeToTopic',
      callback: (args) async {
        if (args.isNotEmpty && args[0] is String) {
          final topic = args[0] as String;
          await _fcmService.subscribeToTopic(topic);
          print('Subscribed to topic: $topic');
          return {'success': true, 'topic': topic};
        }
        return {'success': false, 'error': 'Topic not provided'};
      },
    );

    // FCM 토픽 구독 해제 핸들러
    controller.addJavaScriptHandler(
      handlerName: 'unsubscribeFromTopic',
      callback: (args) async {
        if (args.isNotEmpty && args[0] is String) {
          final topic = args[0] as String;
          await _fcmService.unsubscribeFromTopic(topic);
          print('Unsubscribed from topic: $topic');
          return {'success': true, 'topic': topic};
        }
        return {'success': false, 'error': 'Topic not provided'};
      },
    );
  }

  /// 디바이스 정보 가져오기
  Map<String, dynamic> _getDeviceInfo() {
    final isIOS = Platform.isIOS;
    final isAndroid = Platform.isAndroid;
    final isIPad = isIOS && (MediaQuery.of(context).size.shortestSide >= 600);

    return {
      'isWebView': true,
      'isIOS': isIOS && !isIPad,
      'isIPad': isIPad,
      'isAndroid': isAndroid,
    };
  }

  /// 디바이스 정보를 WebView에 주입
  Future<void> _injectDeviceInfo(InAppWebViewController controller) async {
    print('📱 Injecting device info...');
    final deviceInfo = _getDeviceInfo();
    print('📱 Device info: $deviceInfo');

    // FCM 토큰 가져오기
    String? fcmToken = _fcmService.currentToken;
    if (fcmToken == null) {
      print('🔑 FCM token is null, refreshing...');
      fcmToken = await _fcmService.refreshToken();
    }
    print('🔑 FCM token: ${fcmToken != null ? 'Available' : 'Not available'}');

    await controller.evaluateJavascript(
      source:
          '''
      window.__deviceInfo = ${jsonEncode(deviceInfo)};
      
      // FCM 토큰 저장
      window.__fcmToken = ${fcmToken != null ? '"$fcmToken"' : 'null'};
      
      // 페이지에 이벤트 발송
      window.dispatchEvent(new CustomEvent('deviceInfoReady', { 
        detail: window.__deviceInfo 
      }));
      
      // FCM 토큰 이벤트 발송
      if (window.__fcmToken) {
        window.dispatchEvent(new CustomEvent('fcmTokenReady', { 
          detail: { 
            token: window.__fcmToken,
            platform: '${_fcmService.getPlatform()}'
          }
        }));
        console.log('FCM Token sent to WebView:', window.__fcmToken);
      }
    ''',
    );
  }

  /// 확대/축소 방지 JavaScript 주입 (플랫폼별 최적화)
  Future<void> _preventZoom(InAppWebViewController controller) async {
    // iOS만 JavaScript 줌 방지 적용 (Android는 설정으로 충분)
    if (Platform.isIOS) {
      await controller.evaluateJavascript(
        source: '''
        // Viewport meta tag 강제 설정
        var viewport = document.querySelector("meta[name=viewport]");
        if (viewport) {
          viewport.content = "width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no";
        } else {
          var meta = document.createElement('meta');
          meta.name = "viewport";
          meta.content = "width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no";
          document.getElementsByTagName('head')[0].appendChild(meta);
        }
        
        // iOS전용 gesture 이벤트 방지
        document.addEventListener('gesturestart', function(e) {
          e.preventDefault();
        });
        
        document.addEventListener('gesturechange', function(e) {
          e.preventDefault();
        });
        
        document.addEventListener('gestureend', function(e) {
          e.preventDefault();
        });
        
        // Double tap zoom 방지 (iOS)
        var lastTouchEnd = 0;
        document.addEventListener('touchend', function(event) {
          var now = Date.now();
          if (now - lastTouchEnd <= 300) {
            event.preventDefault();
          }
          lastTouchEnd = now;
        }, false);
        
        console.log('iOS Zoom prevention injected');
      ''',
      );
    } else {
      // Android는 viewport 설정만
      await controller.evaluateJavascript(
        source: '''
        var viewport = document.querySelector("meta[name=viewport]");
        if (viewport) {
          viewport.content = "width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no";
        }
        console.log('Android viewport set');
      ''',
      );
    }
  }

  /// 네이티브 Google 로그인 처리
  Future<void> _handleNativeGoogleSignIn() async {
    print('WebView: Starting native Google sign-in...');

    // 로그인 시작 - 로딩 표시
    setState(() {
      _isSigningIn = true;
    });

    try {
      final result = await GoogleAuthService.signInWithGoogle();
      print('WebView: Sign-in result: ${result['success']}');

      if (result['success']) {
        if (result['webSessionData'] != null) {
          // Supabase 세션 데이터를 직접 WebView에 전달
          print('WebView: Sending session data directly to WebView');
          await _sendSupabaseSessionToWebView(result['webSessionData']);
          // 로그인 성공 후 로딩 해제는 페이지 이동 후 자동으로 처리됨
        } else if (result['needsOAuthFlow'] == true) {
          // OAuth flow가 필요한 경우 (fallback)
          print('WebView: Needs OAuth flow, using access token directly');
          await _sendGoogleTokenToWebView(
            result['accessToken'],
            result['user'],
          );
          setState(() {
            _isSigningIn = false;
          });
        } else {
          // 에러 처리
          print('WebView: No session data available');
          _showErrorMessage('Failed to get session data');
          setState(() {
            _isSigningIn = false;
          });
        }
      } else {
        // 에러 처리
        print('WebView: Sign-in failed: ${result['error']}');
        _showErrorMessage(result['error'] ?? 'Login failed');
        setState(() {
          _isSigningIn = false;
        });
      }
    } catch (e) {
      print('WebView: Exception during sign-in: $e');
      _showErrorMessage('An error occurred during sign-in: $e');
      setState(() {
        _isSigningIn = false;
      });
    }
  }

  /// WebView에 Supabase 세션 직접 전달 (새로운 방법)
  Future<void> _sendSupabaseSessionToWebView(
    Map<String, dynamic> sessionData,
  ) async {
    if (_webViewController == null) return;

    print('WebView: Sending Supabase session to WebView...');

    // JSON 데이터를 문자열로 변환
    final sessionJson = jsonEncode(sessionData);

    // WebView의 JavaScript 함수 호출
    final jsCode =
        '''
      (async function() {
        try {
          console.log('Receiving Supabase session from native app');
          
          const sessionData = $sessionJson;
          
          // Supabase 클라이언트가 있는지 확인
          if (window.supabase || window.__supabase) {
            const supabase = window.supabase || window.__supabase;
            
            // setSession을 사용하여 세션 설정
            const { error } = await supabase.auth.setSession({
              access_token: sessionData.access_token,
              refresh_token: sessionData.refresh_token
            });
            
            if (error) {
              console.error('Failed to set Supabase session:', error);
              return;
            }
            
            console.log('Supabase session set successfully');
            
            // auth-store의 checkUser 호출하여 사용자 정보 업데이트
            if (window.authStore && window.authStore.checkUser) {
              await window.authStore.checkUser();
            }
            
            // 페이지 새로고침 (로딩 상태는 페이지 로드 후 자동 해제)
            window.location.href = '/';
          } else {
            // Supabase 클라이언트가 없는 경우 localStorage 직접 설정
            console.log('Setting session via localStorage');
            
            const storageKey = 'sb-fnnuxaqhwvaeiyfjjatn-auth-token';
            const storageData = {
              access_token: sessionData.access_token,
              refresh_token: sessionData.refresh_token,
              expires_at: sessionData.expires_at,
              expires_in: sessionData.expires_in,
              token_type: sessionData.token_type,
              user: sessionData.user
            };
            
            localStorage.setItem(storageKey, JSON.stringify(storageData));
            
            // 페이지 새로고침 (로딩 상태는 페이지 로드 후 자동 해제)
            window.location.href = '/';
          }
        } catch (error) {
          console.error('Error setting session:', error);
        }
      })();
    ''';

    await _webViewController!.evaluateJavascript(source: jsCode);
    print('WebView: Session sent to WebView');
  }

  /// WebView에 세션 정보 전달 (기존 방법 - fallback)
  Future<void> _sendSessionToWebView(dynamic session) async {
    if (session == null || _webViewController == null) return;

    print('WebView: Sending session to WebView...');
    print('WebView: Session user email: ${session.user.email}');

    // WebView의 JavaScript 함수 호출
    final jsCode =
        '''
      console.log('Received session from native app');
      
      // 직접 로컬 스토리지에 세션 저장
      const sessionData = {
        access_token: '${session.accessToken}',
        refresh_token: '${session.refreshToken ?? ''}',
        expires_at: ${session.expiresAt ?? 0},
        user: {
          id: '${session.user.id}',
          email: '${session.user.email}',
          user_metadata: ${session.user.userMetadata ?? '{}'}
        }
      };
      
      // Supabase 세션 형식으로 저장
      localStorage.setItem('supabase.auth.token', JSON.stringify(sessionData));
      
      // 페이지 새로고침하여 세션 적용
      window.location.href = '/';
    ''';

    await _webViewController!.evaluateJavascript(source: jsCode);
    print('WebView: Session sent to WebView');
  }

  /// Google 토큰을 WebView에 전달 (대체 방법)
  Future<void> _sendGoogleTokenToWebView(
    String? accessToken,
    dynamic googleUser,
  ) async {
    if (accessToken == null || _webViewController == null) return;

    print('WebView: Sending Google token to WebView');

    // WebView의 JavaScript 함수 호출
    await _webViewController!.evaluateJavascript(
      source:
          '''
      if (window.handleGoogleSignInToken) {
        window.handleGoogleSignInToken({
          success: true,
          accessToken: '$accessToken',
          user: {
            email: '${googleUser.email}',
            displayName: '${googleUser.displayName}',
            id: '${googleUser.id}'
          }
        });
      } else {
        console.log('handleGoogleSignInToken not found');
      }
    ''',
    );
  }

  /// 네이티브 Apple 로그인 처리
  Future<void> _handleNativeAppleSignIn() async {
    // Android에서는 웹 OAuth로 처리 - 웹페이지에서 직접 처리하도록 함
    if (Platform.isAndroid) {
      print('WebView: Android detected, should use web OAuth for Apple login');
      // Android에서는 웹페이지에서 직접 처리하므로 여기서는 아무것도 하지 않음
      // 웹페이지의 handleAppleLogin 함수가 이미 웹 OAuth를 처리함
      return;
    }

    // iOS에서는 네이티브 로그인 사용
    print('WebView: Starting native Apple sign-in for iOS...');

    // 로그인 시작 - 로딩 표시
    setState(() {
      _isSigningIn = true;
    });

    try {
      final result = await AppleAuthService.signInWithApple();
      print('WebView: Apple sign-in result: ${result['success']}');

      if (result['success']) {
        if (result['webSessionData'] != null) {
          // Supabase 세션 데이터를 직접 WebView에 전달
          print('WebView: Sending Apple session data directly to WebView');
          await _sendSupabaseSessionToWebView(result['webSessionData']);
          // 로그인 성공 후 로딩 해제는 페이지 이동 후 자동으로 처리됨
        } else {
          // 에러 처리
          print('WebView: No Apple session data available');
          _showErrorMessage('Failed to get Apple session data');
          setState(() {
            _isSigningIn = false;
          });
        }
      } else {
        // 에러 처리
        print('WebView: Apple sign-in failed: ${result['error']}');

        // 사용자가 취소한 경우 에러 메시지 표시 안 함
        if (result['error'] != 'User cancelled sign in') {
          _showErrorMessage(result['error'] ?? 'Apple login failed');
        }

        setState(() {
          _isSigningIn = false;
        });
      }
    } catch (e) {
      print('WebView: Exception during Apple sign-in: $e');
      _showErrorMessage('An error occurred during Apple sign-in: $e');
      setState(() {
        _isSigningIn = false;
      });
    }
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
