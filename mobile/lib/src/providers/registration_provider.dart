import 'dart:convert';
import 'dart:async';
import 'dart:math' as dart_math;
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kinetic/services/hardware_attestation_service.dart';
import 'package:kinetic/src/services/nostr_service.dart';
import 'package:kinetic/src/rust/api/delegation.dart';
import 'package:http/http.dart' as http;

enum RegistrationStatus {
  idle,
  attesting,
  requestingVdf,
  pollingVdf,
  broadcasting,
  success,
  error,
}

class RegistrationState {
  final RegistrationStatus status;
  final String? errorMessage;
  final String? desktopUrl;
  
  // For polling VDF
  final String? challengeHex;

  const RegistrationState({
    this.status = RegistrationStatus.idle,
    this.errorMessage,
    this.desktopUrl,
    this.challengeHex,
  });

  RegistrationState copyWith({
    RegistrationStatus? status,
    String? errorMessage,
    String? desktopUrl,
    String? challengeHex,
  }) {
    return RegistrationState(
      status: status ?? this.status,
      errorMessage: errorMessage,
      desktopUrl: desktopUrl ?? this.desktopUrl,
      challengeHex: challengeHex ?? this.challengeHex,
    );
  }
}

class RegistrationNotifier extends Notifier<RegistrationState> {
  Timer? _pollingTimer;

  @override
  RegistrationState build() {
    _initDesktopUrl();
    _resumePendingVdf(); // For Case 103
    return const RegistrationState();
  }
  
  Future<void> _initDesktopUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('saved_desktop_url');
    if (savedUrl != null && savedUrl.isNotEmpty) {
      state = state.copyWith(desktopUrl: savedUrl);
    }
  }

  void setDesktopUrl(String url) async {
    state = state.copyWith(desktopUrl: url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_desktop_url', url);
  }

  Future<void> _resumePendingVdf() async {
    final prefs = await SharedPreferences.getInstance();
    final pendingJson = prefs.getString('pending_vdf');
    if (pendingJson != null) {
      try {
        final data = jsonDecode(pendingJson);
        final desktopUrl = data['desktopUrl'] as String;
        final name = data['name'] as String;
        final challengeHex = data['challengeHex'] as String;
        
        final saltStr = data['salt'] as String;
        final salt = Uint8List.fromList(saltStr.split(',').map(int.parse).toList());
        final drandPulse = BigInt.parse(data['drandPulse'] as String);
        final drandRandomness = data['drandRandomness'] as String;
        final iterations = BigInt.parse(data['iterations'] as String);

        final jobResponse = VdfJobResponse(
          challengeHex: challengeHex,
          salt: salt,
          drandPulse: drandPulse,
          drandRandomness: drandRandomness,
          iterations: iterations,
        );

        const secureStorage = FlutterSecureStorage();
        final keyStr = await secureStorage.read(key: 'private_key_$name');
        if (keyStr == null) return;
        
        final privateKeyBytes = keyStr.split(',').map(int.parse).toList();

        state = state.copyWith(
          status: RegistrationStatus.pollingVdf,
          challengeHex: challengeHex,
          desktopUrl: desktopUrl,
        );

        if (desktopUrl.startsWith('npub')) {
          _waitForNostrDm(desktopUrl, name, privateKeyBytes, jobResponse);
        } else {
          _startPolling(desktopUrl, name, privateKeyBytes, jobResponse);
        }
      } catch (e) {
        prefs.remove('pending_vdf');
      }
    }
  }

  Future<void> _savePendingVdf(String desktopUrl, String name, VdfJobResponse jobResponse) async {
    final prefs = await SharedPreferences.getInstance();
    final data = {
      'desktopUrl': desktopUrl,
      'name': name,
      'challengeHex': jobResponse.challengeHex,
      'salt': jobResponse.salt.join(','),
      'drandPulse': jobResponse.drandPulse.toString(),
      'drandRandomness': jobResponse.drandRandomness,
      'iterations': jobResponse.iterations.toString(),
    };
    await prefs.setString('pending_vdf', jsonEncode(data));
  }

  Future<void> _clearPendingVdf() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('pending_vdf');
  }

  Future<void> _waitForNostrDm(String desktopUrl, String name, List<int> privateKeyBytes, VdfJobResponse vdfJobResponse) async {
    final String desktopHex = NostrService.decodeNpub(desktopUrl);
    final encryptedReply = await NostrService.listenForDm(desktopUrl, desktopHex);
    
    if (encryptedReply != null) {
      final proofBytes = await decryptVdfProofNostr(
        desktopNpub: desktopUrl, 
        privateKeyBytes: privateKeyBytes, 
        encryptedContent: encryptedReply
      );
      
      await _broadcastReveal(name, privateKeyBytes, vdfJobResponse, proofBytes);
    } else {
      state = state.copyWith(status: RegistrationStatus.error, errorMessage: "Failed to receive VDF proof from node");
    }
  }


  Future<void> startRegistration(String name) async {
    final desktopUrl = state.desktopUrl ?? 'http://10.0.2.2:8080';
    
    // 1. Hardware Attestation
    state = state.copyWith(status: RegistrationStatus.attesting);
    final trustTier = await HardwareAttestationService.verifyDevice();
    
    // Define what constitutes a "local" node vs a "public" node
    final isLocalNode = desktopUrl.contains('localhost') || 
                        desktopUrl.contains('127.0.0.1') || 
                        desktopUrl.contains('10.0.2.2') || 
                        desktopUrl.startsWith('http://192.168.') ||
                        desktopUrl.startsWith('http://10.');

    if (trustTier == TrustTier.untrusted) {
      if (!isLocalNode) {
        state = state.copyWith(
          status: RegistrationStatus.error, 
          errorMessage: "Rooted devices cannot use public nodes. Please run your own local Desktop Node."
        );
        return;
      }
      // If it is a local node, we allow the rooted device to proceed!
    }

    // 1.5 Check name limit (Max 3 for all trusted devices)
    final prefs = await SharedPreferences.getInstance();
    final namesList = prefs.getStringList('delegated_names') ?? [];
    if (namesList.length >= 3 && !namesList.contains(name)) {
      state = state.copyWith(status: RegistrationStatus.error, errorMessage: "Maximum limit of 3 names reached for this device.");
      return;
    }

    try {
      // Generate a secure random Ed25519 private key scalar for this specific domain
      final random = dart_math.Random.secure();
      final privateKeyBytes = List.generate(32, (_) => random.nextInt(256));
      if (desktopUrl.startsWith('npub')) {
        // --- NOSTR FLOW ---
        state = state.copyWith(status: RegistrationStatus.requestingVdf);
        final result = await prepareVdfRequestNostr(
          desktopNpub: desktopUrl,
          name: name,
          privateKeyBytes: privateKeyBytes,
          difficultyBits: 20, 
        );
        
        final vdfJobResponse = result.$1;
        final eventJson = result.$2;

        await NostrService.publishEvent(eventJson);

        state = state.copyWith(
          status: RegistrationStatus.pollingVdf,
          challengeHex: vdfJobResponse.challengeHex,
        );

        const secureStorage = FlutterSecureStorage();
        await secureStorage.write(key: 'private_key_$name', value: privateKeyBytes.join(','));
        await _savePendingVdf(desktopUrl, name, vdfJobResponse);
        
        _waitForNostrDm(desktopUrl, name, privateKeyBytes, vdfJobResponse);
      } else {
        // --- HTTP FLOW (Local Node) ---
        state = state.copyWith(status: RegistrationStatus.requestingVdf);
        final vdfJobResponse = await requestVdfProofFromDesktop(
          desktopUrl: desktopUrl,
          name: name,
          privateKeyBytes: privateKeyBytes,
          difficultyBits: 20,
        );

        state = state.copyWith(
          status: RegistrationStatus.pollingVdf,
          challengeHex: vdfJobResponse.challengeHex,
        );

        const secureStorage = FlutterSecureStorage();
        await secureStorage.write(key: 'private_key_$name', value: privateKeyBytes.join(','));
        await _savePendingVdf(desktopUrl, name, vdfJobResponse);
        
        _startPolling(desktopUrl, name, privateKeyBytes, vdfJobResponse);
      }
    } catch (e) {
      state = state.copyWith(status: RegistrationStatus.error, errorMessage: e.toString());
    }
  }

  void _startPolling(String desktopUrl, String name, List<int> privateKeyBytes, VdfJobResponse jobResponse) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        final proofBytes = await pollVdfProofFromDesktop(
          desktopUrl: desktopUrl,
          challengeHex: jobResponse.challengeHex,
        );

        if (proofBytes != null) {
          timer.cancel();
          await _broadcastReveal(name, privateKeyBytes, jobResponse, proofBytes);
        }
      } catch (e) {
        // Ignore polling errors
      }
    });
  }

  Future<void> _broadcastReveal(String name, List<int> privateKeyBytes, VdfJobResponse jobResponse, List<int> proofBytes) async {
    state = state.copyWith(status: RegistrationStatus.broadcasting);
    
    try {
      final success = await broadcastMobileReveal(
        name: name,
        payload: [], // Empty payload for initial registration
        privateKeyBytes: privateKeyBytes,
        vdfProofBytes: proofBytes,
        salt: jobResponse.salt,
        drandPulse: jobResponse.drandPulse,
        drandRandomness: jobResponse.drandRandomness,
      );

      if (success) {
        // Save to SharedPreferences for Heartbeats (Name List)
        final prefs = await SharedPreferences.getInstance();
        final namesList = prefs.getStringList('delegated_names') ?? [];
        if (!namesList.contains(name)) {
          namesList.add(name);
          await prefs.setStringList('delegated_names', namesList);
        }
        
        await _clearPendingVdf();
        
        state = state.copyWith(status: RegistrationStatus.success);
      } else {
        state = state.copyWith(status: RegistrationStatus.error, errorMessage: "Failed to broadcast reveal to DHT.");
      }
    } catch (e) {
      state = state.copyWith(status: RegistrationStatus.error, errorMessage: e.toString());
    }
  }

  void reset() {
    _pollingTimer?.cancel();
    state = const RegistrationState();
  }
}

final registrationProvider = NotifierProvider<RegistrationNotifier, RegistrationState>(() {
  return RegistrationNotifier();
});

// --- HTTP Fallbacks ---
Future<VdfJobResponse> requestVdfProofFromDesktop({
  required String desktopUrl,
  required String name,
  required List<int> privateKeyBytes,
  required int difficultyBits,
}) async {
  // Derive the Ed25519 verifying key (public key) from the private key bytes.
  // derivePublicKeyBytesSync is a #[frb(sync)] FFI call generated by flutter_rust_bridge.
  final pubkeyBytes = derivePublicKeyBytesSync(privateKeyBytes: privateKeyBytes);
  final pubkeyHex = pubkeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  final res = await http.post(
    Uri.parse('$desktopUrl/vdf/request'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'name': name,
      'difficulty': difficultyBits,
      'pubkey': pubkeyHex,
    })
  );
  if (res.statusCode != 200) throw Exception("HTTP VDF Request Failed: ${res.statusCode} ${res.body}");
  final data = jsonDecode(res.body);
  return VdfJobResponse(
    challengeHex: data['challengeHex'],
    salt: Uint8List.fromList(List<int>.from(data['salt'])),
    drandPulse: BigInt.parse(data['drandPulse'].toString()),
    drandRandomness: data['drandRandomness'],
    iterations: BigInt.parse(data['iterations'].toString()),
  );
}

Future<List<int>?> pollVdfProofFromDesktop({
  required String desktopUrl,
  required String challengeHex,
}) async {
  final res = await http.get(Uri.parse('$desktopUrl/vdf/status/$challengeHex'));
  if (res.statusCode != 200) return null;
  final data = jsonDecode(res.body);
  if (data['status'] == 'completed') {
    return List<int>.from(data['proofBytes']);
  }
  return null;
}
