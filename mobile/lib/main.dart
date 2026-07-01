import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinetic/src/routing/app_router.dart';
import 'package:kinetic/src/theme/app_theme.dart';

import 'dart:ui';
import 'package:kinetic/background_tasks.dart';
import 'package:kinetic/src/rust/frb_generated.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    await RustLib.init();
  } catch (e) {
    debugPrint('RustLib already initialized (likely due to hot restart): $e');
  }
  await BackgroundTasks.init();

  // Edge Case 96: Global Error Boundary for FFI and native crashes
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Flutter Error: \${details.exception}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Native/Platform Error: \$error');
    // Prevents the app from instantly crashing to OS on unhandled async FFI errors
    return true; 
  };

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
