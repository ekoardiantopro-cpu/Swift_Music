import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_theme.dart';
import 'artwork_style_cubit.dart';
import 'widgets/responsive_player.dart';
import '../../../core/widgets/motion.dart';
import 'widgets/volume_control.dart';
import 'widgets/sleep_timer_sheet.dart';
import 'widgets/queue_tools.dart';
import '../../personal/presentation/personal_cubit.dart';
import '../../catalog/domain/catalog_repository.dart';
import 'player_cubit.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});
  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  bool _showVolume = false;
  bool _locked = false;
  Timer? _volumeTimer;
  bool _volumeHeld = false;
  void _scheduleVolumeHide() {
    _volumeTimer?.cancel();
    if (!_showVolume || _volumeHeld) return;
    _volumeTimer = Timer(const Duration(seconds: 3), _hideVolume);
  }

  void _hideVolume() {
    _volumeTimer?.cancel();
    _volumeHeld = false;
    if (mounted && _showVolume) setState(() => _showVolume = false);
  }

  void _toggleVolume() {
    setState(() => _showVolume = !_showVolume);
    if (_showVolume) {
      _scheduleVolumeHide();
    } else {
      _volumeTimer?.cancel();
    }
  }

  @override
  void dispose() {
    _volumeTimer?.cancel();
    super.dispose();
  }

  double? _dragPosition;
  String? _dragTrack;
  void _chooseArtwork() {
    final preference = context.read<ArtworkStyleCubit>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: BlocBuilder<ArtworkStyleCubit, ArtworkStyleState>(
            bloc: preference,
            builder: (context, selection) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Tampilan album',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ),
                for (final style in ArtworkStyle.values)
                  ListTile(
                    enabled: !selection.saving,
                    selected: selection.style == style,
                    leading: Icon(switch (style) {
                      ArtworkStyle.cover => Icons.image_outlined,
                      ArtworkStyle.lyrics => Icons.lyrics_outlined,
                      ArtworkStyle.vinyl => Icons.album_rounded,
                      ArtworkStyle.spectrum => Icons.radar_rounded,
                      ArtworkStyle.wave => Icons.waves_rounded,
                      ArtworkStyle.pulse => Icons.blur_on_rounded,
                    }),
                    title: Text(style.label),
                    subtitle: Text(style.description),
                    trailing: selection.style == style
                        ? const Icon(Icons.check_circle, color: AppTheme.green)
                        : null,
                    onTap: () async {
                      await preference.select(style);
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      if (mounted && preference.state.error != null) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          SnackBar(content: Text(preference.state.error!)),
                        );
                      }
                    },
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _devices() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Connect to a device',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Simulasi UI · audio tetap diputar di perangkat ini.',
                  style: TextStyle(color: AppTheme.secondary),
                ),
                const ListTile(
                  leading: Icon(Icons.smartphone, color: AppTheme.green),
                  title: Text('This device'),
                  subtitle: Text('Sedang digunakan'),
                  trailing: Icon(Icons.check, color: AppTheme.green),
                ),
                const ListTile(
                  enabled: false,
                  leading: Icon(Icons.speaker_group_outlined),
                  title: Text('Living room speaker'),
                  subtitle: Text('Demo · tidak tersambung'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<PlayerCubit, PlayerState>(
    builder: (context, state) {
      final item = state.item;
      if (item == null) {
        return Scaffold(
          appBar: AppBar(),
          body: const Center(child: Text('Pilih lagu.')),
        );
      }
      final cubit = context.read<PlayerCubit>();
      final maximum = math.max(1.0, state.duration.inMilliseconds.toDouble());
      final position =
          ((_dragTrack == item.id ? _dragPosition : null) ??
                  state.position.inMilliseconds.toDouble())
              .clamp(0.0, maximum)
              .toDouble();
      final tracks = context.read<CatalogRepository>().tracks.where(
        (track) => track.id == item.id,
      );
      final lyrics = tracks.isEmpty
          ? (item.extras?['lyrics'] as String? ?? 'Lirik belum tersedia.')
          : tracks.first.lyrics;
      return PopScope<Object?>(
        canPop: !_showVolume && !_locked,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            if (_locked) {
              setState(() => _locked = false);
            } else {
              _hideVolume();
            }
          }
        },
        child: Scaffold(
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: switch (PersonalScope.maybeOf(
                  context,
                )?.state.text('playerBackground', 'purple')) {
                  'black' => const [
                    Color(0xFF151515),
                    Color(0xFF121212),
                    AppTheme.background,
                  ],
                  'blue' => const [
                    Color(0xFF173A50),
                    Color(0xFF141D2B),
                    AppTheme.background,
                  ],
                  'warm' => const [
                    Color(0xFF503022),
                    Color(0xFF261B19),
                    AppTheme.background,
                  ],
                  _ => const [
                    Color(0xFF482644),
                    Color(0xFF20192D),
                    AppTheme.background,
                  ],
                },
                stops: [0, .42, 1],
              ),
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, viewport) => Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: _locked,
                        child: ResponsivePlayer(
                          state: state,
                          lyrics: lyrics,
                          position: position,
                          maximum: maximum,
                          onVolume: _toggleVolume,
                          onArtwork: _chooseArtwork,
                          onDevices: _devices,
                          onQueue: () => _queue(context),
                          onSleepTimer: () => showSleepTimer(context),
                          onLock: PersonalScope.maybeOf(context) == null
                              ? null
                              : () => setState(() => _locked = true),
                          onSeekStart: (value) => setState(() {
                            _dragTrack = item.id;
                            _dragPosition = value;
                          }),
                          onSeekChanged: (value) =>
                              setState(() => _dragPosition = value),
                          onSeekEnd: (value) {
                            if (_dragTrack == item.id) {
                              cubit.seek(Duration(milliseconds: value.round()));
                            }
                            setState(() {
                              _dragTrack = null;
                              _dragPosition = null;
                            });
                          },
                        ),
                      ),
                    ),
                    if (_locked)
                      Positioned(
                        left: 32,
                        right: 32,
                        bottom: 20,
                        child: FilledButton.icon(
                          onPressed: () => setState(() => _locked = false),
                          icon: const Icon(Icons.lock_open),
                          label: const Text('Buka kunci sentuhan'),
                        ),
                      ),
                    if (_showVolume)
                      Positioned.fill(
                        child: GestureDetector(
                          key: const Key('volume-dismiss-area'),
                          behavior: HitTestBehavior.opaque,
                          onTap: _hideVolume,
                          child: const ColoredBox(color: Colors.transparent),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: IgnorePointer(
                          ignoring: !_showVolume,
                          child: AnimatedSwitcher(
                            duration: motionDuration(context, 220),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position:
                                        Tween<Offset>(
                                          begin: const Offset(-.3, 0),
                                          end: Offset.zero,
                                        ).animate(
                                          CurvedAnimation(
                                            parent: animation,
                                            curve: Curves.easeOutCubic,
                                          ),
                                        ),
                                    child: child,
                                  ),
                                ),
                            child: !_showVolume
                                ? const SizedBox.shrink()
                                : VolumeControl(
                                    key: const Key('floating-volume'),
                                    height: math.min(
                                      320.0,
                                      math.max(200.0, viewport.maxHeight - 32),
                                    ),
                                    onClose: _hideVolume,
                                    onInteraction: _scheduleVolumeHide,
                                    onHold: () {
                                      _volumeHeld = true;
                                      _volumeTimer?.cancel();
                                    },
                                    onRelease: () {
                                      _volumeHeld = false;
                                      _scheduleVolumeHide();
                                    },
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  void _queue(BuildContext context) {
    final player = context.read<PlayerCubit>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: BlocBuilder<PlayerCubit, PlayerState>(
            bloc: player,
            buildWhen: (a, b) =>
                a.queueItems != b.queueItems || a.item?.id != b.item?.id,
            builder: (context, state) => Column(
              children: [
                const ListTile(
                  title: Text(
                    'Antrean pemutaran',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('Tahan dan geser untuk mengubah urutan'),
                ),
                const QueueTools(),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: state.queueItems.length,
                    onReorderItem: (from, to) {
                      player.moveQueue(from, to);
                    },
                    itemBuilder: (context, index) {
                      final item = state.queueItems[index];
                      return ListTile(
                        key: ValueKey(item.id),
                        leading: ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: item.id == state.item?.id
                                ? AppTheme.green
                                : Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          item.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: 'Keluarkan dari antrean',
                          icon: const Icon(Icons.close),
                          onPressed: () => player.removeQueue(item),
                        ),
                        onTap: () => player.playId(item.id),
                      );
                    },
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
