import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../features/catalog/presentation/catalog_cubit.dart';

class CatalogLifecycle extends StatefulWidget {
  const CatalogLifecycle({super.key, required this.child});
  final Widget child;
  @override
  State<CatalogLifecycle> createState() => _CatalogLifecycleState();
}

class _CatalogLifecycleState extends State<CatalogLifecycle>
    with WidgetsBindingObserver {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resume();
    });
  }

  void _resume() {
    _timer?.cancel();
    context.read<CatalogCubit>().checkSavedFolders();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) context.read<CatalogCubit>().checkSavedFolders();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resume();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
