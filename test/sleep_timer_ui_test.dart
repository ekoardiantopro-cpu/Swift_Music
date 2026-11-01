import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/features/player/presentation/player_cubit.dart';
import 'package:swift_music/features/player/presentation/widgets/sleep_timer_sheet.dart';

class _Handler extends BaseAudioHandler {
  final modes = <String>[];
  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    modes.add('${extras?['mode']}:${extras?['minutes']}');
    customState.add({
      'sleep': extras?['mode'] == 'cancel'
          ? <String, dynamic>{}
          : {
              'deadlineMs': DateTime.now()
                  .add(const Duration(minutes: 15))
                  .millisecondsSinceEpoch,
            },
    });
    return null;
  }
}

void main() {
  testWidgets(
    'sleep timer sheet activates and cancels through shared audio handler',
    (tester) async {
      final handler = _Handler();
      final player = PlayerCubit(handler, positionStream: const Stream.empty());
      await tester.pumpWidget(
        BlocProvider<PlayerCubit>(
          create: (_) => player,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showSleepTimer(context),
                  child: const Text('Timer'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Timer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15 menit'));
      await tester.pumpAndSettle();
      expect(handler.modes, ['duration:15']);
      expect(player.state.sleepActive, isTrue);
      await tester.tap(find.text('Timer'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Batalkan timer'));
      await tester.pumpAndSettle();
      expect(player.state.sleepActive, isFalse);
      expect(handler.modes.last, 'cancel:null');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
