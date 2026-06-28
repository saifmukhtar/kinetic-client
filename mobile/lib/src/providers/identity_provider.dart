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
    // Ensure the daemon is running before making a request
    final daemonStatus = ref.read(daemonProvider).status;
    if (daemonStatus != DaemonStatus.running) {
      await ref.read(daemonProvider.notifier).startDaemon();
    }

    state = state.copyWith(isResolving: true, url: url, error: null);

    try {
      final doc = await lookupIdentity(kinUrl: url);
      final Map<String, dynamic> decoded = jsonDecode(doc.rawJson);
      
      // Check for Nostr integration
      if (decoded.containsKey('profile')) {
        final profile = decoded['profile'] as Map<String, dynamic>;
        if (profile.containsKey('nostr')) {
          final nostrKey = profile['nostr'] as String;
          try {
            final nostrData = await NostrService.fetchProfile(nostrKey);
            if (nostrData != null) {
              // Merge nostr data into profile without overwriting existing explicit TXT records
              nostrData.forEach((key, value) {
                if (!profile.containsKey(key)) {
                  profile[key] = value;
                }
              });
              decoded['profile'] = profile;
            }
          } catch (e) {
            print('Nostr fetch failed: $e');
          }
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
