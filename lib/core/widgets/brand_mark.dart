import 'package:flutter/material.dart';

/// Identitas yang sama dengan ikon launcher; decode sesuai ukuran tampil.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * 0.22),
    child: Image.asset(
      'assets/branding/swift_music_icon.png',
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
      cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
      excludeFromSemantics: true,
    ),
  );
}
