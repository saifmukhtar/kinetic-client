import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kinetic/services/secure_storage_service.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('SecureStorageService Tests', () {
    test('write and read value', () async {
      await SecureStorageService.write('test_key', 'test_value');
      final value = await SecureStorageService.read('test_key');
      expect(value, 'test_value');
    });

    test('read non-existent value returns null', () async {
      final value = await SecureStorageService.read('missing_key');
      expect(value, isNull);
    });

    test('delete value', () async {
      await SecureStorageService.write('test_key', 'test_value');
      await SecureStorageService.delete('test_key');
      final value = await SecureStorageService.read('test_key');
      expect(value, isNull);
    });

    test('update value', () async {
      await SecureStorageService.write('test_key', 'old_value');
      await SecureStorageService.write('test_key', 'new_value');
      final value = await SecureStorageService.read('test_key');
      expect(value, 'new_value');
    });
  });
}
