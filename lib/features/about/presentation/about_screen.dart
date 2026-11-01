import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/brand_mark.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  // Baca versi paket terpasang agar mengikuti pubspec dan build override.
  final Future<PackageInfo> _package = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Tentang Swift Music')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                const Center(child: BrandMark(size: 96)),
                const SizedBox(height: 20),
                const Text(
                  'Swift Music',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Musik favorit, selalu dekat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.secondary),
                ),
                const SizedBox(height: 32),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Versi aplikasi',
                          style: TextStyle(color: AppTheme.secondary),
                        ),
                        const SizedBox(height: 8),
                        FutureBuilder<PackageInfo>(
                          future: _package,
                          builder: (context, snapshot) {
                            final info = snapshot.data;
                            if (info != null) {
                              return Text(
                                '${info.version} (build ${info.buildNumber})',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            }
                            return Text(
                              snapshot.hasError
                                  ? 'Versi tidak tersedia'
                                  : 'Memuat versi…',
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Developer',
                          style: TextStyle(color: AppTheme.secondary),
                        ),
                        const SizedBox(height: 8),
                        const SelectableText(
                          'ekoardianto.pro@gmail.com',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
