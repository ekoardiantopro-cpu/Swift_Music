import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../player/presentation/player_cubit.dart';

class CarModeScreen extends StatelessWidget {
  const CarModeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mode berkendara')),
    body: BlocBuilder<PlayerCubit, PlayerState>(
      builder: (context, state) {
        final player = context.read<PlayerCubit>();
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  state.item?.title ?? 'Pilih lagu dari Library',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  state.item?.artist ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: 'Previous',
                      iconSize: 56,
                      onPressed: player.previous,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(88, 88),
                      ),
                      onPressed: state.item == null ? null : player.togglePlay,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Icon(
                          state.playing ? Icons.pause : Icons.play_arrow,
                          size: 64,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next',
                      iconSize: 56,
                      onPressed: player.next,
                      icon: const Icon(Icons.skip_next),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: 'Volume turun',
                      iconSize: 40,
                      onPressed: () => player.adjustVolume(-.05),
                      icon: const Icon(Icons.remove),
                    ),
                    Text(
                      '${(state.volume * 100).round()}%',
                      style: const TextStyle(fontSize: 24),
                    ),
                    IconButton(
                      tooltip: 'Volume naik',
                      iconSize: 40,
                      onPressed: () => player.adjustVolume(.05),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
