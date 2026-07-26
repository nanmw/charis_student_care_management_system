import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/core/utils/file_export_utils.dart';

void main() {
  group('FileExportUtils.userFacingSaveError', () {
    test('maps file-in-use / errno 32 to close-file guidance', () {
      final message = FileExportUtils.userFacingSaveError(
        Exception(
          "PathAccessException: Cannot open file, path = 'C:\\x.pdf' "
          '(OS Error: The process cannot access the file because it is being '
          'used by another process, errno = 32)',
        ),
        itemLabel: 'report',
      );
      expect(message, contains('Couldn’t save the report'));
      expect(message, contains('open in another program'));
      expect(message, contains('Close the PDF or Excel'));
      expect(message, contains('different filename'));
    });

    test('maps permission errors to folder guidance', () {
      final message = FileExportUtils.userFacingSaveError(
        Exception('PathAccessException: Access is denied, errno = 5'),
        itemLabel: 'report',
      );
      expect(message, contains('permission'));
      expect(message, contains('Downloads'));
    });

    test('maps unknown PathAccessException to access guidance', () {
      final message = FileExportUtils.userFacingSaveError(
        Exception('PathAccessException: Cannot open file'),
      );
      expect(message, contains('could not be accessed'));
      expect(message, contains('different filename'));
    });

    test('falls back to generic save guidance', () {
      final message = FileExportUtils.userFacingSaveError(Exception('boom'));
      expect(message, contains('Couldn’t save the file'));
      expect(message, contains('try again'));
    });

    test('uses custom itemLabel', () {
      final message = FileExportUtils.userFacingSaveError(
        Exception('boom'),
        itemLabel: 'template',
      );
      expect(message, contains('Couldn’t save the template'));
    });
  });
}
