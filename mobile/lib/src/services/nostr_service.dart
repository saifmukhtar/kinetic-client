import 'dart:convert';
import 'dart:async';
import 'package:bech32/bech32.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class NostrService {
  static const _relay = 'wss://relay.damus.io';

  static Future<Map<String, dynamic>?> fetchProfile(String pubkey) async {
    try {
      String hexPubkey = pubkey;
      if (pubkey.startsWith('npub1')) {
        hexPubkey = decodeNpub(pubkey);
      }

      final channel = WebSocketChannel.connect(Uri.parse(_relay));
      final subId = 'kinetic_${DateTime.now().millisecondsSinceEpoch}';

      final req = jsonEncode([
        'REQ',
        subId,
        {
          'authors': [hexPubkey],
          'kinds': [0],
          'limit': 1,
        }
      ]);

      channel.sink.add(req);

      final completer = Completer<Map<String, dynamic>?>();

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
                if (!completer.isCompleted) {
                  completer.complete(profile);
                }
              }
            } else if (type == 'EOSE') {
              if (!completer.isCompleted) {
                completer.complete(null);
              }
            }
          }
        } catch (e) {
          print('Error parsing Nostr event: $e');
        }
      }, onError: (e) {
        if (!completer.isCompleted) completer.complete(null);
      }, onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      });

      // Timeout after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      });

      final result = await completer.future;
      channel.sink.close();
      return result;
    } catch (e) {
      print('Nostr fetch error: $e');
      return null;
    }
  }

  static String decodeNpub(String npub) {
    final codec = const Bech32Codec();
    final bech32 = codec.decode(npub);
    final data = _convertBits(bech32.data, 5, 8, false);
    return data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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
}
