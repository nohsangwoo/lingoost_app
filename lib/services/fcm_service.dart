import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import 'dart:io';

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  String? _currentToken;
  Function(String)? _onTokenRefresh;
  Function(Map<String, dynamic>)? _onMessageReceived;
  Function(Map<String, dynamic>)? _onNotificationTapped;

  // FCM 초기화
  Future<void> initialize({
    Function(String)? onTokenRefresh,
    Function(Map<String, dynamic>)? onMessageReceived,
    Function(Map<String, dynamic>)? onNotificationTapped,
  }) async {
    _onTokenRefresh = onTokenRefresh;
    _onMessageReceived = onMessageReceived;
    _onNotificationTapped = onNotificationTapped;

    // 권한 요청
    await _requestPermission();
    
    // 로컬 알림 초기화
    await _initializeLocalNotifications();
    
    // FCM 토큰 획득
    await _getToken();
    
    // 토큰 갱신 리스너
    _messaging.onTokenRefresh.listen(_handleTokenRefresh);
    
    // 포그라운드 메시지 핸들러
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    
    // 백그라운드 메시지 클릭 핸들러
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
    
    // 앱이 종료된 상태에서 알림을 통해 열렸는지 확인
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }
  }

  // 권한 요청
  Future<void> _requestPermission() async {
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    
    print('FCM Permission status: ${settings.authorizationStatus}');
  }

  // 로컬 알림 초기화
  Future<void> _initializeLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const settings = InitializationSettings(android: android, iOS: ios);
    
    await _localNotifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          final data = json.decode(response.payload!);
          _onNotificationTapped?.call(data);
        }
      },
    );
  }

  // FCM 토큰 획득
  Future<String?> _getToken() async {
    try {
      print('📲 Getting FCM token...');
      _currentToken = await _messaging.getToken();
      
      if (_currentToken != null) {
        print('✅ FCM Token obtained successfully!');
        print('🔑 FCM Token: $_currentToken');
        print('📏 Token length: ${_currentToken!.length}');
        _onTokenRefresh?.call(_currentToken!);
      } else {
        print('❌ FCM Token is null');
      }
      
      return _currentToken;
    } catch (e) {
      print('❌ Failed to get FCM token: $e');
      print('Error type: ${e.runtimeType}');
      return null;
    }
  }

  // 토큰 갱신 처리
  void _handleTokenRefresh(String token) {
    _currentToken = token;
    print('FCM Token refreshed: $token');
    _onTokenRefresh?.call(token);
  }

  // 포그라운드 메시지 처리
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('Foreground message received: ${message.messageId}');
    
    // 콜백 호출
    _onMessageReceived?.call({
      'title': message.notification?.title,
      'body': message.notification?.body,
      'data': message.data,
    });
    
    // 로컬 알림 표시
    await _showLocalNotification(message);
  }

  // 메시지 클릭 처리
  void _handleMessageOpenedApp(RemoteMessage message) {
    print('Message opened app: ${message.messageId}');
    _onNotificationTapped?.call({
      'title': message.notification?.title,
      'body': message.notification?.body,
      'data': message.data,
    });
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
    
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      message.notification?.title ?? 'New Message',
      message.notification?.body ?? '',
      details,
      payload: json.encode(message.data),
    );
  }

  // 현재 토큰 반환
  String? get currentToken => _currentToken;
  
  // 토큰 강제 갱신
  Future<String?> refreshToken() async {
    await _messaging.deleteToken();
    return await _getToken();
  }
  
  // 토픽 구독
  Future<void> subscribeToTopic(String topic) async {
    await _messaging.subscribeToTopic(topic);
    print('Subscribed to topic: $topic');
  }
  
  // 토픽 구독 해제
  Future<void> unsubscribeFromTopic(String topic) async {
    await _messaging.unsubscribeFromTopic(topic);
    print('Unsubscribed from topic: $topic');
  }
  
  // 플랫폼 정보 가져오기
  String getPlatform() {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }
}

// 백그라운드 메시지 핸들러 (최상위 함수여야 함)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('Background message received: ${message.messageId}');
  // 필요시 백그라운드 작업 수행
}