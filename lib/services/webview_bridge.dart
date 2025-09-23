import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'dart:convert';
import 'fcm_service.dart';

class WebViewBridge {
  static final WebViewBridge _instance = WebViewBridge._internal();
  factory WebViewBridge() => _instance;
  WebViewBridge._internal();

  WebViewController? _controller;
  final FcmService _fcmService = FcmService();
  
  // 웹뷰에서 호출 가능한 함수 등록
  Map<String, Function> _handlers = {};

  // 웹뷰 컨트롤러 설정
  void setController(WebViewController controller) {
    _controller = controller;
    _setupJavaScriptChannels();
    _injectBridgeScript();
  }

  // JavaScript 채널 설정
  void _setupJavaScriptChannels() {
    if (_controller == null) return;
    
    _controller!.addJavaScriptChannel(
      'FlutterBridge',
      onMessageReceived: (JavaScriptMessage message) {
        _handleMessage(message.message);
      },
    );
  }

  // 브릿지 스크립트 주입
  Future<void> _injectBridgeScript() async {
    if (_controller == null) return;
    
    const bridgeScript = '''
      window.FlutterBridge = {
        // Flutter로 메시지 전송
        postMessage: function(type, data) {
          FlutterBridge.postMessage(JSON.stringify({
            type: type,
            data: data
          }));
        },
        
        // FCM 토큰 요청
        requestFcmToken: function() {
          this.postMessage('GET_FCM_TOKEN', {});
        },
        
        // FCM 토큰 저장 (userId와 함께)
        saveFcmToken: function(userId) {
          this.postMessage('SAVE_FCM_TOKEN', { userId: userId });
        },
        
        // FCM 토큰 삭제
        deleteFcmToken: function() {
          this.postMessage('DELETE_FCM_TOKEN', {});
        },
        
        // 토픽 구독
        subscribeToTopic: function(topic) {
          this.postMessage('SUBSCRIBE_TOPIC', { topic: topic });
        },
        
        // 토픽 구독 해제
        unsubscribeFromTopic: function(topic) {
          this.postMessage('UNSUBSCRIBE_TOPIC', { topic: topic });
        },
        
        // 디바이스 정보 요청
        getDeviceInfo: function() {
          this.postMessage('GET_DEVICE_INFO', {});
        }
      };
      
      // 웹뷰 준비 완료 이벤트 발생
      window.dispatchEvent(new CustomEvent('flutterBridgeReady'));
      console.log('Flutter Bridge initialized');
    ''';
    
    await _controller!.runJavaScript(bridgeScript);
  }

  // 메시지 처리
  void _handleMessage(String message) {
    try {
      final Map<String, dynamic> data = json.decode(message);
      final String type = data['type'] ?? '';
      final Map<String, dynamic> payload = data['data'] ?? {};
      
      switch (type) {
        case 'GET_FCM_TOKEN':
          _handleGetFcmToken();
          break;
        case 'SAVE_FCM_TOKEN':
          _handleSaveFcmToken(payload['userId']);
          break;
        case 'DELETE_FCM_TOKEN':
          _handleDeleteFcmToken();
          break;
        case 'SUBSCRIBE_TOPIC':
          _handleSubscribeTopic(payload['topic']);
          break;
        case 'UNSUBSCRIBE_TOPIC':
          _handleUnsubscribeTopic(payload['topic']);
          break;
        case 'GET_DEVICE_INFO':
          _handleGetDeviceInfo();
          break;
        default:
          // 커스텀 핸들러 실행
          if (_handlers.containsKey(type)) {
            _handlers[type]!(payload);
          }
      }
    } catch (e) {
      print('Error handling message from WebView: $e');
    }
  }

  // FCM 토큰 가져오기 처리
  Future<void> _handleGetFcmToken() async {
    final token = _fcmService.currentToken;
    if (token != null) {
      await _sendToWebView('FCM_TOKEN_RECEIVED', {'token': token});
    } else {
      final newToken = await _fcmService.refreshToken();
      if (newToken != null) {
        await _sendToWebView('FCM_TOKEN_RECEIVED', {'token': newToken});
      }
    }
  }

  // FCM 토큰 저장 처리 (서버로 전송)
  Future<void> _handleSaveFcmToken(String? userId) async {
    final token = _fcmService.currentToken;
    if (token != null) {
      await _sendToWebView('FCM_TOKEN_SAVE_REQUEST', {
        'token': token,
        'userId': userId,
        'platform': _fcmService.getPlatform(),
        'deviceId': await _getDeviceId(),
      });
    }
  }

  // FCM 토큰 삭제 처리
  Future<void> _handleDeleteFcmToken() async {
    final token = _fcmService.currentToken;
    if (token != null) {
      await _sendToWebView('FCM_TOKEN_DELETE_REQUEST', {'token': token});
    }
  }

  // 토픽 구독 처리
  Future<void> _handleSubscribeTopic(String? topic) async {
    if (topic != null && topic.isNotEmpty) {
      await _fcmService.subscribeToTopic(topic);
      await _sendToWebView('TOPIC_SUBSCRIBED', {'topic': topic});
    }
  }

  // 토픽 구독 해제 처리
  Future<void> _handleUnsubscribeTopic(String? topic) async {
    if (topic != null && topic.isNotEmpty) {
      await _fcmService.unsubscribeFromTopic(topic);
      await _sendToWebView('TOPIC_UNSUBSCRIBED', {'topic': topic});
    }
  }

  // 디바이스 정보 가져오기
  Future<void> _handleGetDeviceInfo() async {
    await _sendToWebView('DEVICE_INFO_RECEIVED', {
      'platform': _fcmService.getPlatform(),
      'deviceId': await _getDeviceId(),
    });
  }

  // 웹뷰로 메시지 전송
  Future<void> _sendToWebView(String type, Map<String, dynamic> data) async {
    if (_controller == null) return;
    
    final script = '''
      if (window.handleFlutterMessage) {
        window.handleFlutterMessage('$type', ${json.encode(data)});
      } else {
        console.warn('handleFlutterMessage not defined');
      }
    ''';
    
    await _controller!.runJavaScript(script);
  }

  // 디바이스 ID 가져오기 (플랫폼별 구현 필요)
  Future<String> _getDeviceId() async {
    // TODO: device_info_plus 패키지 사용하여 실제 디바이스 ID 가져오기
    return 'device_${DateTime.now().millisecondsSinceEpoch}';
  }

  // 커스텀 핸들러 등록
  void registerHandler(String type, Function(Map<String, dynamic>) handler) {
    _handlers[type] = handler;
  }

  // FCM 메시지 웹뷰로 전달
  void forwardFcmMessage(Map<String, dynamic> message) {
    _sendToWebView('FCM_MESSAGE_RECEIVED', message);
  }

  // FCM 알림 클릭 웹뷰로 전달
  void forwardNotificationTap(Map<String, dynamic> data) {
    _sendToWebView('FCM_NOTIFICATION_TAPPED', data);
  }
}