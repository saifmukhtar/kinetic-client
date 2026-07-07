import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:kinetic/src/rust/frb_generated.dart';
import 'package:kinetic/src/rust/api/daemon.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:kinetic/src/utils/error_handler.dart';

enum DaemonStatus { stopped, starting, running, error, rootDetected }

class DaemonState {
  final DaemonStatus status;
  final String? errorMessage;
  final bool isRooted;

  const DaemonState({
    this.status = DaemonStatus.stopped,
    this.errorMessage,
    this.isRooted = false,
  });

  DaemonState copyWith({DaemonStatus? status, String? errorMessage, bool? isRooted}) {
    return DaemonState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      isRooted: isRooted ?? this.isRooted,
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (this.state.status == DaemonStatus.error) {
        startDaemon();
      } else if (this.state.status == DaemonStatus.running) {
        reconnectNetwork();
      }
    }
  }

  bool _isInitialized = false;

  Future<void> startDaemon({String? overrideNpub, bool bypassRootCheck = false}) async {
    if (state.status == DaemonStatus.running || state.status == DaemonStatus.starting) return;
    
    state = state.copyWith(status: DaemonStatus.starting);
    try {
      if (!_isInitialized) {
        await RustLib.init();
        _isInitialized = true;
      }
      
      bool isRooted = false;
      try {
        isRooted = await checkDeviceRooted();
      } catch (_) {
        // Fallback safely if FFI fails
      }

      // If it's rooted, we force them to provide a desktop npub to tether to, 
      // UNLESS they explicitly clicked "Skip for now".
      if (isRooted && overrideNpub == null && !bypassRootCheck) {
        state = state.copyWith(status: DaemonStatus.rootDetected, isRooted: true);
        return;
      }

      final appDir = await getApplicationDocumentsDirectory();
      const storage = FlutterSecureStorage();
      final identityString = await storage.read(key: 'kinetic_identity');
      Uint8List? identityBytes;
      if (identityString != null) {
        try {
          identityBytes = base64Decode(identityString);
        } catch (_) {}
      }
      
      final newIdentityBytes = await initDaemon(
        appDir: appDir.path, 
        identityBytes: identityBytes,
        targetDesktopNpub: overrideNpub,
      );
      
      if (newIdentityBytes != null) {
        await storage.write(key: 'kinetic_identity', value: base64Encode(newIdentityBytes));
      }
      state = state.copyWith(status: DaemonStatus.running, errorMessage: null, isRooted: isRooted);
    } catch (e) {
      state = state.copyWith(
        status: DaemonStatus.error, 
        errorMessage: parseKineticError(e)
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
