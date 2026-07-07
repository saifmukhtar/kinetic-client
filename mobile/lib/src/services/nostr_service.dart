import 'dart:convert';
import 'dart:async';
import 'package:bech32/bech32.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class NostrService {
  static const _relays = [
    'wss://relay.damus.io',
    'wss://nos.lol',
    'wss://relay.nostr.band',
    'wss://relay.snort.social',
    'wss://relay.primal.net',
    'wss://eden.nostr.land',
    'wss://relay.nostr.bg',
    'wss://nostr.fmt.wiz.biz',
    'wss://nostr.mom',
    'wss://nostr.oxtr.dev',
  ];

  static Future<Map<String, dynamic>?> fetchProfile(String pubkey) async {
    try {
      String hexPubkey = pubkey;
      if (pubkey.startsWith('npub1')) {
        hexPubkey = decodeNpub(pubkey);
      }

      final completer = Completer<Map<String, dynamic>?>();
      int failures = 0;
      List<WebSocketChannel> channels = [];

      final req = jsonEncode([
        'REQ',
        'kinetic_${DateTime.now().millisecondsSinceEpoch}',
        {
          'authors': [hexPubkey],
          'kinds': [0],
          'limit': 1,
        }
      ]);

      void closeAll() {
        for (var c in channels) {
          try { c.sink.close(); } catch (_) {}
        }
      }

      for (final relay in _relays) {
        try {
          final channel = WebSocketChannel.connect(Uri.parse(relay));
          channels.add(channel);
          channel.sink.add(req);

          channel.stream.listen((message) {
            try {
              final data = jsonDecode(message);
              if (data is List && data.isNotEmpty) {
                final type = data[0];
                if (type == 'EVENT' && data.length > 2) {
                  final event = data[2];
                  if (event['kind'] == 0) {
                    final content = event['content'] as String;
                    final profile = jsonDecode(content) as Map<String, dynamic>;
                    
                    // Sanitize image URLs (Edge Case 85 prevention)
                    if (profile.containsKey('picture')) {
                      profile['picture'] = _sanitizeImageUrl(profile['picture']);
                    }
                    if (profile.containsKey('banner')) {
                      profile['banner'] = _sanitizeImageUrl(profile['banner']);
                    }

                    if (!completer.isCompleted) {
                      completer.complete(profile);
                      closeAll();
                    }
                  }
                } else if (type == 'EOSE') {
                  failures++;
                  if (failures >= _relays.length && !completer.isCompleted) {
                    completer.complete(null);
                    closeAll();
                  }
                }
              }
            } catch (e) {
              // Ignore parse errors from single relay
            }
          }, onError: (e) {
            failures++;
            if (failures >= _relays.length && !completer.isCompleted) {
              completer.complete(null);
              closeAll();
            }
          }, onDone: () {
            failures++;
            if (failures >= _relays.length && !completer.isCompleted) {
              completer.complete(null);
              closeAll();
            }
          });
        } catch (_) {
          failures++;
        }
      }

      // Timeout after 4 seconds to keep it fast
      Future.delayed(const Duration(seconds: 4), () {
        if (!completer.isCompleted) {
          completer.complete(null);
          closeAll();
        }
      });

      return await completer.future;
    } catch (e) {
      return null;
    }
  }

  static String decodeNpub(String npub) {
    final codec = const Bech32Codec();
    final bech32 = codec.decode(npub);
    final data = _convertBits(bech32.data, 5, 8, false);
    return data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Future<bool> publishEvent(String eventJson) async {
    final eventMap = jsonDecode(eventJson);
    final req = jsonEncode(['EVENT', eventMap]);
    bool published = false;

    for (final relay in _relays) {
      try {
        final channel = WebSocketChannel.connect(Uri.parse(relay));
        channel.sink.add(req);
        // Wait briefly for OK or just assume sent
        Future.delayed(const Duration(milliseconds: 500), () => channel.sink.close());
        published = true;
      } catch (e) {
        // Ignored
      }
    }
    return published;
  }

  static Future<String?> discoverPublicMiner() async {
    final completer = Completer<String?>();
    List<WebSocketChannel> channels = [];
    int failures = 0;

    final req = jsonEncode([
      'REQ',
      'kinetic_discover_${DateTime.now().millisecondsSinceEpoch}',
      {
        'kinds': [1],
        '#t': ['kinetic-miner'],
        'limit': 5,
      }
    ]);

    void closeAll() {
      for (var c in channels) {
        try { c.sink.close(); } catch (_) {}
      }
    }

    for (final relay in _relays) {
      try {
        final channel = WebSocketChannel.connect(Uri.parse(relay));
        channels.add(channel);
        channel.sink.add(req);

        channel.stream.listen((message) {
          try {
            final data = jsonDecode(message);
            if (data is List && data.isNotEmpty) {
              final type = data[0];
              if (type == 'EVENT' && data.length > 2) {
                final event = data[2];
                if (event['kind'] == 1) {
                  final pubkeyHex = event['pubkey'];
                  if (!completer.isCompleted) {
                    completer.complete(pubkeyHex);
                    closeAll();
                  }
                }
              } else if (type == 'EOSE') {
                failures++;
                if (failures >= _relays.length && !completer.isCompleted) {
                  completer.complete(null);
                  closeAll();
                }
              }
            }
          } catch (_) {}
        }, onError: (_) {
          failures++;
          if (failures >= _relays.length && !completer.isCompleted) {
            completer.complete(null);
            closeAll();
          }
        }, onDone: () {
          failures++;
          if (failures >= _relays.length && !completer.isCompleted) {
            completer.complete(null);
            closeAll();
          }
        });
      } catch (_) {
        failures++;
      }
    }

    Future.delayed(const Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        completer.complete(null);
        closeAll();
      }
    });

    return await completer.future;
  }

  static Future<String?> listenForDm(
    String senderNpub,
    String recipientHex, {
    int maxAttempts = 10,
  }) async {
    String senderHex = senderNpub;
    if (senderNpub.startsWith('npub1')) {
      senderHex = decodeNpub(senderNpub);
    }

    int retryDelaySeconds = 5;
    int attempt = 0;

    while (attempt < maxAttempts) {
      attempt++;
      final req = jsonEncode([
        'REQ',
        'kinetic_vdf_${DateTime.now().millisecondsSinceEpoch}',
        {
          'authors': [senderHex],
          'kinds': [4],
          '#p': [recipientHex],
          'limit': 1,
        }
      ]);

      final completer = Completer<String?>();
      List<WebSocketChannel> channels = [];

      void closeAll() {
        for (var c in channels) {
          try { c.sink.close(); } catch (_) {}
        }
      }

      for (final relay in _relays) {
        try {
          final channel = WebSocketChannel.connect(Uri.parse(relay));
          channels.add(channel);
          channel.sink.add(req);

          channel.stream.listen((message) {
            try {
              final data = jsonDecode(message);
              if (data is List && data.isNotEmpty && data[0] == 'EVENT') {
                final event = data[2];
                if (event['kind'] == 4) {
                  if (!completer.isCompleted) {
                    completer.complete(event['content']);
                  }
                }
              }
            } catch (_) {}
          }, onError: (_) {}, onDone: () {});
        } catch (_) {}
      }

      final result = await Future.any([
        completer.future,
        Future.delayed(const Duration(seconds: 30), () => null)
      ]);

      closeAll();

      if (result != null) return result;

      // Give up after maxAttempts — prevents unbounded battery drain if the
      // desktop node never responds.
      if (attempt >= maxAttempts) break;

      // Exponential backoff to prevent relay rate-limit bans.
      await Future.delayed(Duration(seconds: retryDelaySeconds));
      retryDelaySeconds = (retryDelaySeconds * 2).clamp(5, 60);
    }

    return null; // Desktop node did not respond within the retry window.
  }

  static List<int> _convertBits(List<int> data, int fromBits, int toBits, bool pad) {
    var acc = 0;
    var bits = 0;
    final ret = <int>[];
    final maxv = (1 << toBits) - 1;

    for (var value in data) {
      if (value < 0 || (value >> fromBits) != 0) {
        throw Exception('Invalid value: $value');
      }
      acc = (acc << fromBits) | value;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        ret.add((acc >> bits) & maxv);
      }
    }

    if (pad) {
      if (bits > 0) {
        ret.add((acc << (toBits - bits)) & maxv);
      }
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      throw Exception('Invalid padding');
    }

    return ret;
  }

  static String? _sanitizeImageUrl(dynamic url) {
    if (url is! String) return null;
    if (!url.startsWith('https://') && !url.startsWith('http://')) return null;
    
    try {
      final uri = Uri.parse(url);
      final path = uri.path.toLowerCase();
      // Must end in a standard image extension to prevent endless streams/1GB payloads
      if (path.endsWith('.png') || path.endsWith('.jpg') || path.endsWith('.jpeg') || 
          path.endsWith('.gif') || path.endsWith('.webp')) {
        return url;
      }
    } catch (_) {}
    return null;
  }
}
