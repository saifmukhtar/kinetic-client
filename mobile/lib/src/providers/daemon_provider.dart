import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinetic/src/rust/frb_generated.dart';

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

class DaemonNotifier extends Notifier<DaemonState> {
  @override
  DaemonState build() {
    return const DaemonState();
  }

  bool _isInitialized = false;

  Future<void> startDaemon() async {
    if (_isInitialized || state.status == DaemonStatus.running) return;
    
    state = state.copyWith(status: DaemonStatus.starting);
    try {
      await RustLib.init();
      _isInitialized = true;
      state = state.copyWith(status: DaemonStatus.running, errorMessage: null);
    } catch (e) {
      state = state.copyWith(
        status: DaemonStatus.error, 
        errorMessage: e.toString()
      );
    }
  }
}

final daemonProvider = NotifierProvider<DaemonNotifier, DaemonState>(() {
  return DaemonNotifier();
});
