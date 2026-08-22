import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/core/utils/io_retry.dart';

void main() {
  group('isTransientIoError', () {
    test('detects sharing / lock messages', () {
      expect(
        isTransientIoError(
          const FileSystemException(
            'Cannot open file',
            'x',
            OSError(
              'The process cannot access the file because it is being used by another process.',
              32,
            ),
          ),
        ),
        isTrue,
      );
      expect(isTransientIoError(Exception('sharing violation')), isTrue);
      expect(isTransientIoError(Exception('PathAccessException: locked')), isTrue);
    });

    test('rejects path-not-found', () {
      expect(
        isTransientIoError(Exception('FileSystemException: no such file')),
        isFalse,
      );
      expect(isTransientIoError(Exception('path not found errno = 2')), isFalse);
    });
  });

  group('userFacingSyncError', () {
    test('maps transient lock to file-busy guidance', () {
      final msg = userFacingSyncError(Exception('sharing violation'));
      expect(msg, contains('file busy'));
    });

    test('maps timeout', () {
      final msg = userFacingSyncError(
        TimeoutException('Export timed out after 60s'),
      );
      expect(msg.toLowerCase(), contains('timed out'));
    });
  });

  group('retryOnTransientIo', () {
    test('succeeds after transient failures', () async {
      var attempts = 0;
      final result = await retryOnTransientIo(
        () async {
          attempts++;
          if (attempts < 3) {
            throw Exception('sharing violation');
          }
          return 'ok';
        },
        maxAttempts: 5,
        delayForAttempt: (_) => Duration.zero,
      );
      expect(result, 'ok');
      expect(attempts, 3);
    });

    test('rethrows non-transient immediately', () async {
      var attempts = 0;
      await expectLater(
        () => retryOnTransientIo(
          () async {
            attempts++;
            throw Exception('something else entirely');
          },
          maxAttempts: 5,
          delayForAttempt: (_) => Duration.zero,
        ),
        throwsA(isA<Exception>()),
      );
      expect(attempts, 1);
    });

    test('rethrows after max attempts', () async {
      var attempts = 0;
      await expectLater(
        () => retryOnTransientIo(
          () async {
            attempts++;
            throw Exception('file is locked');
          },
          maxAttempts: 3,
          delayForAttempt: (_) => Duration.zero,
        ),
        throwsA(isA<Exception>()),
      );
      expect(attempts, 3);
    });
  });
}
