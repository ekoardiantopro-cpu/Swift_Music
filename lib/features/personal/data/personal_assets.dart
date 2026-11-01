import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';

class PersonalAssets {
  PersonalAssets(this.directory);
  final Directory directory;
  Future<String?> pickCover() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
      dialogTitle: 'Pilih cover',
    );
    if (file == null) return null;
    final bytes = <int>[];
    await for (final chunk in file.readAsByteStream()) {
      if (bytes.length + chunk.length > 8 * 1024 * 1024) {
        throw const FormatException('Cover maksimal 8 MiB.');
      }
      bytes.addAll(chunk);
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      Uint8List.fromList(bytes),
    );
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final scale = math.min(
      1.0,
      768 / math.max(descriptor.width, descriptor.height),
    );
    late final ui.Codec codec;
    try {
      codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * scale).round()),
        targetHeight: math.max(1, (descriptor.height * scale).round()),
      );
    } finally {
      descriptor.dispose();
      buffer.dispose();
    }
    try {
      final frame = await codec.getNextFrame();
      try {
        final png = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (png == null) {
          throw const FormatException('Cover tidak dapat dibaca.');
        }
        final data = png.buffer.asUint8List();
        await directory.create(recursive: true);
        final target = File(
          '${directory.path}/cover-${sha256.convert(data)}.png',
        );
        await target.writeAsBytes(data, flush: true);
        return target.uri.toString();
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }
}
