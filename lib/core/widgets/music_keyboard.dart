import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../features/player/presentation/player_cubit.dart';

class MusicKeyboard extends StatelessWidget {
  const MusicKeyboard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent ||
          HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isAltPressed ||
          HardwareKeyboard.instance.isMetaPressed) {
        return KeyEventResult.ignored;
      }
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused?.widget is EditableText ||
          focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
        return KeyEventResult.ignored;
      }
      final player = context.read<PlayerCubit>();
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.space) {
        player.togglePlay();
      } else if (key == LogicalKeyboardKey.arrowRight) {
        player.next();
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        player.previous();
      } else if (key == LogicalKeyboardKey.arrowUp) {
        player.adjustVolume(.05);
      } else if (key == LogicalKeyboardKey.arrowDown) {
        player.adjustVolume(-.05);
      } else if (key == LogicalKeyboardKey.keyM) {
        player.toggleMute();
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    },
    child: child,
  );
}
