import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/artwork.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/motion.dart';
import '../../catalog/domain/catalog_repository.dart';
import '../../catalog/domain/track.dart';
import '../../catalog/presentation/catalog_cubit.dart';
import '../../library/presentation/library_cubit.dart';
import '../../player/presentation/player_cubit.dart';
import '../../personal/presentation/personal_cubit.dart';
import '../../personal/presentation/music_center_screen.dart';
import '../../streaming/presentation/source_icons.dart';
import '../../streaming/presentation/streaming_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  String get _greeting {
    final hour = DateTime.now().hour;
    return hour < 12
        ? 'Good Morning'
        : hour < 18
        ? 'Good Afternoon'
        : 'Good Evening';
  }

  @override
  Widget build(BuildContext context) {
    context.watch<CatalogCubit>();
    final tracks = context.read<CatalogRepository>().tracks;
    void play(Track track) => context.read<PlayerCubit>().playId(track.id);
    return BlocBuilder<PlayerCubit, PlayerState>(
      builder: (context, playerState) {
        final localTrack =
            playerState.playing &&
            playerState.item?.extras?['url'] is String &&
            Uri.tryParse(playerState.item!.extras!['url'] as String)?.scheme ==
                'file';
        final currentLocal = localTrack
            ? tracks
                  .where((track) => track.id == playerState.item!.id)
                  .firstOrNull
            : null;
        return _HomeEntrance(
          index: 0,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              _HomeEntrance(
                index: 0,
                child: Row(
                  children: [
                    const BrandMark(size: 30),
                    const SizedBox(width: 8),
                    const Text(
                      'SWIFT MUSIC',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        letterSpacing: 2,
                      ),
                    ),
                    const Spacer(),
                    if (PersonalScope.maybeOf(context) != null)
                      IconButton(
                        tooltip: 'Music Center',
                        icon: const Icon(Icons.dashboard_customize_outlined),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const MusicCenterScreen(),
                          ),
                        ),
                      ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppTheme.purple, AppTheme.pink],
                        ),
                      ),
                      child: const Icon(Icons.headphones, size: 20),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _HomeEntrance(
                index: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Text(
                      'Temukan musik favorit berikutnya.',
                      style: TextStyle(color: AppTheme.secondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (currentLocal != null)
                AnimatedSwitcher(
                  duration: motionDuration(context, 380),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, .04),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Container(
                    key: ValueKey(currentLocal.id),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF54218A),
                          Color(0xFFB62D83),
                          Color(0xFF21192F),
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'NOW PLAYING · LOCAL',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 2,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                currentLocal.title,
                                style: const TextStyle(
                                  fontSize: 26,
                                  height: 1.1,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currentLocal.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: () =>
                                    context.read<PlayerCubit>().togglePlay(),
                                icon: Icon(
                                  playerState.playing
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                                label: Text(
                                  playerState.playing ? 'Pause' : 'Play',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.album_outlined,
                          size: 76,
                          color: Colors.white54,
                        ),
                      ],
                    ),
                  ),
                ),
              if (currentLocal != null) const SizedBox(height: 28),
              const _Heading('Recently Played'),
              BlocBuilder<LibraryCubit, LibraryState>(
                builder: (context, state) {
                  final ordered = state.recent
                      .map((id) => tracks.where((track) => track.id == id))
                      .expand((matches) => matches)
                      .take(6)
                      .toList();
                  if (ordered.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Lagu yang diputar akan muncul di sini.',
                        style: TextStyle(color: AppTheme.secondary),
                      ),
                    );
                  }
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: ordered.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisExtent:
                          64 *
                          (MediaQuery.textScalerOf(context).scale(14) / 14)
                              .clamp(1, 3),
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemBuilder: (context, i) => PressScale(
                      child: Material(
                        color: const Color(0xFF232229),
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => play(ordered[i]),
                          child: Row(
                            children: [
                              Artwork(
                                url: ordered[i].artUrl,
                                size: 56,
                                radius: 8,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  ordered[i].title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              if (currentLocal != null) const SizedBox(height: 28),
              const _Heading('Layanan Musik'),
              const _ServiceCards(),
            ],
          ),
        );
      },
    );
  }
}

class _HomeEntrance extends StatefulWidget {
  const _HomeEntrance({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_HomeEntrance> createState() => _HomeEntranceState();
}

class _HomeEntranceState extends State<_HomeEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  );
  late final Animation<double> _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(Duration(milliseconds: widget.index * 80), () {
      if (mounted && fullMotionAllowed(context)) _controller.forward();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!fullMotionAllowed(context)) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _animation,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _animation.value,
      child: Transform.translate(
        offset: Offset(0, 14 * (1 - _animation.value)),
        child: child,
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.title);
  final String title;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Container(width: 3, height: 20, color: AppTheme.pink),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
      ],
    ),
  );
}

class _ServiceCards extends StatelessWidget {
  const _ServiceCards();

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 132,
    child: Row(
      children: [
        Expanded(
          child: _ServiceCard(
            source: MusicSource.spotify,
            title: 'Spotify',
            subtitle: 'Cari dan putar musik di sini',
            color: const Color(0xFF176B46),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ServiceCard(
            source: MusicSource.youtube,
            title: 'YouTube Music',
            subtitle: 'Trending, rekomendasi, dan pemutar musik',
            color: const Color(0xFF9F1830),
          ),
        ),
      ],
    ),
  );
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({
    required this.source,
    required this.title,
    required this.subtitle,
    required this.color,
  });
  final MusicSource source;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) => PressScale(
    child: Material(
      color: color,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (_) => StreamingScreen(initial: source),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SourceIcon(source, size: 30),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
