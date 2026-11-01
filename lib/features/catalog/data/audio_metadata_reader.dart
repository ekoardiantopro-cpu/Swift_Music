import 'dart:io';
import 'package:flutter/services.dart';

abstract interface class AudioMetadataReader {
  Future<Map<String, dynamic>> read(File audio, File cover);
}

class NoAudioMetadataReader implements AudioMetadataReader {
  const NoAudioMetadataReader();
  @override
  Future<Map<String, dynamic>> read(File audio, File cover) async => {};
}

class NativeAudioMetadataReader implements AudioMetadataReader {
  const NativeAudioMetadataReader();
  @override
  Future<Map<String, dynamic>> read(File audio, File cover) async {
    if (!Platform.isAndroid && !Platform.isIOS) return {};
    return await const MethodChannel(
          'com.swiftmusic/metadata',
        ).invokeMapMethod<String, dynamic>('read', {
          'path': audio.path,
          'coverPath': cover.path,
        }) ??
        {};
  }
}
