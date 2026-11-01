import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/motion.dart';
import 'package:webview_flutter/webview_flutter.dart';

class _ChartOption {
  const _ChartOption(this.source, this.label, this.uri, this.host);
  final String source;
  final String label;
  final Uri uri;
  final String host;
}

class YouTubeTrendingChart extends StatefulWidget {
  const YouTubeTrendingChart({super.key});

  @override
  State<YouTubeTrendingChart> createState() => _YouTubeTrendingChartState();
}

class _YouTubeTrendingChartState extends State<YouTubeTrendingChart> {
  int _selected = 0;
  static final _charts = <_ChartOption>[
    _ChartOption('YouTube Music', 'Trending Indonesia', Uri.https('charts.youtube.com', '/charts/TrendingVideos/ID/RightNow'), 'charts.youtube.com'),
    _ChartOption('YouTube Music', 'Top Songs · Mingguan', Uri.https('charts.youtube.com', '/charts/TopSongs/ID/weekly'), 'charts.youtube.com'),
    _ChartOption('YouTube Music', 'Top Music Videos · Harian', Uri.https('charts.youtube.com', '/charts/TopVideos/ID/daily'), 'charts.youtube.com'),
    _ChartOption('YouTube Music', 'Top Artists · Mingguan', Uri.https('charts.youtube.com', '/charts/TopArtists/ID/weekly'), 'charts.youtube.com'),
    _ChartOption('Spotify', 'Top 50 Indonesia', Uri.https('open.spotify.com', '/embed/playlist/37i9dQZEVXbObFQZ3JLcXt'), 'open.spotify.com'),
    _ChartOption('Spotify', 'Top 50 Global', Uri.https('open.spotify.com', '/embed/playlist/37i9dQZEVXbLiRSasKsNU9'), 'open.spotify.com'),
    _ChartOption('Spotify', 'Lagu Indonesia · Harian', Uri.https('charts.spotify.com', '/charts/view/regional-id-daily/latest'), 'charts.spotify.com'),
    _ChartOption('Spotify', 'Lagu Indonesia · Mingguan', Uri.https('charts.spotify.com', '/charts/view/regional-id-weekly/latest'), 'charts.spotify.com'),
    _ChartOption('Spotify', 'Global · Harian', Uri.https('charts.spotify.com', '/charts/view/regional-global-daily/latest'), 'charts.spotify.com'),
    _ChartOption('Spotify', 'Global · Mingguan', Uri.https('charts.spotify.com', '/charts/view/regional-global-weekly/latest'), 'charts.spotify.com'),
  ];

  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (request) {
      if (request.url == 'about:blank') return NavigationDecision.navigate;
      final uri = Uri.tryParse(request.url);
      final host = uri?.host;
      final allowed = host == _charts[_selected].host ||
          (_charts[_selected].source == 'YouTube Music' &&
              host == 'music.youtube.com') ||
          (_charts[_selected].source == 'Spotify' &&
              (host == 'spotify.com' || host?.endsWith('.spotify.com') == true));
      return uri?.scheme == 'https' && allowed
          ? NavigationDecision.navigate
          : NavigationDecision.prevent;
    }))
    ..loadRequest(_charts.first.uri);

  void _selectChart(int index) {
    if (index == _selected) return;
    setState(() => _selected = index);
    _controller.loadRequest(_charts[index].uri);
  }

  @override
  Widget build(BuildContext context) {
    final option = _charts[_selected];
    final sourceCharts = _charts
        .asMap()
        .entries
        .where((entry) => entry.value.source == option.source)
        .toList();
    final accent = option.source == 'Spotify'
        ? AppTheme.green
        : const Color(0xFFFF1744);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (final source in ['YouTube Music', 'Spotify'])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: source == 'YouTube Music' ? 8 : 0,
                  ),
                  child: _SourceCard(
                    title: source,
                    spotify: source == 'Spotify',
                    selected: option.source == source,
                    onTap: () {
                      final index = _charts.indexWhere(
                        (chart) => chart.source == source,
                      );
                      _selectChart(index);
                    },
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: sourceCharts.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final chart = sourceCharts[index];
              final selected = chart.key == _selected;
              return PressScale(
                child: Material(
                  color: selected
                      ? accent.withValues(alpha: .2)
                      : const Color(0xFF232229),
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _selectChart(chart.key),
                    child: AnimatedContainer(
                      duration: motionDuration(context, 280),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected
                              ? accent.withValues(alpha: .55)
                              : Colors.white.withValues(alpha: .06),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          chart.value.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: selected ? accent : Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
          height: 420,
            child: WebViewWidget(controller: _controller),
          ),
        ),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.title,
    required this.spotify,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool spotify;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = spotify ? AppTheme.green : const Color(0xFFFF1744);
    return PressScale(
      child: Material(
        color: selected
            ? accent.withValues(alpha: .14)
            : const Color(0xFF232229),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: motionDuration(context, 320),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: .65)
                    : Colors.white.withValues(alpha: .07),
                width: selected ? 1.4 : 1,
              ),
            ),
            child: Row(
              children: [
                _ServiceBrandIcon(spotify: spotify, accent: accent),
                const SizedBox(width: 10),
                AnimatedContainer(
                  duration: motionDuration(context, 320),
                  width: 4,
                  height: selected ? 34 : 28,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        spotify ? 'Spotify charts' : 'YouTube charts',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? accent : AppTheme.secondary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedSwitcher(
                  duration: motionDuration(context, 240),
                  child: Icon(
                    selected ? Icons.check_circle : Icons.chevron_right,
                    key: ValueKey(selected),
                    size: 19,
                    color: selected ? accent : AppTheme.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceBrandIcon extends StatelessWidget {
  const _ServiceBrandIcon({required this.spotify, required this.accent});

  final bool spotify;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: accent.withValues(alpha: .15),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Center(
      child: spotify
          ? CustomPaint(
              size: const Size(24, 24),
              painter: _SpotifyMark(accent),
            )
          : const Icon(Icons.smart_display_rounded, color: Color(0xFFFF1744)),
    ),
  );
}

class _SpotifyMark extends CustomPainter {
  const _SpotifyMark(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index < 3; index++) {
      paint.strokeWidth = 2.4 - index * .35;
      canvas.drawPath(
        Path()
          ..moveTo(3.0 + index, 8.0 + index * 4)
          ..quadraticBezierTo(12, 4.0 + index * 4, 21.0 - index, 10.0 + index * 3),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_SpotifyMark oldDelegate) => oldDelegate.color != color;
}
