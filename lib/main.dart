import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'services/device_info_service.dart';
import 'screens/video_player_screen.dart';

void main() {
  runApp(const MyApp());
}

// Centralized domain/base URL management
String appBaseUrl() {
  const String envOverride = String.fromEnvironment('APP_BASE_URL');
  if (envOverride.isNotEmpty) return envOverride;
  // Toggle defaults by build mode
  const String local = 'https://ca3c7dd25966.ngrok-free.app';
  const String prod = 'https://www.lingoost.com';
  return kReleaseMode ? prod : local;
}

String initialAppUrl({String locale = 'ko'}) {
  final base = appBaseUrl().replaceAll(RegExp(r'/+$'), '');
  return '$base/$locale';
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lingoost',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LingoostWebViewPage(initialUrl: ''),
    );
  }
}

class LingoostWebViewPage extends StatefulWidget {
  const LingoostWebViewPage({super.key, required this.initialUrl});

  final String initialUrl;

  @override
  State<LingoostWebViewPage> createState() => _LingoostWebViewPageState();
}

class _LingoostWebViewPageState extends State<LingoostWebViewPage> {
  WebViewController? _controller;
  bool _hasError = false;
  String? _errorDescription;
  late final bool _isWebViewSupported;

  @override
  void initState() {
    super.initState();

    _isWebViewSupported =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);

    if (_isWebViewSupported) {
      final WebViewController controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setUserAgent(DeviceInfoService.getUserAgent())
        ..addJavaScriptChannel(
          'LingoostVideoPlayer',
          onMessageReceived: (JavaScriptMessage message) {
            try {
              debugPrint(
                '[LingoostApp] Received video play request: ${message.message}',
              );

              // Parse JSON message
              final Map<String, dynamic> data = jsonDecode(message.message);
              final String? masterUrl = data['url'] as String?;
              final String? title = data['title'] as String?;
              final String? courseTitle = data['courseTitle'] as String?;
              final String? selectedLanguage =
                  data['selectedLanguage'] as String?;
              final List<dynamic>? dubTracks =
                  data['dubTracks'] as List<dynamic>?;
              final String? explicitMasterUrl = data['masterUrl'] as String?;
              final List<dynamic>? candidatesRaw =
                  data['candidates'] as List<dynamic>?;
              // final int? sectionId = data['sectionId'] as int?; // not used currently

              debugPrint('[LingoostApp] Parsed data:');
              debugPrint('  - Master URL: $masterUrl');
              debugPrint('  - Title: $title');
              debugPrint('  - Course: $courseTitle');
              debugPrint('  - Selected Language: $selectedLanguage');
              debugPrint('  - Dub Tracks: ${dubTracks?.length ?? 0}');

              if (masterUrl != null && title != null && context.mounted) {
                String primaryUrl = masterUrl;

                // Build candidate URL list (highest priority first)
                final List<String> candidateUrls = <String>[];

                // 1) Candidates from web (patterned urls)
                if (candidatesRaw != null) {
                  for (final c in candidatesRaw) {
                    if (c is String && c.trim().isNotEmpty) {
                      candidateUrls.add(c.trim());
                    }
                  }
                }

                // 2) DubTracks URLs for selected language (prefer only video+audio variant playlists)
                if (selectedLanguage != null &&
                    selectedLanguage != 'origin' &&
                    dubTracks != null) {
                  for (final track in dubTracks) {
                    if (track is Map<String, dynamic> &&
                        track['lang'] == selectedLanguage) {
                      final String? turl = track['url'] as String?;
                      if (turl != null && turl.isNotEmpty) {
                        final lower = turl.toLowerCase();
                        // Exclude obvious audio-only patterns
                        final isAudioOnly =
                            lower.contains('/dubtracks/') ||
                            lower.endsWith('.aac') ||
                            lower.endsWith('.mp3');
                        // Prefer urls containing master/playlist/video and not audio-only
                        if (!isAudioOnly &&
                            (lower.contains('master') ||
                                lower.contains('playlist') ||
                                lower.contains('video'))) {
                          candidateUrls.add(turl);
                        } else {
                          debugPrint(
                            '[LingoostApp] Skipping audio-only dub track url: $turl',
                          );
                        }
                      }
                    }
                  }
                }

                // 3) Master with lang query hint
                if (selectedLanguage != null &&
                    selectedLanguage.isNotEmpty &&
                    selectedLanguage != 'origin') {
                  final base = (explicitMasterUrl ?? masterUrl).trim();
                  final withLang = base.contains('?')
                      ? '$base&lang=$selectedLanguage'
                      : '$base?lang=$selectedLanguage';
                  candidateUrls.add(withLang);
                }

                // 4) Finally the provided primary (master) url
                candidateUrls.add(masterUrl.trim());

                debugPrint(
                  '[LingoostApp] Candidate URLs (${candidateUrls.length}):',
                );
                for (final u in candidateUrls) {
                  debugPrint('  - $u');
                }
                debugPrint(
                  '[LingoostApp] Selected language: $selectedLanguage',
                );

                VideoPlayerScreen.show(
                  context: context,
                  videoUrl: primaryUrl.trim(),
                  title: title,
                  courseTitle: courseTitle,
                  selectedLanguage: selectedLanguage,
                  candidateUrls: candidateUrls,
                  masterUrl: (explicitMasterUrl ?? masterUrl).trim(),
                );
              } else {
                debugPrint(
                  '[LingoostApp] Missing required data: url=$masterUrl, title=$title',
                );
              }
            } catch (e) {
              debugPrint('[LingoostApp] Error handling video request: $e');
            }
          },
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {},
            onPageStarted: (String url) async {
              setState(() {
                _hasError = false;
                _errorDescription = null;
              });
              // Inject device info as early as possible
              await DeviceInfoService.injectScriptsToController(_controller!);
            },
            onPageFinished: (String url) async {
              // Re-inject scripts after page load to ensure they're available
              await DeviceInfoService.injectScriptsToController(_controller!);

              const String jsOverrideWindowOpen = """
                  (function() {
                    try {
                      const originalOpen = window.open;
                      window.open = function(url) {
                        if (url) {
                          window.location.href = url;
                          return null;
                        }
                        return originalOpen.apply(window, arguments);
                      };
                    } catch (e) { }
                  })();
                  """;
              const String jsDisableZoom = """
                  (function() {
                    try {
                      var meta = document.querySelector('meta[name=viewport]');
                      var content = 'width=device-width, initial-scale=1, minimum-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
                      if (meta) {
                        meta.setAttribute('content', content);
                      } else {
                        meta = document.createElement('meta');
                        meta.setAttribute('name', 'viewport');
                        meta.setAttribute('content', content);
                        document.head.appendChild(meta);
                      }

                      var style = document.createElement('style');
                      style.textContent = 'html, body { touch-action: manipulation; -webkit-text-size-adjust: 100%; text-size-adjust: 100%; } input, select, textarea { font-size: 16px; }';
                      document.head.appendChild(style);

                      var prevent = function(e) { e.preventDefault(); };
                      document.addEventListener('gesturestart', prevent, { passive: false });
                      document.addEventListener('gesturechange', prevent, { passive: false });
                      document.addEventListener('gestureend', prevent, { passive: false });
                      document.addEventListener('wheel', function(e) { if (e.ctrlKey) e.preventDefault(); }, { passive: false });

                      var lastTouchEnd = 0;
                      document.addEventListener('touchend', function(e) {
                        var now = Date.now();
                        if (now - lastTouchEnd <= 300) {
                          e.preventDefault();
                        }
                        lastTouchEnd = now;
                      }, { passive: false });
                    } catch (e) { }
                  })();
                  """;
              try {
                await _controller?.runJavaScript(jsOverrideWindowOpen);
                await _controller?.runJavaScript(jsDisableZoom);
              } catch (e) {
                debugPrint('JavaScript injection error: $e');
              }
            },
            onWebResourceError: (WebResourceError error) {
              setState(() {
                _hasError = true;
                _errorDescription = error.description;
              });
            },
            onNavigationRequest: (NavigationRequest request) async {
              final Uri uri = Uri.parse(request.url);
              final String scheme = uri.scheme.toLowerCase();

              if (scheme == 'http' || scheme == 'https') {
                return NavigationDecision.navigate;
              }

              if (await canLaunchUrl(uri)) {
                unawaited(launchUrl(uri, mode: LaunchMode.externalApplication));
              }
              return NavigationDecision.prevent;
            },
          ),
        )
        ..loadRequest(
          Uri.parse(
            widget.initialUrl.isNotEmpty ? widget.initialUrl : initialAppUrl(),
          ),
        );

      _controller = controller;
    }
  }

  Future<void> _reload() async {
    try {
      if (_controller == null) {
        final Uri uri = Uri.parse(
          widget.initialUrl.isNotEmpty ? widget.initialUrl : initialAppUrl(),
        );
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      if (_hasError) {
        await _controller!.loadRequest(
          Uri.parse(
            widget.initialUrl.isNotEmpty ? widget.initialUrl : initialAppUrl(),
          ),
        );
      } else {
        await _controller!.reload();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_controller != null && await _controller!.canGoBack()) {
          await _controller!.goBack();
          return false;
        }
        return true;
      },
      child: Scaffold(
        body: SafeArea(
          child: !_isWebViewSupported
              ? const _UnsupportedView()
              : _hasError
              ? _ErrorView(
                  message: _errorDescription ?? '페이지를 불러오지 못했습니다.',
                  onRetry: _reload,
                )
              : RefreshIndicator(
                  onRefresh: _reload,
                  child: _controller == null
                      ? const SizedBox.shrink()
                      : WebViewWidget(controller: _controller!),
                ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.wifi_off, size: 56),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnsupportedView extends StatelessWidget {
  const _UnsupportedView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.desktop_windows, size: 56),
            const SizedBox(height: 12),
            const Text(
              '이 플랫폼에서는 내장 웹뷰가 지원되지 않습니다.\n브라우저로 열기를 이용해 주세요.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                final Uri uri = Uri.parse(initialAppUrl());
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('브라우저로 열기'),
            ),
          ],
        ),
      ),
    );
  }
}
