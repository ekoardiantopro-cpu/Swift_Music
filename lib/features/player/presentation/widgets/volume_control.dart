import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';
import '../player_cubit.dart';

/// A floating vertical panel; it never takes space in the player layout.
class VolumeControl extends StatelessWidget {
  const VolumeControl({
    super.key,
    required this.height,
    required this.onClose,
    required this.onInteraction,
    required this.onHold,
    required this.onRelease,
  });
  final double height;
  final VoidCallback onClose;
  final VoidCallback onInteraction;
  final VoidCallback onHold;
  final VoidCallback onRelease;
  @override
  Widget build(BuildContext context) => BlocBuilder<PlayerCubit, PlayerState>(
    buildWhen: (before, after) => before.volume != after.volume,
    builder: (context, state) {
      final player = context.read<PlayerCubit>();
      void action(VoidCallback callback) {
        onInteraction();
        callback();
      }

      return Listener(
        onPointerDown: (_) => onHold(),
        onPointerUp: (_) => onRelease(),
        onPointerCancel: (_) => onRelease(),
        child: SizedBox(
          key: const Key('volume-overlay'),
          width: 80,
          height: height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Material(
                  elevation: 16,
                  color: const Color(0xFF24232D),
                  borderRadius: BorderRadius.circular(30),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        Text(
                          '${(state.volume * 100).round()}%',
                          style: const TextStyle(
                            color: AppTheme.green,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Volume naik',
                          onPressed: () =>
                              action(() => player.adjustVolume(.05)),
                          icon: const Icon(Icons.add_rounded),
                        ),
                        Expanded(
                          child: RotatedBox(
                            quarterTurns: 3,
                            child: Slider(
                              key: const Key('volume-slider'),
                              value: state.volume,
                              semanticFormatterCallback: (value) =>
                                  'Volume aplikasi ${(value * 100).round()} persen',
                              onChanged: (value) =>
                                  action(() => player.setVolume(value)),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Volume turun',
                          onPressed: () =>
                              action(() => player.adjustVolume(-.05)),
                          icon: const Icon(Icons.remove_rounded),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: IconButton(
                                tooltip: state.volume == 0
                                    ? 'Aktifkan suara'
                                    : 'Bisukan',
                                onPressed: () => action(player.toggleMute),
                                icon: MotionIcon(
                                  state.volume == 0
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                  color: AppTheme.green,
                                ),
                              ),
                            ),
                            Expanded(
                              child: IconButton(
                                tooltip: 'Tutup volume',
                                onPressed: onClose,
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
