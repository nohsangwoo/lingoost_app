import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final String? courseTitle;

  const VideoPlayerScreen({
    Key? key,
    required this.videoUrl,
    required this.title,
    this.courseTitle,
  }) : super(key: key);

  static Future<void> show({
    required BuildContext context,
    required String videoUrl,
    required String title,
    String? courseTitle,
  }) {
    // Force landscape mode for video playback
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => VideoPlayerScreen(
          videoUrl: videoUrl,
          title: title,
          courseTitle: courseTitle,
        ),
      ),
    ).then((_) {
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

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      debugPrint('[VideoPlayer] Initializing with URL: ${widget.videoUrl}');

      // Check if URL is valid
      final Uri? uri = Uri.tryParse(widget.videoUrl);
      if (uri == null) {
        throw Exception('Invalid URL format: ${widget.videoUrl}');
      }

      // Determine if it's HLS or direct video
      final bool isHLS = widget.videoUrl.contains('.m3u8');
      debugPrint('[VideoPlayer] URL type: ${isHLS ? "HLS" : "Direct video"}');
      debugPrint('[VideoPlayer] Creating controller for: $uri');

      _controller = VideoPlayerController.networkUrl(
        uri,
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: true,
          allowBackgroundPlayback: false,
        ),
        httpHeaders: {
          'User-Agent': 'LingoostApp/iOS Flutter',
          'Accept': '*/*',
          'Accept-Language': 'en-US,en;q=0.9',
          'Cache-Control': 'no-cache',
        },
      );

      debugPrint('[VideoPlayer] Initializing controller...');
      await _controller!.initialize();
      debugPrint('[VideoPlayer] Controller initialized successfully');
      debugPrint('[VideoPlayer] Video duration: ${_controller!.value.duration}');
      debugPrint('[VideoPlayer] Video size: ${_controller!.value.size}');

      setState(() {
        _isInitialized = true;
      });

      debugPrint('[VideoPlayer] Starting playback...');
      await _controller!.play();

      // Hide status bar for immersive experience
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    } catch (e, stackTrace) {
      debugPrint('[VideoPlayer] Error initializing video: $e');
      debugPrint('[VideoPlayer] Error type: ${e.runtimeType}');

      // If HLS fails, try fallback to direct MP4 if available
      if (widget.videoUrl.contains('.m3u8') && widget.videoUrl.contains('/master.m3u8')) {
        final mp4Url = widget.videoUrl.replaceAll('/master.m3u8', '/video.mp4');
        debugPrint('[VideoPlayer] HLS failed, trying MP4 fallback: $mp4Url');

        try {
          _controller = VideoPlayerController.networkUrl(Uri.parse(mp4Url));
          await _controller!.initialize();
          setState(() {
            _isInitialized = true;
            _isError = false;
          });
          await _controller!.play();
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          return; // Success with fallback
        } catch (fallbackError) {
          debugPrint('[VideoPlayer] MP4 fallback also failed: $fallbackError');
        }
      }

      setState(() {
        _isError = true;
        _errorMessage = '${e.toString()}\n\nURL: ${widget.videoUrl}';
      });
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
                              icon: const Icon(Icons.arrow_back, color: Colors.white),
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
                                      style: const TextStyle(color: Colors.white),
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
        Text(
          '동영상 로딩 중...',
          style: TextStyle(color: Colors.white),
        ),
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