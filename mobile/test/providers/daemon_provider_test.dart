import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/src/providers/daemon_provider.dart';

void main() {
  group('DaemonState Tests', () {
    test('default state is stopped', () {
      const state = DaemonState();
      expect(state.status, DaemonStatus.stopped);
      expect(state.errorMessage, isNull);
      expect(state.isRooted, false);
    });

    test('copyWith updates fields', () {
      const state = DaemonState();
      final updated = state.copyWith(
        status: DaemonStatus.running,
        errorMessage: 'error',
        isRooted: true,
      );
      
      expect(updated.status, DaemonStatus.running);
      expect(updated.errorMessage, 'error');
      expect(updated.isRooted, true);
    });
    
    test('copyWith keeps old fields if not provided', () {
      const state = DaemonState(
        status: DaemonStatus.error,
        errorMessage: 'old error',
        isRooted: true,
      );
      
      final updated = state.copyWith(status: DaemonStatus.running);
      
      expect(updated.status, DaemonStatus.running);
      expect(updated.errorMessage, 'old error');
      expect(updated.isRooted, true);
    });
  });
}
