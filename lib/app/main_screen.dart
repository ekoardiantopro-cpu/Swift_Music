import 'package:flutter/material.dart';
import 'package:salomon_bottom_bar/salomon_bottom_bar.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/motion.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/search/presentation/search_screen.dart';
import '../features/library/presentation/library_screen.dart';
import '../features/player/presentation/widgets/mini_player.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  late final AnimationController _motion = AnimationController(
    vsync: this,
    value: 1,
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _motion,
    curve: Curves.easeOutCubic,
  );
  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    _motion.duration = motionDuration(context, 340);
    _motion.forward(from: 0);
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    // Tab bukan route baru: Back dari Search/Library harus kembali ke Home.
    canPop: _index == 0,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && _index != 0) {
        _select(0);
      }
    },
    child: Scaffold(
      body: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: FadeTransition(
              opacity: _curve,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .025),
                  end: Offset.zero,
                ).animate(_curve),
                child: IndexedStack(
                  index: _index,
                  children: [
                    TickerMode(enabled: _index == 0, child: const HomeScreen()),
                    TickerMode(
                      enabled: _index == 1,
                      child: const SearchScreen(),
                    ),
                    TickerMode(
                      enabled: _index == 2,
                      child: const LibraryScreen(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(localOnly: true),
            SalomonBottomBar(
              duration: motionDuration(context, 360),
              currentIndex: _index,
              selectedItemColor: AppTheme.green,
              unselectedItemColor: AppTheme.secondary,
              onTap: _select,
              items: [
                SalomonBottomBarItem(
                  icon: const Icon(Icons.home_rounded),
                  title: const Text('Home'),
                ),
                SalomonBottomBarItem(
                  icon: const Icon(Icons.search),
                  title: const Text('Search'),
                ),
                SalomonBottomBarItem(
                  icon: const Icon(Icons.library_music_outlined),
                  title: const Text('Library'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
