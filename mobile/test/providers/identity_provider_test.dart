import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/src/providers/identity_provider.dart';

void main() {
  group('IdentityState Tests', () {
    test('default state is empty', () {
      const state = IdentityState();
      expect(state.isResolving, false);
      expect(state.url, isNull);
      expect(state.data, isNull);
      expect(state.error, isNull);
    });

    test('copyWith updates fields', () {
      const state = IdentityState();
      final updated = state.copyWith(
        isResolving: true,
        url: 'test.kin',
        data: {'key': 'value'},
        error: const IdentityError(IdentityErrorKind.notFound, 'not found'),
      );

      expect(updated.isResolving, true);
      expect(updated.url, 'test.kin');
      expect(updated.data, {'key': 'value'});
      expect(updated.error?.message, 'not found');
      expect(updated.error?.kind, IdentityErrorKind.notFound);
    });

    test('copyWith clearError flag works', () {
      const state = IdentityState(
        error: IdentityError(IdentityErrorKind.network, 'network error'),
      );

      final cleared = state.copyWith(isResolving: true, clearError: true);

      expect(cleared.isResolving, true);
      expect(cleared.error, isNull);
    });
  });
}
