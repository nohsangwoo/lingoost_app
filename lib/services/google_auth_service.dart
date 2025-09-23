import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class GoogleAuthService {
  static final _supabase = Supabase.instance.client;

  // Google Sign In 설정
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    // Android는 OAuth 2.0 Web Client ID 사용
    // iOS는 iOS Client ID 사용
    clientId: Platform.isAndroid
        ? '763014708776-r7ak2jcfao10br04njoheqpf693ig1ro.apps.googleusercontent.com' // Web Client ID
        : '763014708776-7vla6fndpmj6tpkmqus8ac8ip4icj20d.apps.googleusercontent.com', // iOS Client ID
    scopes: ['email', 'profile'],
  );

  /// iOS 네이티브 Google 로그인
  static Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      debugPrint('Starting Google Sign-In...');

      // 이전 로그인 세션 정리
      await _googleSignIn.signOut();

      // 1. Google Sign-In 실행
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      debugPrint('Google Sign-In result: ${googleUser?.email}');

      if (googleUser == null) {
        debugPrint('User cancelled Google Sign-In');
        return {'success': false, 'error': 'User cancelled sign in'};
      }

      // 2. Authentication 정보 획득
      debugPrint('Getting authentication tokens...');
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final String? idToken = googleAuth.idToken;
      final String? googleAccessToken = googleAuth.accessToken;

      debugPrint('ID Token exists: ${idToken != null}');
      debugPrint('Access Token exists: ${googleAccessToken != null}');

      if (idToken == null && googleAccessToken == null) {
        debugPrint('No tokens received from Google');
        return {'success': false, 'error': 'No tokens received'};
      }

      // 3. Supabase로 로그인
      debugPrint('Signing in to Supabase...');

      AuthResponse response;

      if (idToken != null) {
        // ID Token이 있는 경우
        response = await _supabase.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: googleAccessToken,
        );
      } else if (googleAccessToken != null) {
        // Access Token만 있는 경우 (대체 방법)
        debugPrint('Only access token available, trying alternative approach');

        // Google 사용자 정보를 직접 전달
        return {
          'success': true,
          'needsOAuthFlow': true,
          'accessToken': googleAccessToken,
          'user': googleUser,
        };
      } else {
        return {'success': false, 'error': 'No valid tokens'};
      }

      debugPrint('Supabase response: ${response.session?.user.email}');

      if (response.session == null) {
        debugPrint('Failed to create Supabase session');
        return {'success': false, 'error': 'Failed to create session'};
      }

      // 4. 세션 정보를 WebView에 직접 전달할 수 있도록 준비
      final sessionJson = response.session!.toJson();

      debugPrint('=== SUPABASE SESSION ANALYSIS ===');
      debugPrint('Session.toJson: $sessionJson');
      debugPrint('Access token exists: ${sessionJson['access_token'] != null}');
      debugPrint(
        'Refresh token exists: ${sessionJson['refresh_token'] != null}',
      );

      // WebView에 직접 전달할 세션 데이터 준비
      final webSessionData = {
        'access_token': sessionJson['access_token'],
        'refresh_token': sessionJson['refresh_token'],
        'expires_at': sessionJson['expires_at'],
        'expires_in': sessionJson['expires_in'],
        'token_type': sessionJson['token_type'],
        'user': sessionJson['user'],
      };

      return {
        'success': true,
        'session': response.session,
        'user': response.user,
        'webSessionData': webSessionData, // WebView에 직접 전달할 세션 데이터
      };
    } catch (error) {
      debugPrint('Google Sign-In Error: $error');
      return {'success': false, 'error': error.toString()};
    }
  }

  /// 서버에 핸드오프 코드 요청
  static Future<String?> _createHandoffCode({
    required String accessToken,
    required String refreshToken,
  }) async {
    try {
      debugPrint('Requesting handoff code from server...');
      debugPrint('URL: https://www.medikk.com/api/mobile/handoff');
      debugPrint('Access token length: ${accessToken.length}');
      debugPrint('Refresh token: "$refreshToken"');
      debugPrint('Refresh token length: ${refreshToken.length}');

      final requestBody = {
        'refreshToken': refreshToken.isNotEmpty ? refreshToken : null,
        'accessToken': accessToken,
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

  /// WebView 로그인 세션 전달
  static Future<void> setupWebViewSession(String handoffCode) async {
    // WebView Controller에서 이 URL로 이동
    // final consumeUrl = 'https://www.medikk.com/auth/consume?code=$handoffCode';

    // WebView에서 처리
    // webViewController.loadUrl(consumeUrl);
  }

  /// 로그아웃
  static Future<void> signOut() async {
    await _googleSignIn.signOut();
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
}
