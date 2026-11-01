import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/rendering.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/motion.dart';
import '../../domain/lrc_document.dart';
import '../../../personal/presentation/personal_cubit.dart';

/// Plain text lyrics supplied by the catalog or user; no fabricated timing.
class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.trackId,
    required this.title,
    required this.fallback,
    this.load,
    this.save,
    this.position = Duration.zero,
    this.onSeek,
  });
  final String trackId;
  final String title;
  final String fallback;
  final Future<String?> Function(String)? load;
  final Future<void> Function(String, String)? save;
  final Duration position;
  final ValueChanged<Duration>? onSeek;
  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  String? _custom;
  int _revision = 0;
  bool _saving = false;
  final _scroll = ScrollController();
  String? _parsedText;
  LrcDocument _document = LrcDocument.parse('');
  int _lastActive = -2;
  DateTime _manualUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String get _key => 'lyrics_${widget.trackId}';
  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void didUpdateWidget(LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackId != widget.trackId) {
      _custom = null;
      _revision++;
      _lastActive = -2;
      _restore();
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _importLrc({bool translation = false}) async {
    final id = widget.trackId;
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Pilih lirik LRC atau TXT',
        type: FileType.custom,
        allowedExtensions: ['lrc', 'txt'],
      );
      if (file == null || !mounted || widget.trackId != id) return;
      final bytes = <int>[];
      await for (final chunk in file.readAsByteStream()) {
        if (bytes.length + chunk.length > 256 * 1024) {
          throw const FormatException(
            'File lirik terlalu besar (maksimal 256 KiB).',
          );
        }
        bytes.addAll(chunk);
      }
      String text;
      if (bytes.length >= 2 &&
          ((bytes[0] == 255 && bytes[1] == 254) ||
              (bytes[0] == 254 && bytes[1] == 255))) {
        final little = bytes[0] == 255;
        text = String.fromCharCodes([
          for (var i = 2; i + 1 < bytes.length; i += 2)
            little
                ? bytes[i] | bytes[i + 1] << 8
                : bytes[i] << 8 | bytes[i + 1],
        ]);
      } else {
        text = utf8.decode(bytes);
      }
      if (text.length > 100000) {
        throw const FormatException('Teks lirik terlalu panjang.');
      }
      if (translation) text = '${_custom ?? widget.fallback}\n$text';
      if (text.length > 100000) {
        throw const FormatException('Gabungan lirik terlalu panjang.');
      }
      if (mounted && widget.trackId == id) await _store(text);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Lirik gagal diimpor. Gunakan TXT/LRC UTF-8 atau UTF-16 maksimal 256 KiB.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _store(String result) async {
    final revision = ++_revision;
    final id = widget.trackId;
    final key = _key;
    final personal = context
        .getInheritedWidgetOfExactType<PersonalScope>()
        ?.controller;
    setState(() => _saving = true);
    try {
      if (widget.save != null) {
        await widget.save!(id, result);
      } else if (personal != null) {
        await personal.mark(id, {'lyrics': result});
      } else {
        await SharedPreferencesAsync().setString(key, result);
      }
      if (mounted && revision == _revision) {
        setState(() {
          _custom = result;
          _lastActive = -2;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lirik belum berhasil disimpan. Coba lagi.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restore() async {
    final revision = _revision;
    try {
      final personal = context
          .getInheritedWidgetOfExactType<PersonalScope>()
          ?.controller;
      final value =
          await (widget.load?.call(widget.trackId) ??
              (personal?.state
                          .song(widget.trackId)
                          .values
                          .containsKey('lyrics') ==
                      true
                  ? Future.value(
                      personal!.state.song(widget.trackId).text('lyrics'),
                    )
                  : SharedPreferencesAsync().getString(_key)));
      if (personal != null &&
          value != null &&
          mounted &&
          revision == _revision &&
          !personal.state.song(widget.trackId).values.containsKey('lyrics')) {
        await personal.mark(widget.trackId, {'lyrics': value});
      }
      if (mounted && revision == _revision) setState(() => _custom = value);
    } catch (_) {
      /* Lirik katalog tetap dapat dibaca tanpa preferensi. */
    }
  }

  Future<void> _edit() async {
    final trackId = widget.trackId;
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _LyricsEditor(initial: _custom ?? ''),
    );
    if (result == null || !mounted || widget.trackId != trackId) return;
    await _store(result);
  }

  @override
  Widget build(BuildContext context) {
    final text = (_custom?.trim().isNotEmpty ?? false)
        ? _custom!
        : widget.fallback;
    if (_parsedText != text) {
      _parsedText = text;
      _document = LrcDocument.parse(text);
      _lastActive = -2;
    }
    final offset =
        PersonalScope.maybeOf(
          context,
        )?.state.song(widget.trackId).number('lyricOffset') ??
        0;
    final active = _document.activeIndex(
      widget.position + Duration(milliseconds: offset),
    );
    final extent = 84.0 * MediaQuery.textScalerOf(context).scale(1);
    if (active != _lastActive) {
      _lastActive = active;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_scroll.hasClients ||
            active < 0 ||
            DateTime.now().isBefore(_manualUntil)) {
          return;
        }
        final target = (active * extent - extent / 2).clamp(
          0.0,
          _scroll.position.maxScrollExtent,
        );
        if (MediaQuery.disableAnimationsOf(context)) {
          _scroll.jumpTo(target);
        } else {
          _scroll.animateTo(
            target,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
          );
        }
      });
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF462B69), Color(0xFF17132A)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Lirik',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Impor lirik LRC',
                enabled: !_saving,
                onSelected: (value) =>
                    _importLrc(translation: value == 'translation'),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'primary', child: Text('Impor lirik')),
                  PopupMenuItem(
                    value: 'translation',
                    child: Text('Gabungkan terjemahan LRC'),
                  ),
                ],
                icon: const Icon(Icons.file_open_outlined, size: 22),
              ),
              IconButton(
                tooltip: 'Tambah atau edit lirik',
                onPressed: _saving ? null : _edit,
                icon: const Icon(
                  Icons.edit_note_rounded,
                  color: AppTheme.green,
                ),
              ),
            ],
          ),
          Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.secondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _document.synced
                ? NotificationListener<UserScrollNotification>(
                    onNotification: (notification) {
                      if (notification.direction != ScrollDirection.idle) {
                        _manualUntil = DateTime.now().add(
                          const Duration(seconds: 4),
                        );
                      }
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      itemExtent: extent,
                      itemCount: _document.lines.length,
                      itemBuilder: (context, index) => GestureDetector(
                        onLongPress: widget.onSeek == null
                            ? null
                            : () => widget.onSeek!(_document.lines[index].time),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedDefaultTextStyle(
                            duration: motionDuration(context, 250),
                            style: TextStyle(
                              fontSize: 20,
                              height: 1.3,
                              fontWeight: FontWeight.w700,
                              color: index == active
                                  ? AppTheme.green
                                  : AppTheme.secondary,
                            ),
                            child: Text(
                              _document.lines[index].text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : Scrollbar(
                    child: SingleChildScrollView(
                      key: ValueKey(widget.trackId),
                      child: Text(
                        text.trim().isEmpty
                            ? 'Lirik belum tersedia. Ketuk ikon pensil untuk menambahkan lirik.'
                            : text,
                        style: const TextStyle(
                          fontSize: 20,
                          height: 1.65,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LyricsEditor extends StatefulWidget {
  const _LyricsEditor({required this.initial});
  final String initial;
  @override
  State<_LyricsEditor> createState() => _LyricsEditorState();
}

class _LyricsEditorState extends State<_LyricsEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Lirik lagu'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: TextField(
          controller: _controller,
          minLines: 5,
          maxLines: 10,
          maxLength: 100000,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            hintText: 'Tempel atau tulis lirik lagu ini',
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Batal'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Simpan'),
      ),
    ],
  );
}
