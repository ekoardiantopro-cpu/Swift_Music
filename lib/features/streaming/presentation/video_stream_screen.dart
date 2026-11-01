import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../../core/widgets/motion.dart';
import '../domain/network_playlist.dart';

class VideoStreamScreen extends StatefulWidget {
  const VideoStreamScreen({super.key, required this.uri, required this.title, this.channels = const []});
  final Uri uri;
  final String title;
  final List<StreamEntry> channels;

  @override
  State<VideoStreamScreen> createState() => _VideoStreamScreenState();
}

class _VideoStreamScreenState extends State<VideoStreamScreen> {
  late VideoPlayerController _controller;
  String? _error;
  Timer? _controlsTimer;
  bool _controlsVisible = true;
  bool _switchingChannel = false;
  int _channelIndex = 0;

  @override
  void initState() {
    super.initState();
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    _channelIndex = widget.channels.indexWhere((channel) => channel.uri == widget.uri);
    if (_channelIndex < 0) _channelIndex = 0;
    _controller = VideoPlayerController.networkUrl(widget.uri);
    _initializeController(_controller);
  }

  void _initializeController(VideoPlayerController controller) {
    controller
        .initialize()
        .then((_) {
          if (mounted && identical(controller, _controller)) setState(() => _switchingChannel = false);
          return controller.play();
        })
        .catchError((Object error) {
          if (mounted && identical(controller, _controller)) {
            setState(() {
              _switchingChannel = false;
              _error = 'Video tidak dapat diputar: $error';
            });
          }
        });
    controller.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _showControls() {
    _controlsTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    if (_controller.value.isPlaying) {
      _controlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _controller.value.isPlaying) {
          setState(() => _controlsVisible = false);
        }
      });
    }
  }

  Future<void> _showChannelList() async {
    if (widget.channels.isEmpty) return;
    _controlsTimer?.cancel();
    setState(() => _controlsVisible = true);
    final selected = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFF19171E),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .62,
        minChildSize: .35,
        maxChildSize: .9,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(4))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Row(children: [
                const Icon(Icons.live_tv_rounded, color: Colors.white),
                const SizedBox(width: 10),
                const Expanded(child: Text('Daftar channel', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
                Text('${widget.channels.length}', style: const TextStyle(color: Colors.white60)),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: widget.channels.length,
                itemBuilder: (context, index) {
                  final channel = widget.channels[index];
                  final active = index == _channelIndex;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: active ? const Color(0xFF53C878) : Colors.white12,
                      child: Icon(active ? Icons.equalizer_rounded : Icons.tv_rounded, color: Colors.white, size: 20),
                    ),
                    title: Text(channel.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(channel.uri.host, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    trailing: active ? const Icon(Icons.play_arrow_rounded, color: Color(0xFF53C878)) : null,
                    onTap: () => Navigator.pop(context, index),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (selected != null && selected != _channelIndex) await _playChannel(selected);
    _showControls();
  }

  Future<void> _playChannel(int index) async {
    final channel = widget.channels[index];
    final previous = _controller;
    previous.removeListener(_onChanged);
    setState(() {
      _switchingChannel = true;
      _controlsVisible = true;
      _error = null;
      _channelIndex = index;
    });
    final controller = VideoPlayerController.networkUrl(channel.uri);
    _controller = controller;
    _initializeController(controller);
    await previous.dispose();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _controller.removeListener(_onChanged);
    unawaited(_controller.dispose());
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showControls,
          onLongPress: _showChannelList,
          child: Stack(
          alignment: Alignment.center,
          children: [
            if (value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : 16 / 9,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _showControls,
                    child: VideoPlayer(_controller),
                  ),
                ),
              )
            else if (_error == null)
              Center(
                child: _SoftLoadingIndicator(
                  color: Theme.of(context).colorScheme.primary,
                ),
              )
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            if (_switchingChannel)
              const Center(child: _SoftLoadingIndicator(color: Colors.white)),
            if (widget.channels.isNotEmpty && value.isInitialized && _controlsVisible)
              Positioned(
                top: 12,
                left: 64,
                child: ActionChip(
                  avatar: const Icon(Icons.live_tv_rounded, color: Colors.white, size: 18),
                  label: Text('${widget.channels[_channelIndex].title}  ·  ${widget.channels.length} channel', style: const TextStyle(color: Colors.white)),
                  backgroundColor: Colors.black.withValues(alpha: .72),
                  side: BorderSide.none,
                  onPressed: _showChannelList,
                ),
              ),
            if (_error != null || (value.isInitialized && _controlsVisible))
              Positioned(
                top: 8,
                left: 8,
                child: IconButton.filledTonal(
                  tooltip: 'Tutup video',
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
            if (_error != null)
              Positioned(
                bottom: 24,
                child: TextButton.icon(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Kembali ke daftar channel'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
              ),
            if (value.isInitialized && _controlsVisible)
              Positioned(
                left: 16,
                right: 16,
                bottom: 8,
                child: Material(
                  color: Colors.black.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: value.isPlaying ? 'Jeda' : 'Putar',
                          color: Colors.white,
                          onPressed: () {
                            if (value.isPlaying) {
                              _controller.pause();
                            } else {
                              _controller.play();
                              _showControls();
                            }
                          },
                          icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                        ),
                        Expanded(
                          child: Slider(
                            value: value.duration.inMilliseconds == 0
                                ? 0
                                : value.position.inMilliseconds
                                    .clamp(0, value.duration.inMilliseconds)
                                    .toDouble(),
                            max: value.duration.inMilliseconds > 0
                                ? value.duration.inMilliseconds.toDouble()
                                : 1,
                            onChanged: (position) => _controller.seekTo(
                              Duration(milliseconds: position.round()),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

class _SoftLoadingIndicator extends StatefulWidget {
  const _SoftLoadingIndicator({required this.color});
  final Color color;

  @override
  State<_SoftLoadingIndicator> createState() => _SoftLoadingIndicatorState();
}

class _SoftLoadingIndicatorState extends State<_SoftLoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (fullMotionAllowed(context)) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = .5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) => Opacity(
      opacity: .55 + _controller.value * .45,
      child: Transform.scale(scale: .92 + _controller.value * .08, child: child),
    ),
    child: SizedBox(
      width: 42,
      height: 42,
      child: CircularProgressIndicator(
        strokeWidth: 3,
        color: widget.color,
        backgroundColor: widget.color.withValues(alpha: .16),
      ),
    ),
  );
}
