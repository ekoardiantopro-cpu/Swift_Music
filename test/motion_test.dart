import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_music/core/widgets/motion.dart';

void main() {
  testWidgets(
    'visualizer stops on pause, mute, reduced motion and hidden tabs',
    (tester) async {
      Future<void> show({
        bool playing = true,
        bool reduced = false,
        bool visible = true,
        double volume = 1,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: TickerMode(
                enabled: visible,
                child: Center(
                  child: SizedBox(
                    width: 240,
                    child: EqualizerVisualizer(
                      playing: playing,
                      volume: volume,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      await show();
      expect(tester.hasRunningAnimations, isTrue);
      await show(playing: false);
      expect(tester.hasRunningAnimations, isFalse);
      await show(volume: 0);
      expect(tester.hasRunningAnimations, isFalse);
      await show(reduced: true);
      expect(tester.hasRunningAnimations, isFalse);
      await show(visible: false);
      expect(tester.hasRunningAnimations, isFalse);
      await show();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
