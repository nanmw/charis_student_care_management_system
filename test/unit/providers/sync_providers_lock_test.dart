import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

// Mirrors [_ChangeSetSyncLock] in sync_providers.dart for unit testing.
class _TestChangeSetSyncLock {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      }
    });
    return completer.future;
  }
}

void main() {
  group('_ChangeSetSyncLock', () {
    test('runs concurrent callers sequentially', () async {
      final lock = _TestChangeSetSyncLock();
      final order = <int>[];

      final first = lock.run(() async {
        order.add(1);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        order.add(2);
        return 1;
      });

      final second = lock.run(() async {
        order.add(3);
        return 2;
      });

      expect(await first, 1);
      expect(await second, 2);
      expect(order, [1, 2, 3]);
    });
  });
}
