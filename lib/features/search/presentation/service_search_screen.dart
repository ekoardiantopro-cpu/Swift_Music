import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_webview_flutter/in_app_webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../streaming/presentation/source_icons.dart';

class ServiceSearchScreen extends StatefulWidget {
  const ServiceSearchScreen({
    super.key,
    required this.source,
    required this.query,
  });
  final MusicSource source;
  final String query;

  @override
  State<ServiceSearchScreen> createState() => _ServiceSearchScreenState();
}

class _ServiceSearchScreenState extends State<ServiceSearchScreen> {
  InAppWebViewController? _controller;
  Timer? _loadTimer;
  bool _loading = true;
  bool _failed = false;

  bool get _youtube => widget.source == MusicSource.youtube;

  Uri get _searchUri => _youtube
      ? Uri.https('music.youtube.com', '/search', {'q': widget.query})
      : Uri.https('open.spotify.com', '/search/${Uri.encodeComponent(widget.query)}');

  void _startLoading() {
    _loadTimer?.cancel();
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    _loadTimer = Timer(const Duration(seconds: 18), () {
      if (mounted && _loading) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    });
  }

  void _finishLoading() {
    _loadTimer?.cancel();
    if (mounted) {
      setState(() {
        _loading = false;
        _failed = false;
      });
    }
  }

  void _failLoading() {
    _loadTimer?.cancel();
    if (mounted) {
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _retry() async {
    _startLoading();
    final controller = _controller;
    if (controller == null) return;
    await controller.loadUrl(urlRequest: URLRequest(url: WebUri(_searchUri.toString())));
  }

  Future<void> _openExternal() => launchUrl(
    _searchUri,
    mode: LaunchMode.externalApplication,
  );

  @override
  void dispose() {
    _loadTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          SourceIcon(widget.source, size: 24),
          const SizedBox(width: 10),
          Text(_youtube ? 'YouTube Music' : 'Spotify'),
        ],
      ),
    ),
    body: Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(_searchUri.toString())),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            mediaPlaybackRequiresUserGesture: true,
          ),
          onWebViewCreated: (controller) => _controller = controller,
          onLoadStart: (controller, url) => _startLoading(),
          onLoadStop: (controller, url) => _finishLoading(),
          onReceivedError: (controller, request, error) {
            if (request.isForMainFrame == true) _failLoading();
          },
          onReceivedHttpError: (controller, request, response) {
            if (request.isForMainFrame == true &&
                (response.statusCode ?? 0) >= 400) {
              _failLoading();
            }
          },
          shouldOverrideUrlLoading: (controller, action) async {
            final uri = action.request.url;
            if (uri == null || uri.scheme != 'https') {
              return NavigationActionPolicy.CANCEL;
            }
            final host = uri.host.toLowerCase();
            final allowed = _youtube
                ? host == 'music.youtube.com' ||
                      host.endsWith('.youtube.com') ||
                      host == 'accounts.google.com' ||
                      host == 'consent.google.com'
                : host == 'spotify.com' || host.endsWith('.spotify.com');
            return allowed
                ? NavigationActionPolicy.ALLOW
                : NavigationActionPolicy.CANCEL;
          },
        ),
        if (_loading || _failed)
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xFF111114),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_loading)
                        const CircularProgressIndicator()
                      else
                        const Icon(Icons.wifi_off_rounded, size: 36),
                      const SizedBox(height: 14),
                      Text(
                        _loading
                            ? 'Membuka hasil di ${_youtube ? 'YouTube Music' : 'Spotify'}…'
                            : 'Layanan belum dapat dimuat. Periksa koneksi internet.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      if (_failed) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          children: [
                            TextButton.icon(
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Coba lagi'),
                            ),
                            TextButton.icon(
                              onPressed: _openExternal,
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
          ),
      ],
    ),
  );
}
