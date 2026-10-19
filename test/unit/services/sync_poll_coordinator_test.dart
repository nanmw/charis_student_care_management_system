import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/data/services/sync_poll_coordinator.dart';

void main() {
  group('SyncPollCoordinator', () {
    test('does not poll without a connection string', () async {
      var calls = 0;
      final coordinator = SyncPollCoordinator(
        onSyncRequested: () async {
          calls++;
        },
        interval: const Duration(milliseconds: 20),
      );

      coordinator.configure(connectionString: null, enabled: true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      coordinator.dispose();

      expect(calls, 0);
      expect(coordinator.isPolling, isFalse);
    });

    test('polls while enabled and a connection string is set', () async {
      var calls = 0;
      final coordinator = SyncPollCoordinator(
        onSyncRequested: () async {
          calls++;
        },
        interval: const Duration(milliseconds: 20),
      );

      coordinator.configure(
        connectionString: 'postgresql://user:secret@example.neon.tech/neondb',
        enabled: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 70));
      coordinator.dispose();

      expect(calls, greaterThanOrEqualTo(1));
      expect(coordinator.isPolling, isFalse);
    });
  });
}
