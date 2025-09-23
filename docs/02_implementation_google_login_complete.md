# Supabase + Flutter WebView Google 로그인 완벽 가이드

## 📋 목차
1. [개요](#개요)
2. [Google Cloud Console 설정](#google-cloud-console-설정)
3. [Supabase 설정](#supabase-설정)
4. [Flutter 앱 설정](#flutter-앱-설정)
5. [WebView 인증 연동](#webview-인증-연동)
6. [트러블슈팅](#트러블슈팅)

---

## 개요

Flutter 앱에서 Google 로그인을 구현하고, WebView로 열리는 웹 애플리케이션에 인증 상태를 전달하는 완전한 가이드입니다.

### 아키텍처
```
[Flutter App]
    ↓ Google Sign-In SDK
[Google OAuth]
    ↓ ID Token
[Supabase Auth]
    ↓ Session (access_token, refresh_token)
[WebView JavaScript Bridge]
    ↓ setSession()
[Next.js Web App]
```

---

## Google Cloud Console 설정

### 1. 프로젝트 생성
1. [Google Cloud Console](https://console.cloud.google.com) 접속
2. 새 프로젝트 생성 또는 기존 프로젝트 선택

### 2. OAuth 동의 화면 구성
1. **APIs & Services** → **OAuth consent screen**
2. User Type: **External** 선택
3. 필수 정보 입력:
   - 앱 이름
   - 사용자 지원 이메일
   - 개발자 연락처 정보
4. Scopes: `email`, `profile` 추가

### 3. OAuth 2.0 클라이언트 ID 생성

#### 🌐 Web Application Client (필수!)
1. **APIs & Services** → **Credentials** → **Create Credentials** → **OAuth client ID**
2. Application type: **Web application**
3. Name: `Supabase Auth`
4. Authorized redirect URIs:
   ```
   https://YOUR_PROJECT_ID.supabase.co/auth/v1/callback
   ```
5. **생성된 Client ID 저장** (예: `395429217529-vns0d6t500qq89m8vvgm9u3bm8svkepc.apps.googleusercontent.com`)

#### 📱 iOS Client
1. Application type: **iOS**
2. Bundle ID: `com.ludgi.medik_app` (또는 실제 Bundle ID)
3. **생성된 Client ID 저장**

#### 🤖 Android Clients (3개 필요)

> **⚠️ 중요한 개념 이해:**
> - **Android Client ID = 앱 검증용 (필수 등록, 코드에서 사용 안 함)**
> - **Web Client ID = 실제 인증 토큰 발급용 (코드에서 사용)**
> 
> Android Client를 만들지 않으면 ApiException: 10 에러가 발생합니다.
> 하지만 실제 코드에서는 Web Client ID를 사용합니다!

각각 다른 SHA-1 인증서로 생성:

1. **디버그용 Client**
   - Package name: `com.ludgi.medik_app`
   - SHA-1: 디버그 키스토어의 SHA-1
   ```bash
   # 디버그 SHA-1 확인 명령어
   cd android && ./gradlew signingReport
   # Variant: debug 섹션의 SHA1 값 복사
   ```

2. **릴리즈용 Client**
   - Package name: 동일
   - SHA-1: 릴리즈 키스토어의 SHA-1

3. **Play Store용 Client**
   - Package name: 동일
   - SHA-1: Play Console → 앱 무결성 → 앱 서명에서 확인

**왜 Android는 Web Client ID를 사용하나요?**
1. Supabase는 서버에서 Google OAuth를 처리
2. 서버는 Web Client ID로 발급된 ID Token만 검증 가능
3. Android Client ID는 "이 앱이 진짜다"를 확인하는 용도
4. 검증된 앱만 Web Client ID로 토큰 요청 허용

---

## Supabase 설정

### 1. Supabase Dashboard 설정
1. [Supabase Dashboard](https://app.supabase.com) → Project → Authentication → Providers
2. **Google** Provider 활성화
3. **Client ID**: Web Application Client ID 입력 (⚠️ Web Client ID를 사용해야 함!)
4. **Client Secret**: Web Application Client Secret 입력
5. Save

### 2. Redirect URL 확인
```
https://YOUR_PROJECT_ID.supabase.co/auth/v1/callback
```

---

## Flutter 앱 설정

### 1. Dependencies 추가 (`pubspec.yaml`)
```yaml
dependencies:
  google_sign_in: ^6.2.2
  supabase_flutter: ^2.0.0
  flutter_inappwebview: ^6.0.0
  http: ^1.2.0
```

### 2. iOS 설정

#### Info.plist
```xml
<!-- Google Sign In URL Scheme -->
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <!-- REVERSED_CLIENT_ID from GoogleService-Info.plist -->
            <string>com.googleusercontent.apps.YOUR_REVERSED_CLIENT_ID</string>
        </array>
    </dict>
</array>

<!-- WebView 설정 -->
<key>UIRequiresFullScreen</key>
<false/>
```

### 3. Android 설정

#### ⚠️ 중요: Android는 Web Client ID를 사용!

> **Android Client ID vs Web Client ID 정리:**
> - **Google Console에서**: Android Client 3개 모두 생성 (필수!)
> - **코드에서 사용**: Web Client ID만 사용
> - **이유**: Android Client는 앱 검증용, Web Client는 토큰 발급용

#### android/app/src/main/res/values/strings.xml (생성)
```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Your App Name</string>
    <!-- Google Sign-In: Web Application Client ID 사용! -->
    <string name="default_web_client_id">YOUR_WEB_CLIENT_ID.apps.googleusercontent.com</string>
</resources>
```

#### android/app/src/main/AndroidManifest.xml
```xml
<uses-permission android:name="android.permission.INTERNET" />
```

### 4. Google 인증 서비스 구현

#### lib/services/google_auth_service.dart
```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GoogleAuthService {
  static final _supabase = Supabase.instance.client;

  // Google Sign In 설정
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    // ⚠️ Android는 Web Client ID, iOS는 iOS Client ID 사용
    clientId: Platform.isAndroid
        ? 'WEB_CLIENT_ID.apps.googleusercontent.com'  // Web Client ID
        : 'IOS_CLIENT_ID.apps.googleusercontent.com', // iOS Client ID
    scopes: ['email', 'profile'],
  );

  /// Google 로그인
  static Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      debugPrint('Starting Google Sign-In...');
      
      // 이전 로그인 세션 정리
      await _googleSignIn.signOut();

      // 1. Google Sign-In 실행
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        return {'success': false, 'error': 'User cancelled sign in'};
      }

      // 2. Authentication 정보 획득
      final GoogleSignInAuthentication googleAuth = 
          await googleUser.authentication;

      final String? idToken = googleAuth.idToken;
      final String? googleAccessToken = googleAuth.accessToken;

      if (idToken == null) {
        return {'success': false, 'error': 'No ID token received'};
      }

      // 3. Supabase로 로그인
      final response = await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: googleAccessToken,
      );

      if (response.session == null) {
        return {'success': false, 'error': 'Failed to create session'};
      }

      // 4. WebView에 전달할 세션 데이터 준비
      final sessionJson = response.session!.toJson();
      
      final webSessionData = {
        'access_token': sessionJson['access_token'],
        'refresh_token': sessionJson['refresh_token'],
        'expires_at': sessionJson['expires_at'],
        'expires_in': sessionJson['expires_in'],
        'token_type': sessionJson['token_type'],
        'user': sessionJson['user']
      };

      return {
        'success': true,
        'session': response.session,
        'user': response.user,
        'webSessionData': webSessionData,
      };
    } catch (error) {
      debugPrint('Google Sign-In Error: $error');
      return {
        'success': false,
        'error': error.toString(),
      };
    }
  }

  /// 로그아웃
  static Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _supabase.auth.signOut();
  }
}
```

### 5. 메인 앱 초기화

#### lib/main.dart
```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Supabase 초기화
  await Supabase.initialize(
    url: 'YOUR_SUPABASE_URL',
    anonKey: 'YOUR_SUPABASE_ANON_KEY',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
  
  runApp(const MyApp());
}
```

---

## WebView 인증 연동

### 1. WebView 화면 구현

#### lib/screens/webview_screen.dart
```dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:your_app/services/google_auth_service.dart';

class WebViewScreen extends StatefulWidget {
  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  bool _isSigningIn = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri('https://your-domain.com'),
              ),
              initialSettings: InAppWebViewSettings(
                // 미디어 설정
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                
                // 줌 차단
                supportZoom: false,
                builtInZoomControls: false,
                displayZoomControls: false,
                
                // 기본 설정
                javaScriptEnabled: true,
                domStorageEnabled: true,
                useWideViewPort: true,
                loadWithOverviewMode: true,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
                _setupJavaScriptHandlers(controller);
              },
              onLoadStop: (controller, url) async {
                setState(() {
                  _isLoading = false;
                  _isSigningIn = false;
                });
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final url = navigationAction.request.url?.toString() ?? '';
                
                // Google OAuth URL 감지 시 네이티브 로그인 실행
                if (url.contains('accounts.google.com/o/oauth2')) {
                  _handleNativeGoogleSignIn();
                  return NavigationActionPolicy.CANCEL;
                }
                
                return NavigationActionPolicy.ALLOW;
              },
            ),
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
                        Text('로그인 중...'),
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
    controller.addJavaScriptHandler(
      handlerName: 'googleSignIn',
      callback: (args) async {
        await _handleNativeGoogleSignIn();
      },
    );
  }

  /// 네이티브 Google 로그인 처리
  Future<void> _handleNativeGoogleSignIn() async {
    setState(() {
      _isSigningIn = true;
    });
    
    try {
      final result = await GoogleAuthService.signInWithGoogle();
      
      if (result['success']) {
        if (result['webSessionData'] != null) {
          await _sendSupabaseSessionToWebView(result['webSessionData']);
        }
      } else {
        _showErrorMessage(result['error'] ?? 'Login failed');
        setState(() {
          _isSigningIn = false;
        });
      }
    } catch (e) {
      _showErrorMessage('An error occurred: $e');
      setState(() {
        _isSigningIn = false;
      });
    }
  }

  /// WebView에 Supabase 세션 전달
  Future<void> _sendSupabaseSessionToWebView(Map<String, dynamic> sessionData) async {
    if (_webViewController == null) return;
    
    final sessionJson = jsonEncode(sessionData);
    
    final jsCode = '''
      (async function() {
        try {
          const sessionData = $sessionJson;
          
          // Supabase 클라이언트가 있는 경우
          if (window.supabase || window.__supabase) {
            const supabase = window.supabase || window.__supabase;
            
            // setSession으로 세션 설정
            const { error } = await supabase.auth.setSession({
              access_token: sessionData.access_token,
              refresh_token: sessionData.refresh_token
            });
            
            if (!error) {
              console.log('Session set successfully');
              window.location.href = '/';
            }
          } else {
            // localStorage 직접 설정 (fallback)
            const storageKey = 'sb-YOUR_PROJECT_ID-auth-token';
            localStorage.setItem(storageKey, JSON.stringify(sessionData));
            window.location.href = '/';
          }
        } catch (error) {
          console.error('Error setting session:', error);
        }
      })();
    ''';
    
    await _webViewController!.evaluateJavascript(source: jsCode);
  }
  
  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}
```

### 2. 웹 애플리케이션 설정 (Next.js)

#### app/clientLayout.tsx
```typescript
'use client'

import { useEffect } from 'react'
import { createClient } from '@/lib/supabase/client'
import useAuthStore from '@/store/auth-store'

export default function ClientLayout({ children }) {
  useEffect(() => {
    // WebView Bridge: Supabase client를 전역으로 노출
    if (typeof window !== 'undefined') {
      (window as any).__supabase = createClient()
      ;(window as any).authStore = useAuthStore
      console.log('WebView Bridge initialized')
    }
  }, [])

  return <>{children}</>
}
```

---

## 트러블슈팅

### 🔴 ApiException: 10 (Android)
**원인**: SHA-1 인증서 불일치 또는 잘못된 Client ID 사용

**해결**:
1. Web Client ID를 사용하고 있는지 확인 (Android는 Web Client ID 필수!)
2. `strings.xml`에 올바른 Web Client ID가 설정되어 있는지 확인
3. SHA-1 인증서가 Google Console에 등록되어 있는지 확인
4. 패키지명이 정확히 일치하는지 확인

### 🔴 로그인 후 세션이 전달되지 않음
**원인**: WebView와 네이티브 앱 간 통신 실패

**해결**:
1. WebView에서 JavaScript가 활성화되어 있는지 확인
2. `window.__supabase` 객체가 웹에서 노출되어 있는지 확인
3. localStorage 키 이름이 Supabase 프로젝트 ID와 일치하는지 확인

### 🔴 Android WebView에서 터치/스크롤 안 됨
**원인**: 줌 방지 JavaScript 코드가 터치 이벤트 차단

**해결**:
```dart
// iOS만 JavaScript 줌 방지 적용
if (Platform.isIOS) {
  // iOS 전용 줌 방지 코드
} else {
  // Android는 WebView 설정으로만 처리
}
```

### 🔴 비디오가 전체화면으로 재생됨 (iOS)
**원因**: iOS WebView의 기본 동작

**해결**:
```dart
InAppWebViewSettings(
  allowsInlineMediaPlayback: true,  // 인라인 재생 허용
  mediaPlaybackRequiresUserGesture: false,  // 자동 재생 허용
)
```

---

## 체크리스트

### Google Cloud Console
- [ ] OAuth 동의 화면 구성 완료
- [ ] Web Application Client 생성
- [ ] iOS Client 생성
- [ ] Android Client 생성 (디버그/릴리즈/Play Store)
- [ ] 모든 SHA-1 인증서 등록

### Supabase
- [ ] Google Provider 활성화
- [ ] Web Client ID & Secret 입력
- [ ] Redirect URL 확인

### Flutter
- [ ] Dependencies 추가
- [ ] iOS Info.plist 설정
- [ ] Android strings.xml 생성
- [ ] GoogleAuthService 구현
- [ ] WebViewScreen 구현

### 테스트
- [ ] iOS 디버그 빌드 테스트
- [ ] Android 디버그 빌드 테스트
- [ ] WebView 세션 전달 테스트
- [ ] 프로덕션 빌드 테스트

---

## 중요 포인트 정리

1. **Android는 반드시 Web Client ID를 사용해야 함** (iOS Client ID 사용 시 ApiException: 10 발생)
2. **Supabase Dashboard에도 Web Client ID를 설정**해야 함
3. **SHA-1 인증서는 총 3개** 필요 (디버그/릴리즈/Play Store)
4. **WebView와 네이티브 앱 간 세션 공유**는 JavaScript Bridge를 통해 구현
5. **플랫폼별 설정 차이**를 반드시 고려 (iOS vs Android)

---

## 참고 자료

- [Google Sign-In Flutter Plugin](https://pub.dev/packages/google_sign_in)
- [Supabase Flutter Documentation](https://supabase.com/docs/guides/auth/social-login/auth-google)
- [Flutter InAppWebView](https://pub.dev/packages/flutter_inappwebview)
- [Google Cloud Console](https://console.cloud.google.com)
- [Supabase Dashboard](https://app.supabase.com)