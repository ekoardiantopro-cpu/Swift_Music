import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../player/presentation/player_cubit.dart';
import 'package:in_app_webview_flutter/in_app_webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart'
    hide PlayerState;
import '../data/sponsor_block.dart';
import 'source_icons.dart';

/// This widget exists only while its service is selected. No background WebView.
class ServicePlayer extends StatefulWidget {
  const ServicePlayer({
    super.key,
    required this.source,
    required this.id,
    required this.sponsorBlock,
    this.youtubeMusicHome = false,
    this.spotifyHome = false,
    this.playerHeight,
  });
  final MusicSource source;
  final String id;
  final bool sponsorBlock;
  final bool youtubeMusicHome;
  final bool spotifyHome;
  final double? playerHeight;
  @override
  State<ServicePlayer> createState() => _ServicePlayerState();
}

class _ServicePlayerState extends State<ServicePlayer>
    with WidgetsBindingObserver {
  YoutubePlayerController? _youtube;
  InAppWebViewController? _spotify;
  InAppWebViewController? _youtubeMusic;
  StreamSubscription<YoutubeVideoState>? _subscription;
  List<SponsorSegment> _segments = [];
  final _skipped = <double>{};
  String? _message;
  bool _seeking = false;
  bool _spotifySuspended = false;
  bool _youtubeMusicSuspended = false;
  Timer? _youtubeMusicSponsorTimer;
  String? _youtubeMusicVideoId;
  List<SponsorSegment> _youtubeMusicSegments = const [];
  Timer? _youtubeMusicLoadTimer;
  Timer? _spotifyLoadTimer;
  bool _youtubeMusicLoading = false;
  bool _spotifyLoading = false;
  bool _youtubeMusicFailed = false;
  bool _spotifyFailed = false;

  WebUri get _spotifyUrl => WebUri(
    widget.spotifyHome
        ? 'https://open.spotify.com/'
        : 'https://open.spotify.com/embed/${widget.id}',
  );

  Future<void> _stopService() async {
    await _youtube?.pauseVideo();
    await _youtubeMusic?.evaluateJavascript(
      source: "document.querySelectorAll('video,audio').forEach(e=>e.pause())",
    );
    if (_youtubeMusic != null) {
      _youtubeMusicSuspended = true;
      await _youtubeMusic!.loadUrl(
        urlRequest: URLRequest(url: WebUri('about:blank')),
      );
    }
    await _spotify?.evaluateJavascript(
      source: "document.querySelectorAll('audio,video').forEach(e=>e.pause())",
    );
    if (_spotify != null) {
      _spotifySuspended = true;
      await _spotify!.loadUrl(
        urlRequest: URLRequest(url: WebUri('about:blank')),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.source == MusicSource.youtube && widget.youtubeMusicHome) {
      _beginWebLoad(spotify: false);
      if (widget.sponsorBlock) {
        _youtubeMusicSponsorTimer = Timer.periodic(
          const Duration(milliseconds: 800),
          (_) => unawaited(_skipYoutubeMusicSponsor()),
        );
      }
    } else if (widget.source == MusicSource.spotify && widget.spotifyHome) {
      _beginWebLoad(spotify: true);
    } else if (widget.source == MusicSource.youtube) {
      _youtube = YoutubePlayerController.fromVideoId(
        videoId: widget.id,
        autoPlay: false,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: false,
        ),
      );
      if (widget.sponsorBlock) unawaited(_loadSegments());
    }
  }

  void _beginWebLoad({required bool spotify}) {
    if (spotify) {
      _spotifyLoadTimer?.cancel();
      _spotifyLoading = true;
      _spotifyFailed = false;
      _spotifyLoadTimer = Timer(const Duration(seconds: 18), () {
        if (!mounted || !_spotifyLoading) return;
        setState(() {
          _spotifyLoading = false;
          _spotifyFailed = true;
        });
      });
    } else {
      _youtubeMusicLoadTimer?.cancel();
      _youtubeMusicLoading = true;
      _youtubeMusicFailed = false;
      _youtubeMusicLoadTimer = Timer(const Duration(seconds: 18), () {
        if (!mounted || !_youtubeMusicLoading) return;
        setState(() {
          _youtubeMusicLoading = false;
          _youtubeMusicFailed = true;
        });
      });
    }
  }

  void _finishWebLoad({required bool spotify}) {
    if (spotify) {
      _spotifyLoadTimer?.cancel();
      _spotifyLoading = false;
      _spotifyFailed = false;
    } else {
      _youtubeMusicLoadTimer?.cancel();
      _youtubeMusicLoading = false;
      _youtubeMusicFailed = false;
    }
    if (mounted) setState(() {});
  }

  void _failWebLoad({required bool spotify}) {
    if (spotify) {
      _spotifyLoadTimer?.cancel();
      _spotifyLoading = false;
      _spotifyFailed = true;
    } else {
      _youtubeMusicLoadTimer?.cancel();
      _youtubeMusicLoading = false;
      _youtubeMusicFailed = true;
    }
    if (mounted) setState(() {});
  }

  Future<void> _retryWebLoad({required bool spotify}) async {
    _beginWebLoad(spotify: spotify);
    final controller = spotify ? _spotify : _youtubeMusic;
    if (controller == null) {
      _failWebLoad(spotify: spotify);
      return;
    }
    await controller.loadUrl(
      urlRequest: URLRequest(
        url: spotify ? _spotifyUrl : WebUri('https://music.youtube.com/'),
      ),
    );
  }

  Future<void> _openOfficialService({required bool spotify}) => launchUrl(
    spotify
        ? Uri.https('open.spotify.com', '/')
        : Uri.https('music.youtube.com', '/'),
    mode: LaunchMode.externalApplication,
  );

  Future<NavigationActionPolicy> _youtubeMusicNavigation(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final uri = action.request.url;
    if (uri == null || uri.scheme != 'https') {
      return NavigationActionPolicy.CANCEL;
    }
    final host = uri.host.toLowerCase();
    if (action.isForMainFrame &&
        (host == 'youtube.com' || host.endsWith('.youtube.com')) &&
        host != 'music.youtube.com' &&
        host != 'consent.youtube.com') {
      return NavigationActionPolicy.CANCEL;
    }
    final id = uri.queryParameters['v'];
    if (id != null && id != _youtubeMusicVideoId) {
      _youtubeMusicVideoId = id;
      _youtubeMusicSegments = const [];
      unawaited(_loadYoutubeMusicSegments(id));
    }
    return NavigationActionPolicy.ALLOW;
  }

  Future<NavigationActionPolicy> _spotifyNavigation(
    InAppWebViewController controller,
    NavigationAction action,
  ) async {
    final uri = action.request.url;
    if (uri == null || uri.scheme != 'https') {
      return NavigationActionPolicy.CANCEL;
    }
    final host = uri.host.toLowerCase();
    if (action.isForMainFrame &&
        host != 'spotify.com' &&
        !host.endsWith('.spotify.com')) {
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  Future<void> _loadYoutubeMusicSegments(String id) async {
    try {
      final segments = await SponsorBlock().fetch(id);
      if (!mounted || id != _youtubeMusicVideoId) return;
      _youtubeMusicSegments = segments;
      if (segments.isNotEmpty) {
        setState(
          () => _message = 'SponsorBlock siap · ${segments.length} segmen',
        );
      }
    } catch (_) {
      // SponsorBlock is optional; music playback continues when unavailable.
    }
  }

  Future<void> _skipYoutubeMusicSponsor() async {
    final controller = _youtubeMusic;
    if (!mounted || controller == null || _youtubeMusicSegments.isEmpty) return;
    final encoded = _youtubeMusicSegments
        .map((segment) => '[${segment.start},${segment.end}]')
        .join(',');
    try {
      await controller.evaluateJavascript(
        source:
            '''(() => {
          const video = document.querySelector('video');
          if (!video) return;
          const time = video.currentTime;
          const segments = [$encoded];
          for (const segment of segments) {
            if (time >= segment[0] && time < segment[1]) {
              video.currentTime = segment[1];
              break;
            }
          }
        })()''',
      );
    } catch (_) {
      // Playback should not be interrupted by SponsorBlock failures.
    }
  }

  Future<void> _loadSegments() async {
    try {
      _segments = await SponsorBlock().fetch(widget.id);
      if (!mounted) return;
      setState(
        () => _message = _segments.isEmpty
            ? 'Belum ada segmen sponsor untuk video ini.'
            : 'SponsorBlock aktif · ${_segments.length} segmen',
      );
      _subscription = _youtube!.videoStateStream.listen((state) async {
        if (_seeking || !mounted) return;
        final time = state.position.inMilliseconds / 1000;
        for (final segment in _segments) {
          if (time >= segment.start &&
              time < segment.end &&
              !_skipped.contains(segment.start)) {
            _seeking = true;
            _skipped.add(segment.start);
            try {
              await _youtube!.seekTo(
                seconds: segment.end,
                allowSeekAhead: true,
              );
            } catch (_) {
              if (mounted) {
                setState(
                  () => _message =
                      'Segmen sponsor belum dapat dilewati. Video tetap dapat diputar.',
                );
              }
              break;
            } finally {
              _seeking = false;
            }
            if (mounted) setState(() => _message = 'Segmen sponsor dilewati');
            break;
          }
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'SponsorBlock tidak tersedia; video tetap dapat diputar.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _spotifySuspended) {
      _spotifySuspended = false;
      _spotify?.loadUrl(urlRequest: URLRequest(url: _spotifyUrl));
    }
    if (state == AppLifecycleState.resumed && _youtubeMusicSuspended) {
      _youtubeMusicSuspended = false;
      _youtubeMusic?.loadUrl(
        urlRequest: URLRequest(url: WebUri('https://music.youtube.com/')),
      );
    }
    if (state != AppLifecycleState.resumed) {
      _youtube?.pauseVideo();
      _youtubeMusic?.evaluateJavascript(
        source:
            "document.querySelectorAll('video,audio').forEach(e=>e.pause())",
      );
      if (_youtubeMusic != null) {
        _youtubeMusicSuspended = true;
        _youtubeMusic!.loadUrl(
          urlRequest: URLRequest(url: WebUri('about:blank')),
        );
      }
      _spotify?.evaluateJavascript(
        source:
            "document.querySelectorAll('audio,video').forEach(e=>e.pause())",
      );
      // Navigating away releases Spotify iframe buffers and stops iframe audio.
      if (_spotify != null) {
        _spotifySuspended = true;
        _spotify!.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _youtubeMusicSponsorTimer?.cancel();
    _youtubeMusicLoadTimer?.cancel();
    _spotifyLoadTimer?.cancel();
    _youtube?.close();
    _youtubeMusic?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
    _spotify?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocListener<PlayerCubit, PlayerState>(
    listenWhen: (previous, current) => !previous.playing && current.playing,
    listener: (context, state) {
      _youtube?.pauseVideo();
      _stopService();
    },
    child: Column(
      children: [
        if (_youtube != null)
          SizedBox(
            height: (MediaQuery.sizeOf(context).width * 9 / 16).clamp(220, 400),
            child: YoutubePlayer(
              controller: _youtube!,
              enableFullScreenOnVerticalDrag: false,
              autoFullScreen: false,
            ),
          ),
        if (widget.source == MusicSource.youtube && widget.youtubeMusicHome)
          SizedBox(
            height: widget.playerHeight ?? 680,
            child: Stack(
              children: [
                InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri('https://music.youtube.com/'),
                  ),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    mediaPlaybackRequiresUserGesture: false,
                  ),
                  onWebViewCreated: (controller) => _youtubeMusic = controller,
                  onLoadStart: (controller, url) =>
                      _beginWebLoad(spotify: false),
                  onLoadStop: (controller, url) =>
                      _finishWebLoad(spotify: false),
                  shouldOverrideUrlLoading: _youtubeMusicNavigation,
                  onUpdateVisitedHistory: (controller, url, isReload) {
                    final id = url?.queryParameters['v'];
                    if (id != null && id != _youtubeMusicVideoId) {
                      _youtubeMusicVideoId = id;
                      _youtubeMusicSegments = const [];
                      unawaited(_loadYoutubeMusicSegments(id));
                    }
                  },
                  onReceivedError: (controller, request, error) {
                    if (request.isForMainFrame == true && mounted) {
                      setState(
                        () => _message =
                            'YouTube Music gagal dimuat. Periksa koneksi internet.',
                      );
                      _failWebLoad(spotify: false);
                    }
                  },
                  onReceivedHttpError: (controller, request, response) {
                    if (request.isForMainFrame == true &&
                        (response.statusCode ?? 0) >= 400) {
                      _failWebLoad(spotify: false);
                    }
                  },
                ),
                _webLoadOverlay(
                  spotify: false,
                  loading: _youtubeMusicLoading,
                  failed: _youtubeMusicFailed,
                ),
              ],
            ),
          ),
        if (widget.source == MusicSource.spotify)
          SizedBox(
            height: widget.playerHeight ?? (widget.spotifyHome ? 680 : 360),
            child: Stack(
              children: [
                InAppWebView(
                  initialUrlRequest: URLRequest(url: _spotifyUrl),
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    mediaPlaybackRequiresUserGesture: false,
                  ),
                  onWebViewCreated: (controller) => _spotify = controller,
                  onLoadStart: (controller, url) =>
                      _beginWebLoad(spotify: true),
                  onLoadStop: (controller, url) =>
                      _finishWebLoad(spotify: true),
                  shouldOverrideUrlLoading: _spotifyNavigation,
                  onReceivedError: (controller, request, error) {
                    if (request.isForMainFrame == true && mounted) {
                      setState(
                        () => _message =
                            'Pemutar Spotify belum dapat dimuat. Periksa koneksi.',
                      );
                      _failWebLoad(spotify: true);
                    }
                  },
                  onReceivedHttpError: (controller, request, response) {
                    if (request.isForMainFrame == true &&
                        (response.statusCode ?? 0) >= 400) {
                      _failWebLoad(spotify: true);
                    }
                  },
                ),
                _webLoadOverlay(
                  spotify: true,
                  loading: _spotifyLoading,
                  failed: _spotifyFailed,
                ),
              ],
            ),
          ),
        if (_message != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(_message!)),
      ],
    ),
  );

  Widget _webLoadOverlay({
    required bool spotify,
    required bool loading,
    required bool failed,
  }) {
    if (!loading && !failed) return const SizedBox.shrink();
    final service = spotify ? 'Spotify' : 'YouTube Music';
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xFF111114),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  const CircularProgressIndicator()
                else
                  const Icon(Icons.wifi_off_rounded, size: 36),
                const SizedBox(height: 14),
                Text(
                  loading
                      ? 'Menghubungkan ke $service…'
                      : '$service belum dapat dimuat. Periksa koneksi internet.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                if (failed) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => _retryWebLoad(spotify: spotify),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Coba lagi'),
                      ),
                      TextButton.icon(
                        onPressed: () => _openOfficialService(spotify: spotify),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Buka layanan resmi'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ServicePlayerScreen extends StatelessWidget {
  const ServicePlayerScreen({super.key, required this.source});
  final MusicSource source;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final height =
        MediaQuery.sizeOf(context).height -
        kToolbarHeight -
        padding.top -
        padding.bottom;
    final youtube = source == MusicSource.youtube;
    return Scaffold(
      appBar: AppBar(title: Text(youtube ? 'YouTube Music' : 'Spotify')),
      body: SafeArea(
        child: ServicePlayer(
          source: source,
          id: '',
          sponsorBlock: youtube,
          youtubeMusicHome: youtube,
          spotifyHome: !youtube,
          playerHeight: height.clamp(360.0, 1200.0),
        ),
      ),
    );
  }
}
