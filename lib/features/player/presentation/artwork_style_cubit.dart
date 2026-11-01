import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ArtworkStyle {
  cover('Cover', 'Sampul album klasik'),
  lyrics('Lirik', 'Lirik yang dapat digulir dan ditambahkan sendiri'),
  vinyl('Vinyl', 'Piringan berputar saat lagu dimainkan'),
  spectrum('Spectrum', 'Lingkaran spektrum neon biru dan magenta'),
  wave('Wave', 'Gelombang cahaya berlapis yang mengalir'),
  pulse('Pulse', 'Sampul dengan denyut cahaya lembut');

  const ArtworkStyle(this.label, this.description);
  final String label;
  final String description;
}

class ArtworkStyleState {
  const ArtworkStyleState({
    this.style = ArtworkStyle.cover,
    this.saving = false,
    this.error,
  });
  final ArtworkStyle style;
  final bool saving;
  final String? error;
}

class ArtworkStyleCubit extends Cubit<ArtworkStyleState> {
  ArtworkStyleCubit({
    Future<String?> Function()? load,
    Future<void> Function(String)? save,
  }) : _load = load ?? (() => SharedPreferencesAsync().getString(_key)),
       _save =
           save ?? ((value) => SharedPreferencesAsync().setString(_key, value)),
       super(const ArtworkStyleState()) {
    unawaited(_restore());
  }
  static const _key = 'player_artwork_style';
  final Future<String?> Function() _load;
  final Future<void> Function(String) _save;
  bool _selected = false;
  bool _persisting = false;
  ArtworkStyle? _pending;

  Future<void> next() => select(
    ArtworkStyle.values[(ArtworkStyle.values.indexOf(state.style) + 1) %
        ArtworkStyle.values.length],
  );

  Future<void> _restore() async {
    try {
      final saved = await _load();
      if (isClosed || _selected) return;
      final style = ArtworkStyle.values
          .where((style) => style.name == saved)
          .firstOrNull;
      if (style != null) emit(ArtworkStyleState(style: style));
    } catch (_) {
      // Preferensi gagal dibaca tidak boleh menghalangi pemutar audio.
    }
  }

  Future<void> select(ArtworkStyle style) async {
    if (isClosed) return;
    _selected = true;
    _pending = style;
    emit(ArtworkStyleState(style: style, saving: true));
    if (_persisting) return;
    _persisting = true;
    String? error;
    while (_pending != null && !isClosed) {
      final target = _pending!;
      _pending = null;
      try {
        await _save(target.name);
        error = null;
      } catch (_) {
        error = 'Pilihan diterapkan, tetapi belum berhasil disimpan.';
      }
    }
    _persisting = false;
    if (!isClosed) emit(ArtworkStyleState(style: state.style, error: error));
  }
}
