import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

class Artwork extends StatelessWidget {
  const Artwork({super.key, required this.url, this.size, this.radius = 16});
  final String url;
  final double? size;
  final double radius;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: url.isEmpty
        ? SizedBox(
            width: size,
            height: size,
            child: const ColoredBox(
              color: Color(0xFF292339),
              child: Center(child: Icon(Icons.music_note_rounded)),
            ),
          )
        : Uri.tryParse(url)?.scheme == 'file'
        ? Image.file(
            File.fromUri(Uri.parse(url)),
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: ((size ?? 160) * MediaQuery.devicePixelRatioOf(context))
                .round()
                .clamp(64, 1024),
            errorBuilder: (_, error, stack) => SizedBox.square(
              dimension: size,
              child: const ColoredBox(
                color: Color(0xFF292339),
                child: Icon(Icons.album_outlined),
              ),
            ),
          )
        : CachedNetworkImage(
            memCacheWidth:
                ((size ?? 160) * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(64, 1024),
            memCacheHeight:
                ((size ?? 160) * MediaQuery.devicePixelRatioOf(context))
                    .round()
                    .clamp(64, 1024),
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (_, _) => SizedBox(
              width: size,
              height: size,
              child: const ColoredBox(
                color: Color(0xFF292339),
                child: Center(child: Icon(Icons.music_note_rounded)),
              ),
            ),
            errorWidget: (_, _, _) => SizedBox(
              width: size,
              height: size,
              child: const ColoredBox(
                color: Color(0xFF292339),
                child: Center(child: Icon(Icons.album_rounded)),
              ),
            ),
          ),
  );
}
