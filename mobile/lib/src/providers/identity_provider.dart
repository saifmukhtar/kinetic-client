import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinetic/src/services/nostr_service.dart';
import 'package:kinetic/src/rust/api/resolver.dart';
import 'package:kinetic/src/providers/daemon_provider.dart';
import 'package:kinetic/src/utils/error_handler.dart';

enum IdentityErrorKind { network, notFound, offline, unknown }

class IdentityError {
  final IdentityErrorKind kind;
  final String message;

  const IdentityError(this.kind, this.message);
}

class IdentityState {
  final bool isResolving;
  final String? url;
  final Map<String, dynamic>? data;
  final IdentityError? error;

  const IdentityState({
    this.isResolving = false,
    this.url,
    this.data,
    this.error,
  });

  IdentityState copyWith({
    bool? isResolving,
    String? url,
    Map<String, dynamic>? data,
    IdentityError? error,
    bool clearError = false,
  }) {
    return IdentityState(
      isResolving: isResolving ?? this.isResolving,
      url: url ?? this.url,
      data: data ?? this.data,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class IdentityNotifier extends Notifier<IdentityState> {
  @override
  IdentityState build() {
    return const IdentityState();
  }

  Future<void> resolveDomain(String url) async {
    state = state.copyWith(isResolving: true, url: url, clearError: true);

    try {
      if (url.startsWith('npub1')) {
        state = state.copyWith(
          isResolving: false,
          error: const IdentityError(
            IdentityErrorKind.unknown,
            'Direct Nostr pubkey lookups are disabled for privacy and connection stability (Edge Cases 79 & 80).',
          ),
        );
        return;
      }

      // Ensure the daemon is running before making a request
      final daemonStatus = ref.read(daemonProvider).status;
      if (daemonStatus != DaemonStatus.running) {
        await ref.read(daemonProvider.notifier).startDaemon();
      }

      // Edge Case 94: Add a 45-second timeout to prevent permanent UI hangs.
      // Kademlia may attempt to dial unroutable private IPs broadcasted by cloud nodes,
      // which take ~10s each to timeout. 45s gives the DHT enough time to recover.
      final doc = await lookupIdentity(kinUrl: url).timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw Exception(
          'Resolution timed out. The network may be partitioned or the peer is offline.',
        ),
      );
      final Map<String, dynamic> decoded = jsonDecode(doc.rawJson);

      // Edge Case 97: Sanitize untrusted peer payload to prevent spoofing
      decoded['status'] =
          'Verified'; // Kademlia signature was already verified by Rust
      decoded.remove('resolution');
      decoded.remove('status_note');

      // Check for Nostr integration
      if (decoded.containsKey('profile')) {
        final profile = decoded['profile'] as Map<String, dynamic>;
        if (profile.containsKey('nostr')) {
          // Since this is an explicit manual lookup from the Identity Lookup sheet
          // and not an automatic search-bar autocomplete, it is safe to query relays.
          final nostrKey = profile['nostr'] as String;
          final nostrProfile = await NostrService.fetchProfile(nostrKey);
          if (nostrProfile != null) {
            profile.addAll(nostrProfile);
          }
        }
      }

      state = state.copyWith(isResolving: false, data: decoded);
    } catch (e) {
      final cleanMsg = parseKineticError(e);
      IdentityErrorKind kind = IdentityErrorKind.unknown;

      if (cleanMsg.contains('not found')) {
        kind = IdentityErrorKind.notFound;
      } else if (cleanMsg.contains('offline') ||
          cleanMsg.contains('timed out') ||
          cleanMsg.contains('partitioned')) {
        kind = IdentityErrorKind.offline;
      } else if (cleanMsg.contains('DHT lookup failed')) {
        kind = IdentityErrorKind.network;
      }

      state = state.copyWith(
        isResolving: false,
        error: IdentityError(kind, cleanMsg),
      );
    }
  }

  void clear() {
    state = const IdentityState();
  }
}

final identityProvider = NotifierProvider<IdentityNotifier, IdentityState>(() {
  return IdentityNotifier();
});
