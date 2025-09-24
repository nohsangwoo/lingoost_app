# Flutter Apple 네이티브 로그인 구현 가이드

## 개요
Flutter 앱에서 네이티브 Apple Sign-In을 구현하고, WebView로 열리는 웹 애플리케이션에 인증 상태를 전달하는 완전한 가이드입니다.

## 목차
1. [사전 준비](#사전-준비)
2. [패키지 설치](#패키지-설치)
3. [플랫폼별 설정](#플랫폼별-설정)
4. [코드 구현](#코드-구현)
5. [테스트 및 검증](#테스트-및-검증)

## 사전 준비

### Apple Developer Console 설정
1. **App ID 생성/설정**
   - Identifier: `com.ludgi.medik_app`
   - Sign in with Apple 기능 활성화

2. **Service ID 생성 (Android/Web용)**
   - Identifier: `com.ludgi.medik-service`
   - Sign in with Apple 활성화
   - Return URLs 설정:
     ```
     https://fnnuxaqhwvaeiyfjjatn.supabase.co/auth/v1/callback
     ```

3. **Key 생성**
   - Sign in with Apple 용 Key 생성
   - Key ID와 .p8 파일 저장

### Supabase 설정
1. Authentication → Providers → Apple 활성화
2. Service ID (Client ID) 입력: `com.ludgi.medik-service`
3. Secret Key 입력 (생성한 JWT)

## 패키지 설치

### pubspec.yaml
```yaml
dependencies:
  # Authentication
  google_sign_in: ^6.2.2
  supabase_flutter: ^2.10.0
  sign_in_with_apple: ^6.1.3  # Apple Sign-In 패키지
  
  # Advanced WebView
  flutter_inappwebview: ^6.0.0
  
  # HTTP requests
  http: ^1.2.0
```

설치 명령어:
```bash
flutter pub get
```

## 플랫폼별 설정

### iOS 설정

#### 1. Xcode에서 Capability 추가
1. Xcode에서 프로젝트 열기
2. Runner 타겟 선택
3. Signing & Capabilities 탭
4. "+ Capability" 클릭
5. "Sign in with Apple" 추가

#### 2. Info.plist 설정 (자동으로 추가됨)
Capability를 추가하면 자동으로 설정됩니다.

### Android 설정

#### 1. AndroidManifest.xml
```xml
<!-- 인터넷 권한 (이미 있을 가능성 높음) -->
<uses-permission android:name="android.permission.INTERNET" />
```

#### 2. 추가 설정
Android는 Web OAuth 플로우를 사용하므로 Service ID가 필요합니다.
코드에서 이미 처리되어 있습니다.

## 코드 구현

### 1. Apple Auth Service (`lib/services/apple_auth_service.dart`)

```dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AppleAuthService {
  static final _supabase = Supabase.instance.client;

  /// Apple 로그인 (iOS & Android)
  static Future<Map<String, dynamic>> signInWithApple() async {
    try {
      debugPrint('Starting Apple Sign-In...');
      debugPrint('Platform: ${Platform.operatingSystem}');

      // 1. Apple Sign-In 가능 여부 확인
      final isAvailable = await SignInWithApple.isAvailable();
      if (!isAvailable) {
        return {
          'success': false,
          'error': 'Apple Sign-In is not available on this device'
        };
      }

      // 2. Apple Sign-In 실행
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        webAuthenticationOptions: Platform.isAndroid
            ? WebAuthenticationOptions(
                clientId: 'com.ludgi.medik-service', // Service ID
                redirectUri: Uri.parse(
                  'https://fnnuxaqhwvaeiyfjjatn.supabase.co/auth/v1/callback',
                ),
              )
            : null,
      );

      // 3. 토큰 확인
      if (credential.identityToken == null) {
        return {
          'success': false,
          'error': 'No identity token received from Apple'
        };
      }

      // 4. Supabase로 로그인
      AuthResponse response;
      if (Platform.isIOS) {
        response = await _supabase.auth.signInWithIdToken(
          provider: OAuthProvider.apple,
          idToken: credential.identityToken!,
          accessToken: credential.authorizationCode,
        );
      } else {
        response = await _supabase.auth.signInWithIdToken(
          provider: OAuthProvider.apple,
          idToken: credential.identityToken!,
        );
      }

      if (response.session == null) {
        return {'success': false, 'error': 'Failed to create session'};
      }

      // 5. WebView용 세션 데이터 준비
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
      debugPrint('Apple Sign-In Error: $error');
      
      if (error is SignInWithAppleAuthorizationException) {
        if (error.code == AuthorizationErrorCode.canceled) {
          return {
            'success': false,
            'error': 'User cancelled sign in'
          };
        }
      }
      
      return {
        'success': false,
        'error': error.toString(),
      };
    }
  }

  /// 로그아웃
  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
```

### 2. WebView Screen 수정 (`lib/screens/webview_screen.dart`)

#### Import 추가
```dart
import 'package:medik_app/services/apple_auth_service.dart';
```

#### JavaScript 핸들러 추가
```dart
void _setupJavaScriptHandlers(InAppWebViewController controller) {
  // 기존 Google 핸들러...
  
  // Apple 로그인 핸들러 추가
  controller.addJavaScriptHandler(
    handlerName: 'appleSignIn',
    callback: (args) async {
      print('WebView requested Apple Sign-In');
      await _handleNativeAppleSignIn();
    },
  );
}
```

#### Apple 로그인 처리 함수
```dart
Future<void> _handleNativeAppleSignIn() async {
  print('WebView: Starting native Apple sign-in...');
  
  setState(() {
    _isSigningIn = true;
  });
  
  try {
    final result = await AppleAuthService.signInWithApple();
    
    if (result['success']) {
      if (result['webSessionData'] != null) {
        // Supabase 세션을 WebView에 전달
        await _sendSupabaseSessionToWebView(result['webSessionData']);
      } else {
        _showErrorMessage('Failed to get Apple session data');
        setState(() {
          _isSigningIn = false;
        });
      }
    } else {
      // 사용자가 취소한 경우 에러 메시지 표시 안 함
      if (result['error'] != 'User cancelled sign in') {
        _showErrorMessage(result['error'] ?? 'Apple login failed');
      }
      setState(() {
        _isSigningIn = false;
      });
    }
  } catch (e) {
    _showErrorMessage('An error occurred during Apple sign-in: $e');
    setState(() {
      _isSigningIn = false;
    });
  }
}
```

## WebView와의 통신

### JavaScript Bridge를 통한 세션 전달
```dart
Future<void> _sendSupabaseSessionToWebView(Map<String, dynamic> sessionData) async {
  if (_webViewController == null) return;
  
  final sessionJson = jsonEncode(sessionData);
  
  final jsCode = '''
    (async function() {
      try {
        const sessionData = $sessionJson;
        
        if (window.supabase || window.__supabase) {
          const supabase = window.supabase || window.__supabase;
          
          // Supabase 세션 설정
          const { error } = await supabase.auth.setSession({
            access_token: sessionData.access_token,
            refresh_token: sessionData.refresh_token
          });
          
          if (!error) {
            console.log('Apple session set successfully');
            window.location.href = '/';
          }
        }
      } catch (error) {
        console.error('Error setting session:', error);
      }
    })();
  ''';
  
  await _webViewController!.evaluateJavascript(source: jsCode);
}
```

## 테스트 및 검증

### iOS 테스트
1. **실제 디바이스 필요**: iOS 시뮬레이터에서는 Apple Sign-In이 작동하지 않음
2. **개발자 계정 필요**: Apple Developer Program 가입 필요
3. **테스트 절차**:
   ```bash
   flutter clean
   flutter pub get
   cd ios && pod install
   flutter run --release
   ```

### Android 테스트
1. **에뮬레이터 가능**: Android 에뮬레이터에서도 테스트 가능
2. **Web OAuth 플로우**: 브라우저를 통한 인증
3. **테스트 절차**:
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

## 트러블슈팅

### 일반적인 문제

#### 1. "Sign in with Apple isn't available"
- **원인**: iOS 13 미만 또는 설정 미완료
- **해결**: iOS 버전 확인, Capability 추가 확인

#### 2. "Invalid client" 에러
- **원인**: Service ID 불일치
- **해결**: Apple Developer Console과 코드의 Service ID 확인

#### 3. Android에서 리다이렉트 실패
- **원인**: Return URL 설정 오류
- **해결**: Apple Developer Console에서 Return URL 확인

### 디버깅 팁
1. **로그 확인**: `flutter logs`로 실시간 로그 확인
2. **네트워크 모니터링**: Charles Proxy 등으로 네트워크 요청 확인
3. **Supabase 로그**: Supabase Dashboard에서 Auth 로그 확인

## 체크리스트

### 개발 전
- [ ] Apple Developer Program 가입
- [ ] App ID에 Sign in with Apple 활성화
- [ ] Service ID 생성 (Android용)
- [ ] Supabase에 Apple Provider 설정

### 구현
- [ ] sign_in_with_apple 패키지 추가
- [ ] AppleAuthService 클래스 생성
- [ ] WebView 핸들러 추가
- [ ] iOS Capability 추가

### 테스트
- [ ] iOS 실제 디바이스 테스트
- [ ] Android 에뮬레이터/디바이스 테스트
- [ ] 로그인 플로우 완료 확인
- [ ] WebView 세션 전달 확인

## 보안 고려사항

1. **Identity Token 검증**: 서버 측에서 Apple의 공개 키로 토큰 검증
2. **Nonce 사용**: 재생 공격 방지를 위한 nonce 구현 (선택사항)
3. **세션 관리**: 토큰 만료 시간 관리 및 자동 갱신

## 참고 자료

- [Apple Developer - Sign in with Apple](https://developer.apple.com/sign-in-with-apple/)
- [sign_in_with_apple 패키지](https://pub.dev/packages/sign_in_with_apple)
- [Supabase Apple Auth](https://supabase.com/docs/guides/auth/social-login/auth-apple)
- [Flutter 공식 문서](https://flutter.dev/)