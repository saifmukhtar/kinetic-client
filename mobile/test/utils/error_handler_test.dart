import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/src/rust/api/error.dart';
import 'package:kinetic/src/utils/error_handler.dart';

void main() {
  group('parseKineticError Tests', () {
    test('parses ResolverError', () {
      final notInitialized = parseKineticError(const ResolverError.notInitialized());
      expect(notInitialized, "Not initialized: call init_light_client() first");

      final notFound = parseKineticError(const ResolverError.notFound("test.kin"));
      expect(notFound, "Name 'test.kin' was not found in the Kinetic network. It may be unregistered.");

      final invalidUrl = parseKineticError(const ResolverError.invalidUrl("invalid"));
      expect(invalidUrl, "Invalid URL format: invalid");
    });

    test('parses DelegationError', () {
      final invalidKey = parseKineticError(const DelegationError.invalidPrivateKey());
      expect(invalidKey, "Private key must be exactly 32 bytes");

      final tooShort = parseKineticError(const DelegationError.nameTooShort());
      expect(tooShort, "Name must be at least 8 characters long");
      
      final drandFailed = parseKineticError(const DelegationError.drandFetchFailed());
      expect(drandFailed, "Failed to fetch drand randomness from all endpoints");
    });

    test('parses DaemonError', () {
      final alreadyInit = parseKineticError(const DaemonError.alreadyInitialized());
      expect(alreadyInit, "Network client already initialized");

      final invalidAppDir = parseKineticError(const DaemonError.invalidAppDirectory());
      expect(invalidAppDir, "Invalid app directory provided");
    });

    test('parses IdentityError', () {
      final notFound = parseKineticError(const IdentityError.notFound("identity"));
      expect(notFound, "Identity 'identity' was not found in the Kinetic network.");
      
      final internal = parseKineticError(const IdentityError.internal("something went wrong"));
      expect(internal, "Internal error: something went wrong");
    });

    test('parses generic string exception', () {
      final genericStr = parseKineticError("Just a string error");
      expect(genericStr, "Just a string error");

      final exc = Exception("Test Exception");
      final parsedExc = parseKineticError(exc);
      expect(parsedExc, "Test Exception");
    });
  });
}
