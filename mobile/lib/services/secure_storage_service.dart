import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Service to handle edge cases around Android Keystore wiping and iOS Keychain desyncs
/// Edge Case: Local Storage Wipe (156)
class SecureStorageService {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );

  static Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException catch (e) {
      debugPrint(
        'Secure Storage PlatformException (Possible Storage Wipe/Keystore Desync): $e',
      );
      // If the keystore gets corrupted or the app data is wiped but keystore remains,
      // it throws a bad padding/MAC exception. We must clear storage to recover.
      await _storage.deleteAll();
      return null;
    } catch (e) {
      debugPrint('Secure Storage Error: $e');
      return null;
    }
  }

  static Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException catch (e) {
      debugPrint('Secure Storage PlatformException on write: $e');
      await _storage.deleteAll();
      await _storage.write(key: key, value: value);
    } catch (e) {
      debugPrint('Secure Storage Error: $e');
    }
  }

  static Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e) {
      debugPrint('Secure Storage Error on delete: $e');
    }
  }
}
