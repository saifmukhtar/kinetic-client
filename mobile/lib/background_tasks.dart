import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'src/rust/api/delegation.dart';
import 'src/rust/frb_generated.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:kinetic/services/secure_storage_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // Check connectivity early (Mobile Goes Offline Early - 103)
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        debugPrint("Background Task: No internet connection. Aborting.");
        return Future.value(false); // Reschedule
      }

      // Must initialize rust bridge in the background isolate
      await RustLib.init();
      
      final prefs = await SharedPreferences.getInstance();
      final namesList = prefs.getStringList('delegated_names') ?? [];
      
      bool allSuccess = true;

      for (final name in namesList) {
        // Use SecureStorageService to handle Local Storage Wipe (156) gracefully
        final privateKeyStr = await SecureStorageService.read('private_key_$name');
        
        if (privateKeyStr != null) {
          final privateKeyBytes = privateKeyStr
              .split(',')
              .map((e) => int.parse(e))
              .toList();
          
          final success = await broadcastMobileHeartbeat(
            name: name,
            privateKeyBytes: privateKeyBytes,
          );
          if (!success) allSuccess = false;
        }
      }
        
      debugPrint("Background Task Heartbeat status: $allSuccess");
      return Future.value(allSuccess);
    } catch (e) {
      debugPrint("Background Task Error: $e");
      return Future.value(false); // Retries based on workmanager backoff policy
    }
  });
}

class BackgroundTasks {
  static const String heartbeatTask = "kinetic_heartbeat_task";

  static Future<void> init() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
  }

  static void scheduleHeartbeat() {
    Workmanager().registerPeriodicTask(
      "kinetic_heartbeat_1",
      heartbeatTask,
      frequency: const Duration(hours: 12),
      constraints: Constraints(
        networkType: NetworkType.connected, // Only run when connected to internet
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }
}
