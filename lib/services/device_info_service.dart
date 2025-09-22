import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

class DeviceInfoService {
  static String getUserAgent() {
    // LingoostApp을 User Agent에 포함시켜 웹에서 감지할 수 있도록 함
    final platform = Platform.isIOS ? 'iOS' : 'Android';
    final deviceType = _getDeviceType();
    return 'LingoostApp/$platform/$deviceType Flutter WebView';
  }

  static String _getDeviceType() {
    if (Platform.isIOS) {
      // iPad detection (simplified - you may need more sophisticated detection)
      final screenSize = PlatformDispatcher.instance.views.first.physicalSize;
      final screenWidth = screenSize.width;
      final screenHeight = screenSize.height;
      final minDimension = screenWidth < screenHeight ? screenWidth : screenHeight;

      // Generally, iPads have minimum dimension > 2000 pixels
      if (minDimension > 2000) {
        return 'iPad';
      }
      return 'iPhone';
    }
    return 'Android';
  }

  static String getDeviceInfoScript() {
    final isIOS = Platform.isIOS;
    final isAndroid = Platform.isAndroid;
    final deviceType = _getDeviceType();
    final isIPad = deviceType == 'iPad';

    return '''
      (function() {
        try {
          // Check if already injected
          if (window.LingoostApp && window.LingoostApp.injected) {
            console.log('[LingoostApp] Device info already injected, skipping');
            return;
          }

          // LingoostApp 플래그 설정
          window.LingoostApp = {
            injected: true,
            isWebView: true,
            isIOS: $isIOS,
            isAndroid: $isAndroid,
            isIPad: $isIPad,
            platform: '${Platform.operatingSystem}',
            deviceType: '$deviceType',
            version: '1.0.0'
          };

          // 기존 방식과의 호환성을 위한 설정
          window.flutter_inappwebview = window.flutter_inappwebview || {};

          // Ensure callHandler is available (stub it if not available from native)
          if (!window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler = function(name, data) {
              console.log('[LingoostApp] callHandler stub called:', name, data);
            };
          }

          // deviceInfoReady 이벤트 발송
          const event = new CustomEvent('deviceInfoReady', {
            detail: {
              isWebView: true,
              isIOS: $isIOS,
              isAndroid: $isAndroid,
              isIPad: $isIPad
            }
          });
          window.dispatchEvent(event);

          console.log('[LingoostApp] Device info injected:', window.LingoostApp);

          // Store original userAgent to avoid infinite recursion
          const originalUserAgent = navigator.userAgent;
          if (!originalUserAgent.includes('LingoostApp')) {
            try {
              Object.defineProperty(navigator, 'userAgent', {
                get: function() {
                  return originalUserAgent + ' LingoostApp/$deviceType';
                },
                configurable: true
              });
            } catch (e) {
              console.log('[LingoostApp] Could not override userAgent:', e);
            }
          }

        } catch (e) {
          console.error('[LingoostApp] Failed to inject device info:', e);
        }
      })();
    ''';
  }

  static String getHLSEnhancementScript() {
    return '''
      (function() {
        try {
          // Check if already enhanced
          if (window.LingoostHLSEnhanced) {
            console.log('[LingoostApp] HLS already enhanced, skipping');
            return;
          }
          window.LingoostHLSEnhanced = true;

          console.log('[LingoostApp] Enhancing HLS playback for WebView');

          // Video element enhancement
          const enhanceVideo = function(video) {
            if (!video || video.hasAttribute('lingoost-enhanced')) return;

            video.setAttribute('lingoost-enhanced', 'true');
            video.setAttribute('playsinline', 'true');
            video.setAttribute('webkit-playsinline', 'true');
            video.setAttribute('x5-video-player-type', 'h5');
            video.setAttribute('x5-video-player-fullscreen', 'false');

            // Add error recovery
            video.addEventListener('error', function(e) {
              console.error('[LingoostApp] Video error:', e);
              const src = video.src;
              if (src && src.includes('.m3u8')) {
                console.log('[LingoostApp] Attempting to recover HLS playback');
                setTimeout(() => {
                  video.load();
                }, 1000);
              }
            });

            console.log('[LingoostApp] Enhanced video element:', video);
          };

          // Observe for new video elements
          const observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
              mutation.addedNodes.forEach(function(node) {
                if (node.nodeName === 'VIDEO') {
                  enhanceVideo(node);
                }
              });
            });
          });

          observer.observe(document.body, {
            childList: true,
            subtree: true
          });

          // Enhance existing videos
          document.querySelectorAll('video').forEach(enhanceVideo);

          // Override createElement for videos (check if not already overridden)
          if (!document.createElement.lingoostOverridden) {
            const originalCreateElement = document.createElement.bind(document);
            document.createElement = function(tagName) {
              const element = originalCreateElement(tagName);
              if (tagName.toLowerCase() === 'video') {
                setTimeout(() => enhanceVideo(element), 0);
              }
              return element;
            };
            document.createElement.lingoostOverridden = true;
          }

        } catch (e) {
          console.error('[LingoostApp] Failed to enhance HLS:', e);
        }
      })();
    ''';
  }

  static Future<void> injectScriptsToController(WebViewController controller) async {
    try {
      // 기기 정보 주입
      await controller.runJavaScript(getDeviceInfoScript());

      // HLS 개선 스크립트 주입
      await controller.runJavaScript(getHLSEnhancementScript());

      debugPrint('[DeviceInfoService] Scripts injected successfully');
    } catch (e) {
      debugPrint('[DeviceInfoService] Failed to inject scripts: $e');
    }
  }
}