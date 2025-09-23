import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class AppleAuthService {
  static final _supabase = Supabase.instance.client;

  /// Apple 로그인 (iOS & Android)
  static Future<Map<String, dynamic>> signInWithApple() async {
    try {
      debugPrint('Starting Apple Sign-In...');
      debugPrint('Platform: ${Platform.operatingSystem}');

      // 1. Apple Sign-In 가능 여부 확인
      final isAvailable = await SignInWithApple.isAvailable();
      debugPrint('Apple Sign-In available: $isAvailable');

      if (!isAvailable) {
        return {
          'success': false,
          'error': 'Apple Sign-In is not available on this device'
        };
      }

      // 2. Apple Sign-In 실행
      // iOS의 경우 nonce를 사용하여 보안 강화
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      debugPrint('=== APPLE SIGN-IN CONFIG ===');
      debugPrint('Platform: ${Platform.operatingSystem}');
      debugPrint('Is iOS: ${Platform.isIOS}');
      debugPrint('Is Android: ${Platform.isAndroid}');
      debugPrint('Using Web Auth: ${Platform.isAndroid}');

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: Platform.isIOS ? nonce : null,
        // Android는 Web OAuth 사용
        webAuthenticationOptions: Platform.isAndroid
            ? WebAuthenticationOptions(
                clientId: 'com.ludgi.medik-service', // Service ID 사용
                redirectUri: Uri.parse(
                  'https://fnnuxaqhwvaeiyfjjatn.supabase.co/auth/v1/callback',
                ),
              )
            : null,
      );

      debugPrint('Apple credential received');
      debugPrint('User identifier: ${credential.userIdentifier}');
      debugPrint('Email: ${credential.email}');
      debugPrint('Given name: ${credential.givenName}');
      debugPrint('Family name: ${credential.familyName}');
      debugPrint('Identity token exists: ${credential.identityToken != null}');
      debugPrint(
          'Authorization code exists: ${credential.authorizationCode != null}');

      // 3. 토큰 확인
      if (credential.identityToken == null) {
        return {
          'success': false,
          'error': 'No identity token received from Apple'
        };
      }

      // 4. ID Token 디코딩해서 내용 확인 (디버깅용)
      try {
        final parts = credential.identityToken!.split('.');
        if (parts.length == 3) {
          // JWT의 payload 부분 디코딩
          final payload = parts[1];
          final normalized = base64Url.normalize(payload);
          final decoded = utf8.decode(base64Url.decode(normalized));
          final Map<String, dynamic> claims = jsonDecode(decoded);

          debugPrint('=== ID TOKEN CLAIMS ===');
          debugPrint('Audience (aud): ${claims['aud']}');
          debugPrint('Issuer (iss): ${claims['iss']}');
          debugPrint('Subject (sub): ${claims['sub']}');
          debugPrint('Email: ${claims['email']}');
          debugPrint('Full claims: $claims');
        }
      } catch (e) {
        debugPrint('Failed to decode ID token: $e');
      }

      // 5. Supabase로 로그인
      debugPrint('Signing in to Supabase with Apple credentials...');
      debugPrint(
          'Using nonce: ${Platform.isIOS ? "YES (rawNonce: ${rawNonce.substring(0, 10)}...)" : "NO"}');

      AuthResponse response;

      if (Platform.isIOS) {
        // iOS: identityToken과 rawNonce 사용
        debugPrint('iOS: Calling signInWithIdToken with nonce');
        response = await _supabase.auth.signInWithIdToken(
          provider: OAuthProvider.apple,
          idToken: credential.identityToken!,
          nonce: rawNonce,
        );
      } else {
        // Android: identityToken만 사용
        debugPrint('Android: Calling signInWithIdToken without nonce');
        response = await _supabase.auth.signInWithIdToken(
          provider: OAuthProvider.apple,
          idToken: credential.identityToken!,
        );
      }

      debugPrint('Supabase response: ${response.session?.user.email}');

      if (response.session == null) {
        debugPrint('Failed to create Supabase session');
        return {'success': false, 'error': 'Failed to create session'};
      }

      // 5. 사용자 메타데이터 업데이트 (최초 로그인 시)
      if (credential.givenName != null || credential.familyName != null) {
        try {
          final fullName = [
            credential.givenName,
            credential.familyName,
          ].where((name) => name != null).join(' ').trim();

          if (fullName.isNotEmpty) {
            await _supabase.auth.updateUser(
              UserAttributes(
                data: {
                  'full_name': fullName,
                  'given_name': credential.givenName,
                  'family_name': credential.familyName,
                },
              ),
            );
            debugPrint('User metadata updated with name: $fullName');
          }
        } catch (e) {
          debugPrint('Failed to update user metadata: $e');
          // 메타데이터 업데이트 실패는 무시 (로그인은 성공)
        }
      }

      // 6. 세션 정보를 WebView에 직접 전달할 수 있도록 준비
      final sessionJson = response.session!.toJson();

      debugPrint('=== SUPABASE SESSION ANALYSIS ===');
      debugPrint('Session.toJson: $sessionJson');
      debugPrint('Access token exists: ${sessionJson['access_token'] != null}');
      debugPrint(
          'Refresh token exists: ${sessionJson['refresh_token'] != null}');

      // WebView에 직접 전달할 세션 데이터 준비
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
        'webSessionData': webSessionData, // WebView에 직접 전달할 세션 데이터
        'appleCredential': {
          'userIdentifier': credential.userIdentifier,
          'email': credential.email,
          'givenName': credential.givenName,
          'familyName': credential.familyName,
        },
      };
    } catch (error) {
      debugPrint('Apple Sign-In Error: $error');

      // 사용자가 취소한 경우
      if (error is SignInWithAppleAuthorizationException) {
        if (error.code == AuthorizationErrorCode.canceled) {
          return {'success': false, 'error': 'User cancelled sign in'};
        }
      }

      return {
        'success': false,
        'error': error.toString(),
      };
    }
  }

  /// 서버에 핸드오프 코드 요청 (필요한 경우 사용)
  static Future<String?> _createHandoffCode({
    required String accessToken,
    required String refreshToken,
  }) async {
    try {
      debugPrint('Requesting handoff code from server...');
      debugPrint('URL: https://www.medikk.com/api/mobile/handoff');

      final requestBody = {
        'refreshToken': refreshToken.isNotEmpty ? refreshToken : null,
        'accessToken': accessToken,
        'provider': 'apple',
      };

      debugPrint('Request body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse('https://www.medikk.com/api/mobile/handoff'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      debugPrint('Handoff response status: ${response.statusCode}');
      debugPrint('Handoff response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['code'];
      }
    } catch (error) {
      debugPrint('Handoff code creation error: $error');
    }
    return null;
  }

  /// 로그아웃
  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  /// 현재 로그인 상태 확인
  static bool isSignedIn() {
    return _supabase.auth.currentSession != null;
  }

  /// 현재 사용자 정보
  static User? getCurrentUser() {
    return _supabase.auth.currentUser;
  }

  /// Apple Sign-In 가능 여부 확인
  static Future<bool> isAvailable() async {
    try {
      return await SignInWithApple.isAvailable();
    } catch (e) {
      debugPrint('Error checking Apple Sign-In availability: $e');
      return false;
    }
  }

  /// 플랫폼별 설정 정보 제공 (디버깅용)
  static Map<String, dynamic> getPlatformConfig() {
    return {
      'platform': Platform.operatingSystem,
      'isIOS': Platform.isIOS,
      'isAndroid': Platform.isAndroid,
      'bundleId': 'com.ludgi.meddikkApp',
      'serviceId': 'com.ludgi.medik-service',
      'redirectUri':
          'https://fnnuxaqhwvaeiyfjjatn.supabase.co/auth/v1/callback',
    };
  }

  /// Nonce 생성 (보안 강화)
  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  /// SHA256 해시 생성
  static String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
