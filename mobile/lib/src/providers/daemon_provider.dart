import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinetic/src/rust/frb_generated.dart';
import 'package:kinetic/src/rust/api/daemon.dart';

enum DaemonStatus { stopped, starting, running, error }

class DaemonState {
  final DaemonStatus status;
  final String? errorMessage;

  const DaemonState({
    this.status = DaemonStatus.stopped,
    this.errorMessage,
  });

  DaemonState copyWith({DaemonStatus? status, String? errorMessage}) {
    return DaemonState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class DaemonNotifier extends Notifier<DaemonState> with WidgetsBindingObserver {
  @override
  DaemonState build() {
    WidgetsBinding.instance.addObserver(this);
    return const DaemonState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (appState == AppLifecycleState.resumed) {
      if (state.status == DaemonStatus.error) {
        // Retry daemon initialization if we were stuck in error state (Edge Case 92)
        startDaemon();
      } else if (state.status == DaemonStatus.running) {
        // Re-bootstrap network to recover from OS background socket termination (Edge Case 84)
        reconnectNetwork();
      }
    }
  }

  bool _isInitialized = false;

  Future<void> startDaemon() async {
    if (state.status == DaemonStatus.running || state.status == DaemonStatus.starting) return;
    
    state = state.copyWith(status: DaemonStatus.starting);
    try {
      if (!_isInitialized) {
        await RustLib.init();
        _isInitialized = true;
      }
      await initDaemon(bootstrapNodes: []);
      state = state.copyWith(status: DaemonStatus.running, errorMessage: null);
    } catch (e) {
      state = state.copyWith(
        status: DaemonStatus.error, 
        errorMessage: e.toString()
      );
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}

final daemonProvider = NotifierProvider<DaemonNotifier, DaemonState>(() {
  return DaemonNotifier();
});
