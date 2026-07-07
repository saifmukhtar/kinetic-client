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
import 'package:kinetic/src/utils/error_handler.dart';
import 'package:http/http.dart' as http;

enum RegistrationErrorKind { attestation, request, vdf, network, unknown }

class RegistrationError {
  final RegistrationErrorKind kind;
  final String message;
  const RegistrationError(this.kind, this.message);
}

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
  final RegistrationStatus? failedStep;
  final RegistrationError? error;
  final String? desktopUrl;

  // For polling VDF
  final String? challengeHex;

  const RegistrationState({
    this.status = RegistrationStatus.idle,
    this.failedStep,
    this.error,
    this.desktopUrl,
    this.challengeHex,
  });

  RegistrationState copyWith({
    RegistrationStatus? status,
    RegistrationStatus? failedStep,
    RegistrationError? error,
    String? desktopUrl,
    String? challengeHex,
    bool clearError = false,
  }) {
    return RegistrationState(
      status: status ?? this.status,
      failedStep: clearError ? null : (failedStep ?? this.failedStep),
      error: clearError ? null : (error ?? this.error),
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
        final salt = Uint8List.fromList(
          saltStr.split(',').map(int.parse).toList(),
        );
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

        if (desktopUrl.startsWith('npub') ||
            (desktopUrl.length == 64 && !desktopUrl.contains(':'))) {
          _waitForNostrDm(desktopUrl, name, privateKeyBytes, jobResponse);
        } else {
          _startPolling(desktopUrl, name, privateKeyBytes, jobResponse);
        }
      } catch (e) {
        prefs.remove('pending_vdf');
      }
    }
  }

  Future<void> _savePendingVdf(
    String desktopUrl,
    String name,
    VdfJobResponse jobResponse,
  ) async {
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

  Future<void> _waitForNostrDm(
    String desktopUrl,
    String name,
    List<int> privateKeyBytes,
    VdfJobResponse vdfJobResponse,
  ) async {
    String desktopHex = desktopUrl;
    if (desktopUrl.startsWith('npub1')) {
      desktopHex = NostrService.decodeNpub(desktopUrl);
    }
    final encryptedReply = await NostrService.listenForDm(
      desktopUrl,
      desktopHex,
    );

    if (encryptedReply != null) {
      final proofBytes = await decryptVdfProofNostr(
        desktopNpub: desktopUrl,
        privateKeyBytes: privateKeyBytes,
        encryptedContent: encryptedReply,
      );

      await _broadcastReveal(name, privateKeyBytes, vdfJobResponse, proofBytes);
    } else {
      state = state.copyWith(
        status: RegistrationStatus.error,
        failedStep: RegistrationStatus.pollingVdf,
        error: const RegistrationError(
          RegistrationErrorKind.vdf,
          "Failed to receive VDF proof from node",
        ),
      );
    }
  }

  Future<void> startRegistration(String name) async {
    final desktopUrl = state.desktopUrl ?? 'auto';

    // 1. Hardware Attestation
    state = state.copyWith(status: RegistrationStatus.attesting);
    final trustTier = await HardwareAttestationService.verifyDevice();

    // Only block rooted devices from using the 'auto' matchmaking pool
    final isAutoMatchmaking = desktopUrl == 'auto';

    if (trustTier == TrustTier.untrusted) {
      if (isAutoMatchmaking) {
        state = state.copyWith(
          status: RegistrationStatus.error,
          failedStep: RegistrationStatus.attesting,
          error: const RegistrationError(
            RegistrationErrorKind.attestation,
            "Rooted devices cannot use public matchmaking. Please specify a manual Node Address or Npub.",
          ),
        );
        return;
      }
      // If they manually specified an npub or local HTTP node, allow them to proceed!
    }

    // 1.5 Check name limit (Max 3 for all trusted devices)
    final prefs = await SharedPreferences.getInstance();
    final namesList = prefs.getStringList('delegated_names') ?? [];
    if (namesList.length >= 3 && !namesList.contains(name)) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        failedStep: RegistrationStatus.attesting,
        error: const RegistrationError(
          RegistrationErrorKind.attestation,
          "Maximum limit of 3 names reached for this device.",
        ),
      );
      return;
    }

    try {
      // Generate a secure random Ed25519 private key scalar for this specific domain
      final random = dart_math.Random.secure();
      final privateKeyBytes = List.generate(32, (_) => random.nextInt(256));

      String targetNode = desktopUrl;

      if (desktopUrl == 'auto') {
        state = state.copyWith(status: RegistrationStatus.requestingVdf);
        final discoveredHex = await NostrService.discoverPublicMiner();
        if (discoveredHex == null) {
          state = state.copyWith(
            status: RegistrationStatus.error,
            failedStep: RegistrationStatus.requestingVdf,
            error: const RegistrationError(
              RegistrationErrorKind.request,
              "Could not discover any public miners on the network.",
            ),
          );
          return;
        }
        targetNode = discoveredHex;
      }

      if (targetNode.startsWith('npub') ||
          (targetNode.length == 64 && !targetNode.contains(':'))) {
        // --- NOSTR FLOW ---
        state = state.copyWith(status: RegistrationStatus.requestingVdf);
        final result = await prepareVdfRequestNostr(
          desktopNpub: targetNode,
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
        await secureStorage.write(
          key: 'private_key_$name',
          value: privateKeyBytes.join(','),
        );
        await _savePendingVdf(targetNode, name, vdfJobResponse);

        _waitForNostrDm(targetNode, name, privateKeyBytes, vdfJobResponse);
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
        await secureStorage.write(
          key: 'private_key_$name',
          value: privateKeyBytes.join(','),
        );
        await _savePendingVdf(desktopUrl, name, vdfJobResponse);

        _startPolling(desktopUrl, name, privateKeyBytes, vdfJobResponse);
      }
    } catch (e) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        failedStep: RegistrationStatus.requestingVdf,
        error: RegistrationError(
          RegistrationErrorKind.request,
          parseKineticError(e),
        ),
      );
    }
  }

  void _startPolling(
    String desktopUrl,
    String name,
    List<int> privateKeyBytes,
    VdfJobResponse jobResponse,
  ) {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      try {
        final proofBytes = await pollVdfProofFromDesktop(
          desktopUrl: desktopUrl,
          challengeHex: jobResponse.challengeHex,
        );

        if (proofBytes != null) {
          timer.cancel();
          await _broadcastReveal(
            name,
            privateKeyBytes,
            jobResponse,
            proofBytes,
          );
        }
      } catch (e) {
        // Ignore polling errors
      }
    });
  }

  Future<void> _broadcastReveal(
    String name,
    List<int> privateKeyBytes,
    VdfJobResponse jobResponse,
    List<int> proofBytes,
  ) async {
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
        state = state.copyWith(
          status: RegistrationStatus.error,
          failedStep: RegistrationStatus.broadcasting,
          error: const RegistrationError(
            RegistrationErrorKind.network,
            "Failed to broadcast reveal to DHT.",
          ),
        );
      }
    } catch (e) {
      state = state.copyWith(
        status: RegistrationStatus.error,
        failedStep: RegistrationStatus.broadcasting,
        error: RegistrationError(
          RegistrationErrorKind.network,
          parseKineticError(e),
        ),
      );
    }
  }

  void reset() {
    _pollingTimer?.cancel();
    state = const RegistrationState();
  }
}

final registrationProvider =
    NotifierProvider<RegistrationNotifier, RegistrationState>(() {
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
  final pubkeyBytes = derivePublicKeyBytesSync(
    privateKeyBytes: privateKeyBytes,
  );
  final pubkeyHex = pubkeyBytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  final res = await http.post(
    Uri.parse('$desktopUrl/vdf/request'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'name': name,
      'difficulty': difficultyBits,
      'pubkey': pubkeyHex,
    }),
  );
  if (res.statusCode != 200) {
    throw Exception("HTTP VDF Request Failed: ${res.statusCode} ${res.body}");
  }
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
