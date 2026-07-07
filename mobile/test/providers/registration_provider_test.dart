import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/src/providers/registration_provider.dart';

void main() {
  group('RegistrationState Tests', () {
    test('default state is idle', () {
      const state = RegistrationState();
      expect(state.status, RegistrationStatus.idle);
      expect(state.failedStep, isNull);
      expect(state.error, isNull);
      expect(state.desktopUrl, isNull);
      expect(state.challengeHex, isNull);
    });

    test('copyWith updates fields', () {
      const state = RegistrationState();
      final updated = state.copyWith(
        status: RegistrationStatus.requestingVdf,
        failedStep: RegistrationStatus.attesting,
        error: const RegistrationError(
          RegistrationErrorKind.attestation,
          'test error',
        ),
        desktopUrl: 'npub1test',
        challengeHex: '0x123',
      );

      expect(updated.status, RegistrationStatus.requestingVdf);
      expect(updated.failedStep, RegistrationStatus.attesting);
      expect(updated.error?.message, 'test error');
      expect(updated.desktopUrl, 'npub1test');
      expect(updated.challengeHex, '0x123');
    });

    test('copyWith clearError flag works', () {
      const state = RegistrationState(
        status: RegistrationStatus.error,
        failedStep: RegistrationStatus.requestingVdf,
        error: RegistrationError(
          RegistrationErrorKind.network,
          'network error',
        ),
      );

      final cleared = state.copyWith(
        status: RegistrationStatus.pollingVdf,
        clearError: true,
      );

      expect(cleared.status, RegistrationStatus.pollingVdf);
      expect(cleared.failedStep, isNull);
      expect(cleared.error, isNull);
    });
  });
}
