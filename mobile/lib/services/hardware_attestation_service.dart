import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum TrustTier { untrusted, basic, verified }

class HardwareAttestationService {
  static const MethodChannel _channel = MethodChannel(
    'dev.saifmukhtar.kinetic/attestation',
  );

  /// Requests hardware attestation from the underlying OS.
  /// Uses Google Play Integrity API on Android and DeviceCheck on iOS.
  static Future<TrustTier> verifyDevice() async {
    if (kDebugMode ||
        Platform.isLinux ||
        Platform.isWindows ||
        Platform.isMacOS) {
      // Return verified for desktop testing
      return TrustTier.verified;
    }

    try {
      final String result = await _channel.invokeMethod('verifyDevice');

      switch (result) {
        case 'MEETS_STRONG_INTEGRITY':
        case 'VALID_DEVICE':
          return TrustTier.verified;
        case 'MEETS_BASIC_INTEGRITY':
          return TrustTier.basic;
        default:
          return TrustTier.untrusted;
      }
    } on PlatformException {
      debugPrint("Attestation failed: \${e.message}");
      return TrustTier.untrusted;
    }
  }
}
