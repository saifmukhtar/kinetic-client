import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinetic/src/screens/browser/browser_tab.dart';
import 'package:kinetic/src/screens/home_screen.dart';
import 'package:kinetic/src/screens/identity/identity_tab.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _browserNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'browser');
final _identityNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'identity');

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/browser',
    routes: [
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
          // Identity Branch
          StatefulShellBranch(
            navigatorKey: _identityNavigatorKey,
            routes: [
              GoRoute(
                path: '/identity',
                builder: (context, state) => const IdentityTab(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
