import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class AndroidFCMHandler {
  static final AndroidFCMHandler _instance = AndroidFCMHandler._internal();
  factory AndroidFCMHandler() => _instance;
  AndroidFCMHandler._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();

  // 초기화
  Future<void> initialize() async {
    await _setupLocalNotifications();
    await _setupFCMHandlers();
    await _requestPermissions();
  }

  // 로컬 알림 설정
  Future<void> _setupLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidSettings);
    
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
  }

  // FCM 핸들러 설정
  Future<void> _setupFCMHandlers() async {
    // 포그라운드 메시지 처리
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // 백그라운드 메시지 처리
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    
    // 앱이 백그라운드에서 열렸을 때
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);
    
    // 종료 상태에서 알림으로 앱이 열렸을 때
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationOpen(initialMessage);
    }
  }

  // 권한 요청
  Future<void> _requestPermissions() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    
    print('[AndroidFCM] 권한 상태: ${settings.authorizationStatus}');
  }

  // FCM 토큰 가져오기 및 저장
  Future<String?> getAndSaveToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        print('[AndroidFCM] FCM 토큰: $token');
        await _saveTokenToServer(token);
      }
      return token;
    } catch (e) {
      print('[AndroidFCM] 토큰 가져오기 실패: $e');
      return null;
    }
  }

  // 토큰 서버에 저장
  Future<void> _saveTokenToServer(String token) async {
    try {
      final response = await http.post(
        Uri.parse('https://www.medikk.com/api/fcm/token'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'token': token,
          'platform': 'android',
          'deviceId': 'flutter_android_${DateTime.now().millisecondsSinceEpoch}',
          'userId': null,
        }),
      );
      
      if (response.statusCode == 200) {
        print('[AndroidFCM] 토큰 저장 성공');
      } else {
        print('[AndroidFCM] 토큰 저장 실패: ${response.statusCode}');
      }
    } catch (e) {
      print('[AndroidFCM] 토큰 저장 오류: $e');
    }
  }

  // 포그라운드 메시지 처리
  void _handleForegroundMessage(RemoteMessage message) {
    print('[AndroidFCM] 포그라운드 메시지 수신: ${message.messageId}');
    
    if (message.notification != null) {
      _showLocalNotification(message);
    }
  }

  // 로컬 알림 표시
  Future<void> _showLocalNotification(RemoteMessage message) async {
    const androidDetails = AndroidNotificationDetails(
      'medik_notification_channel',
      'Medik 알림',
      channelDescription: 'Medik 앱의 주요 알림',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );
    
    const notificationDetails = NotificationDetails(android: androidDetails);
    
    await _localNotifications.show(
      message.hashCode,
      message.notification?.title ?? '알림',
      message.notification?.body ?? '',
      notificationDetails,
      payload: json.encode(message.data),
    );
  }

  // 알림 탭 처리
  void _onNotificationTap(NotificationResponse response) {
    print('[AndroidFCM] 알림 탭: ${response.payload}');
    // 필요한 경우 WebView로 데이터 전달
    if (response.payload != null) {
      final data = json.decode(response.payload!);
      // WebView 브리지를 통해 데이터 전달
    }
  }

  // 알림으로 앱 열기 처리
  void _handleNotificationOpen(RemoteMessage message) {
    print('[AndroidFCM] 알림으로 앱 열림: ${message.data}');
    // 필요한 경우 WebView로 데이터 전달
  }

  // 토큰 리프레시 리스너 설정
  void setupTokenRefreshListener() {
    _messaging.onTokenRefresh.listen((newToken) {
      print('[AndroidFCM] 토큰 리프레시: $newToken');
      _saveTokenToServer(newToken);
    });
  }
}

// 백그라운드 메시지 핸들러 (최상위 함수여야 함)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('[AndroidFCM] 백그라운드 메시지 수신: ${message.messageId}');
}