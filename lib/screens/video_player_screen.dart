import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String? courseTitle;
  final String? selectedLanguage;
  final List<String>? candidateUrls;
  final String? masterUrl;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    required this.title,
    this.courseTitle,
    this.selectedLanguage,
    this.candidateUrls,
    this.masterUrl,
  });

  static Future<void> show({
    required BuildContext context,
    required String videoUrl,
    required String title,
    String? courseTitle,
    String? selectedLanguage,
    List<String>? candidateUrls,
    String? masterUrl,
  }) {
    // Force landscape mode for video playback
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    return Navigator.of(context)
        .push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (context) => VideoPlayerScreen(
              videoUrl: videoUrl,
              title: title,
              courseTitle: courseTitle,
              selectedLanguage: selectedLanguage,
              candidateUrls: candidateUrls,
              masterUrl: masterUrl,
            ),
          ),
        )
        .then((_) {
          // Restore original orientation when exiting video
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        });
  }

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isError = false;
  String? _errorMessage;
  bool _isControlsVisible = true;
  bool _initializing = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    if (_initializing) return;
    _initializing = true;
    try {
      debugPrint(
        '[VideoPlayer] Initializing (selectedLanguage=${widget.selectedLanguage})',
      );

      // Build candidate list
      final List<String> urlsToTry = <String>[];
      void addUrl(String? u) {
        if (u == null) return;
        final t = u.trim();
        if (t.isEmpty) return;
        if (!urlsToTry.contains(t)) urlsToTry.add(t);
      }

      // 1) Provided candidates from WebView (filter out audio-only)
      if (widget.candidateUrls != null) {
        for (final u in widget.candidateUrls!) {
          final lower = (u).toLowerCase();
          final isAudioOnly =
              lower.contains('/dubtracks/') ||
              lower.endsWith('.aac') ||
              lower.endsWith('.mp3');
          if (!isAudioOnly) addUrl(u);
        }
      }
      // 2) Primary videoUrl
      addUrl(widget.videoUrl);
      // 3) Master with lang param
      if ((widget.selectedLanguage ?? '').isNotEmpty &&
          (widget.selectedLanguage ?? '') != 'origin') {
        final base = (widget.masterUrl ?? widget.videoUrl).trim();
        final withLang = base.contains('?')
            ? '$base&lang=${widget.selectedLanguage}'
            : '$base?lang=${widget.selectedLanguage}';
        addUrl(withLang);
      }
      // 4) MP4 fallback based on master
      final master = widget.masterUrl ?? widget.videoUrl;
      if (master.contains('/master.m3u8')) {
        addUrl(master.replaceAll('/master.m3u8', '/video.mp4'));
      }

      // Ensure per-language master is first candidate if available/derivable
      final sel = (widget.selectedLanguage ?? '').toLowerCase();
      if (sel.isNotEmpty && sel != 'origin') {
        // Derive master_{lang}.m3u8 from master base
        if (master.trim().endsWith('/master.m3u8')) {
          final prefix = master.trim().substring(
            0,
            master.trim().length - '/master.m3u8'.length,
          );
          final langMaster = '$prefix/master_$sel.m3u8';
          // Move to front if already exists; otherwise insert at front
          final existingIdx = urlsToTry.indexOf(langMaster);
          if (existingIdx > 0) {
            urlsToTry.removeAt(existingIdx);
            urlsToTry.insert(0, langMaster);
          } else if (existingIdx < 0) {
            urlsToTry.insert(0, langMaster);
          }
        }

        // Also prioritize any existing candidate that matches master_{lang}.m3u8
        final idx = urlsToTry.indexWhere(
          (u) => u.toLowerCase().contains('/master_$sel.m3u8'),
        );
        if (idx > 0) {
          final u = urlsToTry.removeAt(idx);
          urlsToTry.insert(0, u);
        }
      }

      debugPrint('[VideoPlayer] URLs to try (${urlsToTry.length}):');
      for (final u in urlsToTry) {
        debugPrint('  - $u');
      }

      // Headers builder
      Map<String, String> headersFor(String? lang) {
        String acceptLang = 'en-US,en;q=0.9';
        final l = (lang ?? '').toLowerCase();
        if (l.isNotEmpty && l != 'origin') {
          switch (l) {
            case 'ko':
              acceptLang = 'ko-KR,ko;q=0.9';
              break;
            case 'ja':
              acceptLang = 'ja-JP,ja;q=0.9';
              break;
            case 'zh':
              acceptLang = 'zh-CN,zh;q=0.9';
              break;
            case 'en':
              acceptLang = 'en-US,en;q=0.9';
              break;
            case 'fr':
              acceptLang = 'fr-FR,fr;q=0.9';
              break;
            case 'es':
              acceptLang = 'es-ES,es;q=0.9';
              break;
            default:
              acceptLang = '$l;q=0.9,en;q=0.5';
          }
        }
        return {
          'User-Agent': 'LingoostApp/Flutter',
          'Accept': '*/*',
          'Accept-Language': acceptLang,
          'Cache-Control': 'no-cache',
        };
      }

      // Try candidates sequentially
      for (int i = 0; i < urlsToTry.length; i++) {
        final url = urlsToTry[i];
        try {
          debugPrint(
            '[VideoPlayer] Trying candidate ${i + 1}/${urlsToTry.length}: $url',
          );
          // Dispose any previous controller
          await _controller?.dispose();
          _controller = VideoPlayerController.networkUrl(
            Uri.parse(url),
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: true,
              allowBackgroundPlayback: false,
            ),
            httpHeaders: headersFor(widget.selectedLanguage),
          );
          await _controller!.initialize();

          // Success
          setState(() {
            _isInitialized = true;
            _isError = false;
            _errorMessage = null;
          });
          await _controller!.play();
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          debugPrint('[VideoPlayer] Initialized successfully with: $url');
          _initializing = false;
          return;
        } catch (e) {
          debugPrint('[VideoPlayer] Candidate failed: $url -> $e');
          // continue to next candidate
        }
      }

      // If all candidates failed
      setState(() {
        _isError = true;
        _errorMessage = '모든 재생 후보가 실패했습니다.\n\nTried:\n${urlsToTry.join('\n')}';
      });
    } catch (e) {
      setState(() {
        _isError = true;
        _errorMessage = e.toString();
      });
    } finally {
      _initializing = false;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null) return;

    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _isControlsVisible = !_isControlsVisible;
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Video Player
            Center(
              child: _isError
                  ? _buildErrorWidget()
                  : _isInitialized && _controller != null
                  ? GestureDetector(
                      onTap: _toggleControls,
                      child: AspectRatio(
                        aspectRatio: _controller!.value.aspectRatio,
                        child: VideoPlayer(_controller!),
                      ),
                    )
                  : _buildLoadingWidget(),
            ),

            // Controls Overlay
            if (_isInitialized && _controller != null && _isControlsVisible)
              AnimatedOpacity(
                opacity: _isControlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top Bar
                      Container(
                        padding: const EdgeInsets.all(8.0),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (widget.courseTitle != null)
                                    Text(
                                      widget.courseTitle!,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  Text(
                                    widget.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Center Play/Pause Button
                      Center(
                        child: IconButton(
                          iconSize: 64,
                          icon: Icon(
                            _controller!.value.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: Colors.white,
                          ),
                          onPressed: _togglePlayPause,
                        ),
                      ),

                      // Bottom Controls
                      Container(
                        padding: const EdgeInsets.all(8.0),
                        child: Column(
                          children: [
                            // Progress Bar
                            VideoProgressIndicator(
                              _controller!,
                              allowScrubbing: true,
                              colors: const VideoProgressColors(
                                playedColor: Colors.blue,
                                bufferedColor: Colors.white30,
                                backgroundColor: Colors.white10,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Time Display
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                ValueListenableBuilder(
                                  valueListenable: _controller!,
                                  builder: (context, value, child) {
                                    return Text(
                                      _formatDuration(value.position),
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    );
                                  },
                                ),
                                Text(
                                  _formatDuration(_controller!.value.duration),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircularProgressIndicator(color: Colors.white),
        SizedBox(height: 16),
        Text('동영상 로딩 중...', style: TextStyle(color: Colors.white)),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, size: 64, color: Colors.red),
        const SizedBox(height: 16),
        const Text(
          '동영상을 재생할 수 없습니다',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ],
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
          label: const Text('돌아가기'),
        ),
      ],
    );
  }
}
