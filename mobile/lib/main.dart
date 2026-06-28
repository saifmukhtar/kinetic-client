import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinetic/src/routing/app_router.dart';
import 'package:kinetic/src/theme/app_theme.dart';

void main() {
  runApp(
    const ProviderScope(
      child: KineticApp(),
    ),
  );
}

class KineticApp extends ConsumerWidget {
  const KineticApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    
    return MaterialApp.router(
      title: 'Kinetic',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
