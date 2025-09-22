import 'dart:async';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  runApp(const MyApp());
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
      home: const LingoostWebViewPage(
        initialUrl: 'https://www.lingoost.com/ko',
      ),
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
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {},
            onPageStarted: (String url) {
              setState(() {
                _hasError = false;
                _errorDescription = null;
              });
            },
            onPageFinished: (String url) async {
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
              } catch (_) {}
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
        ..loadRequest(Uri.parse(widget.initialUrl));

      _controller = controller;
    }
  }

  Future<void> _reload() async {
    try {
      if (_controller == null) {
        final Uri uri = Uri.parse(widget.initialUrl);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      if (_hasError) {
        await _controller!.loadRequest(Uri.parse(widget.initialUrl));
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
                const String url = 'https://www.lingoost.com/ko';
                final Uri uri = Uri.parse(url);
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
