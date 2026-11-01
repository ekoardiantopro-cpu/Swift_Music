// Menghasilkan listing yang selalu sama dengan kode sumber implementasi.
const fs = require('node:fs');
const groups = [
  ['Bagian A — Dependensi, domain, dan data', ['pubspec.yaml',
    'lib/features/catalog/domain/track.dart', 'lib/features/catalog/domain/catalog_repository.dart',
    'lib/features/catalog/data/demo_catalog_repository.dart',
    'lib/features/catalog/data/local_audio_store.dart', 'lib/features/catalog/data/music_folder_source.dart', 'lib/features/catalog/data/device_catalog_repository.dart',
    'lib/features/library/data/library_repository.dart']],
  ['Bagian B — Native Android dan iOS', ['native/android/AndroidManifest.xml',
    'native/android/MainActivity.kt',
    'native/android/ic_stat_music_note.xml', 'native/android/keep.xml', 'native/ios/Info.plist', 'native/ios/AppDelegate.swift']],
  ['Bagian C — Handler dan state management', ['lib/features/player/data/swift_audio_handler.dart',
    'lib/features/player/presentation/player_cubit.dart', 'lib/features/player/presentation/artwork_style_cubit.dart', 'lib/features/library/presentation/library_cubit.dart',
    'lib/features/catalog/presentation/catalog_cubit.dart']],
  ['Bagian D — Entry point dan antarmuka lengkap', ['lib/main.dart', 'lib/core/theme/app_theme.dart',
    'lib/core/widgets/artwork.dart', 'lib/core/widgets/brand_mark.dart', 'lib/core/widgets/motion.dart', 'lib/core/widgets/track_tile.dart', 'lib/app/main_screen.dart',
    'lib/features/player/presentation/widgets/mini_player.dart', 'lib/features/player/presentation/widgets/responsive_player.dart', 'lib/features/player/presentation/widgets/album_stage.dart', 'lib/features/player/presentation/widgets/lyrics_panel.dart', 'lib/features/player/presentation/widgets/neon_visualizer.dart', 'lib/features/player/presentation/widgets/album_display.dart', 'lib/features/player/presentation/widgets/volume_control.dart', 'lib/features/player/presentation/now_playing_screen.dart',
    'lib/features/home/presentation/home_screen.dart', 'lib/features/search/presentation/search_screen.dart',
    'lib/features/library/presentation/library_screen.dart', 'lib/features/about/presentation/about_screen.dart']],
];
let output = '# Swift Music — Listing lengkap implementasi A–D\n\n';
groups[0][1].push('lib/features/catalog/data/audio_metadata_reader.dart', 'lib/features/catalog/data/folder_registry.dart', 'lib/features/catalog/domain/saved_music_folder.dart', 'lib/features/library/domain/music_playlist.dart', 'lib/features/library/data/playlist_repository.dart', 'lib/features/player/domain/lrc_document.dart');
groups[2][1].push('lib/features/library/presentation/playlist_cubit.dart');
groups[3][1].push('lib/app/catalog_lifecycle.dart', 'lib/features/library/presentation/collection_screens.dart', 'lib/features/library/presentation/library_sections.dart', 'lib/features/library/presentation/track_actions.dart');
groups[0][1].push('lib/features/player/data/playback_session_repository.dart', 'lib/features/player/domain/sleep_timer.dart', 'lib/features/library/data/collection_backup.dart', 'lib/features/catalog/domain/music_filter.dart');
groups[3][1].push('lib/features/player/presentation/widgets/sleep_timer_sheet.dart', 'lib/features/library/presentation/backup_screen.dart', 'lib/features/search/presentation/search_filters.dart');
output += 'Baca [README](../README.md) untuk arsitektur, struktur folder, setup, batas demo, dan status verifikasi. '
  + 'Listing ini dihasilkan dari source melalui `node tool/build-guide.cjs`.\n\n';
for (const [title, files] of groups) {
  output += `## ${title}\n\n`;
  for (const file of files) {
    const language = file.endsWith('.dart') ? 'dart' : file.endsWith('.kt') ? 'kotlin' : file.endsWith('.swift') ? 'swift' : file.endsWith('.yaml') ? 'yaml' : 'xml';
    output += `### ${file}\n\n\`\`\`${language}\n${fs.readFileSync(file, 'utf8').trimEnd()}\n\`\`\`\n\n`;
  }
}
fs.mkdirSync('docs', { recursive: true });
fs.writeFileSync('docs/IMPLEMENTATION.md', output);
console.log('docs/IMPLEMENTATION.md generated.');
