import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kinetic/src/services/nostr_service.dart';
import 'package:kinetic/src/rust/api/resolver.dart';
import 'package:kinetic/src/providers/daemon_provider.dart';

class IdentityState {
  final bool isResolving;
  final String? url;
  final Map<String, dynamic>? data;
  final String? error;

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
    String? error,
  }) {
    return IdentityState(
      isResolving: isResolving ?? this.isResolving,
      url: url ?? this.url,
      data: data ?? this.data,
      error: error, // Can be null to clear errors
    );
  }
}

class IdentityNotifier extends Notifier<IdentityState> {
  @override
  IdentityState build() {
    return const IdentityState();
  }

  Future<void> resolveDomain(String url) async {
    state = state.copyWith(isResolving: true, url: url, error: null);

    try {
      if (url.startsWith('npub1')) {
        state = state.copyWith(isResolving: false, error: 'Direct Nostr pubkey lookups are disabled for privacy and connection stability (Edge Cases 79 & 80).');
        return;
      }

      // Ensure the daemon is running before making a request
      final daemonStatus = ref.read(daemonProvider).status;
      if (daemonStatus != DaemonStatus.running) {
        await ref.read(daemonProvider.notifier).startDaemon();
      }

      // Edge Case 94: Add a 15-second timeout to prevent permanent UI hangs
      final doc = await lookupIdentity(kinUrl: url).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('Resolution timed out. The network may be partitioned or the peer is offline.'),
      );
      final Map<String, dynamic> decoded = jsonDecode(doc.rawJson);
      
      // Edge Case 97: Sanitize untrusted peer payload to prevent spoofing
      decoded['status'] = 'Verified'; // Kademlia signature was already verified by Rust
      decoded.remove('resolution');
      decoded.remove('status_note');
      
      // Check for Nostr integration
      if (decoded.containsKey('profile')) {
        final profile = decoded['profile'] as Map<String, dynamic>;
        if (profile.containsKey('nostr')) {
          // Privacy protection (Edge Case #79): We no longer automatically broadcast this pubkey
          // to public Web2 Nostr relays (Damus, Nos.lol) via plaintext WebSockets, as that 
          // de-anonymizes the user's browsing activity. The key is simply displayed.
        }
      }

      state = state.copyWith(isResolving: false, data: decoded);
    } catch (e) {
      state = state.copyWith(isResolving: false, error: e.toString());
    }
  }

  void clear() {
    state = const IdentityState();
  }
}

final identityProvider = NotifierProvider<IdentityNotifier, IdentityState>(() {
  return IdentityNotifier();
});
