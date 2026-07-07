import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinetic/src/screens/browser/browser_tab.dart';
import 'package:kinetic/src/screens/home_screen.dart';
import 'package:kinetic/src/screens/manage/manage_kin_tab.dart';
import 'package:kinetic/src/screens/tethered_mode_screen.dart';
import 'package:kinetic/src/providers/daemon_provider.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _browserNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'browser');
final _manageNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'manage');

final routerProvider = Provider<GoRouter>((ref) {
  final daemonState = ref.watch(daemonProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/browser',
    redirect: (context, state) {
      final isRootDetected = daemonState.status == DaemonStatus.rootDetected;
      final isTetheredScreen = state.uri.path == '/tethered_mode';

      if (isRootDetected && !isTetheredScreen) {
        return '/tethered_mode';
      }

      if (!isRootDetected && isTetheredScreen) {
        return '/browser';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/tethered_mode',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const TetheredModeScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          // The HomeScreen wraps the shell with the bottom nav bar
          return HomeScreen(navigationShell: navigationShell);
        },
        branches: [
          // Browser Branch
          StatefulShellBranch(
            navigatorKey: _browserNavigatorKey,
            routes: [
              GoRoute(
                path: '/browser',
                builder: (context, state) => const BrowserTab(),
              ),
            ],
          ),
          // Manage Kin Branch
          StatefulShellBranch(
            navigatorKey: _manageNavigatorKey,
            routes: [
              GoRoute(
                path: '/manage',
                builder: (context, state) => const ManageKinTab(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
