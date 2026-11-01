import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../personal/presentation/personal_cubit.dart';
import '../../../personal/presentation/personal_dialogs.dart';
import '../../domain/queue_summary.dart';
import '../player_cubit.dart';

class QueueTools extends StatelessWidget {
  const QueueTools({super.key});
  @override
  Widget build(BuildContext context) => BlocBuilder<PlayerCubit, PlayerState>(
    builder: (context, state) {
      final player = context.read<PlayerCubit>();
      final personal = PersonalScope.maybeOf(context)?.controller;
      final summary = QueueSummary(
        durations: state.queueItems.map((item) => item.duration).toList(),
        currentIndex: state.queueItems.indexWhere(
          (item) => item.id == state.item?.id,
        ),
        position: state.position,
        speed: state.speed,
        shuffled: state.shuffle,
        now: DateTime.now(),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            Text(summary.label, style: const TextStyle(fontSize: 12)),
            Row(
              children: [
                IconButton(
                  tooltip: 'Cari dalam antrean',
                  icon: const Icon(Icons.search),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const QueueSearchScreen(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Batalkan perubahan antrean',
                  icon: const Icon(Icons.undo),
                  onPressed: state.canUndoQueue ? player.undoQueue : null,
                ),
                if (personal != null)
                  IconButton(
                    tooltip: 'Simpan antrean',
                    icon: const Icon(Icons.save_outlined),
                    onPressed: state.queueItems.isEmpty
                        ? null
                        : () async {
                            final name = await askMusicText(
                              context,
                              'Nama antrean',
                              maxLength: 80,
                            );
                            if (name != null && name.trim().isNotEmpty) {
                              await personal.saveQueue(
                                name,
                                state.queueItems.map((i) => i.id).toList(),
                                currentId: state.item?.id,
                                positionMs: state.position.inMilliseconds,
                              );
                            }
                          },
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

class QueueSearchScreen extends StatefulWidget {
  const QueueSearchScreen({super.key});
  @override
  State<QueueSearchScreen> createState() => _QueueSearchScreenState();
}

class _QueueSearchScreenState extends State<QueueSearchScreen> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Cari dalam antrean')),
    body: BlocBuilder<PlayerCubit, PlayerState>(
      builder: (context, state) {
        final query = _controller.text.trim().toLowerCase();
        final items = state.queueItems
            .where(
              (item) =>
                  '${item.title} ${item.artist}'.toLowerCase().contains(query),
            )
            .toList();
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _controller,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Judul atau artis',
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, i) => ListTile(
                  title: Text(items[i].title),
                  subtitle: Text(items[i].artist ?? ''),
                  selected: state.item?.id == items[i].id,
                  onTap: () => context.read<PlayerCubit>().playId(items[i].id),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
