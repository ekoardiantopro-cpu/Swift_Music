import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../player_cubit.dart';

Future<void> showSleepTimer(BuildContext context) {
  final player = context.read<PlayerCubit>();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: BlocBuilder<PlayerCubit, PlayerState>(
        bloc: player,
        builder: (context, state) {
          final deadline = state.sleep['deadlineMs'];
          final until = deadline is int
              ? DateTime.fromMillisecondsSinceEpoch(deadline)
              : null;
          final time = until == null
              ? ''
              : '${until.hour.toString().padLeft(2, '0')}:${until.minute.toString().padLeft(2, '0')}';
          Future<void> select(String mode, {int? minutes}) async {
            await player.setSleepTimer(mode, minutes: minutes);
            if (sheetContext.mounted) Navigator.pop(sheetContext);
          }

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text(
                    'Sleep timer',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
                  ),
                  subtitle: Text(
                    until != null
                        ? 'Aktif hingga $time. Musik akan dijeda.'
                        : state.sleep['trackId'] != null
                        ? 'Aktif: jeda setelah lagu ini selesai.'
                        : 'Pilih kapan musik dijeda otomatis.',
                  ),
                ),
                for (final minutes in [15, 30, 60])
                  ListTile(
                    leading: const Icon(Icons.bedtime_outlined),
                    title: Text('$minutes menit'),
                    onTap: () => select('duration', minutes: minutes),
                  ),
                ListTile(
                  leading: const Icon(Icons.music_note_outlined),
                  title: const Text('Setelah lagu ini selesai'),
                  subtitle: const Text(
                    'Berganti lagu secara manual membatalkan pilihan ini.',
                  ),
                  onTap: state.item == null ? null : () => select('track'),
                ),
                if (state.sleepActive)
                  ListTile(
                    leading: const Icon(Icons.timer_off_outlined),
                    title: const Text('Batalkan timer'),
                    onTap: () => select('cancel'),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Text(
                    'Timer memakai waktu berjalan, termasuk saat musik dijeda. Timer tidak dipulihkan setelah aplikasi dihentikan paksa.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}
