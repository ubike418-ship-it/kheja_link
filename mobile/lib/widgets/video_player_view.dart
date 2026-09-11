import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../config/theme.dart';

/// One video tour, playable inside the listing gallery.
///
/// Nothing is downloaded until the tenant taps play. On a mobile bundle a
/// video that auto-loaded the moment its page swiped into view would quietly
/// eat megabytes the person never chose to spend.
class VideoPlayerView extends StatefulWidget {
  const VideoPlayerView({super.key, required this.url, this.thumbnailUrl});

  final String url;
  final String? thumbnailUrl;

  @override
  State<VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<VideoPlayerView> {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  bool _starting = false;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _starting = true;
      _error = null;
    });

    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize().timeout(const Duration(seconds: 30));
      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _video = controller;
        _chewie = ChewieController(
          videoPlayerController: controller,
          autoPlay: true,
          looping: false,
          allowFullScreen: true,
          allowMuting: true,
          showControlsOnInitialize: false,
          materialProgressColors: ChewieProgressColors(
            playedColor: KhejaColors.blue,
            handleColor: KhejaColors.blue,
            bufferedColor: Colors.white38,
            backgroundColor: Colors.white12,
          ),
          errorBuilder: (context, message) => _ErrorPanel(onRetry: _start),
        );
        _starting = false;
      });
    } catch (_) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = 'Could not play this video. Check your connection and try again.';
      });
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_chewie != null) {
      return ColoredBox(color: Colors.black, child: Chewie(controller: _chewie!));
    }

    if (_error != null) return _ErrorPanel(onRetry: _start, message: _error);

    // The resting state: a poster with a play button. Tapping is the consent
    // to start downloading.
    return GestureDetector(
      onTap: _starting ? null : _start,
      child: Container(
        color: KhejaColors.zinc900,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.thumbnailUrl != null)
              Image.network(
                widget.thumbnailUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              )
            else
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [KhejaColors.brandInk, KhejaColors.zinc900],
                  ),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(color: Colors.black26),
            ),
            Center(
              child: _starting
                  ? const SizedBox(
                      width: 46,
                      height: 46,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: Colors.white),
                    )
                  : Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white54, width: 2),
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          size: 46, color: Colors.white),
                    ),
            ),
            Positioned(
              left: 16,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_rounded, size: 14, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(
                      _starting ? 'LOADING' : 'VIDEO TOUR',
                      style: kEyebrowStyle.copyWith(color: Colors.white),
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
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.onRetry, this.message});

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: KhejaColors.zinc900,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off_rounded, size: 40, color: Colors.white54),
          const SizedBox(height: 12),
          Text(
            message ?? 'This video could not be played.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white38),
              minimumSize: const Size(140, 44),
            ),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
