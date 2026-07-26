import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/data/services/student_import_service.dart';

void main() {
  group('StudentImportService', () {
    test('maps numFmtId decode exception to actionable parse error', () {
      final service = StudentImportService(
        decoder: (_) => throw Exception(
          'custom numFmtId starts at 164 but found a value of 42',
        ),
      );

      expect(
        () => service.parseWorkbook(Uint8List(0)),
        throwsA(
          isA<StudentImportException>()
              .having((e) => e.type, 'type', StudentImportFailureType.fileParse)
              .having(
                (e) => e.message,
                'message',
                contains('unsupported Excel number format'),
              ),
        ),
      );
    });

    test('throws header validation when required columns are missing', () {
      final bytes = _buildWorkbookBytes(
        headers: const ['name', 'className'],
        rows: const [
          ['John Doe', 'Year 1'],
        ],
      );
      const service = StudentImportService();

      expect(
        () => service.parseWorkbook(bytes),
        throwsA(
          isA<StudentImportException>()
              .having(
                (e) => e.type,
                'type',
                StudentImportFailureType.headerValidation,
              )
              .having(
                (e) => e.message,
                'message',
                contains('surname'),
              ),
        ),
      );
    });

    test('normalizes row values and keeps row-level validation issues', () {
      final bytes = _buildWorkbookBytes(
        headers: const [
          'surname',
          'firstName',
          'status',
          'className',
          'mode',
          'admission_year',
          'contact',
          'email',
          'handbook',
          'mediaRelease',
          'accidentWaiver',
          'academicSession',
        ],
        rows: const [
          [
            'Doe',
            'John',
            'withdrawn',
            'Year 1',
            'Full-time',
            '2024',
            '0123',
            'john@example.com',
            'yes',
            '0',
            'true',
            '2026',
          ],
          ['', 'MissingSurname'],
        ],
      );
      const service = StudentImportService();

      final result = service.parseWorkbook(bytes);
      expect(result.rows, hasLength(1));
      expect(result.issues, hasLength(1));
      expect(result.detailedIssues, isNotEmpty);
      expect(result.issues.first, contains('missing surname or firstName'));

      final row = result.rows.single;
      expect(row.rowNumber, 2);
      expect(row.surname, 'Doe');
      expect(row.firstName, 'John');
      expect(row.status, 'Withdrawn');
      expect(row.className, 'Year 1');
      expect(row.handbook, isTrue);
      expect(row.mediaRelease, isFalse);
      expect(row.accidentWaiver, isTrue);
      expect(row.sessionCode, '2026');
    });

    test('normalizes numeric-like session and year values', () {
      final bytes = _buildWorkbookBytes(
        headers: const [
          'surname',
          'firstName',
          'admissionYear',
          'academicSession',
        ],
        rows: const [
          ['Doe', 'Jane', '2026.0', '2027.0'],
        ],
      );
      const service = StudentImportService();

      final result = service.parseWorkbook(bytes);
      expect(result.rows, hasLength(1));
      final row = result.rows.single;
      expect(row.admissionYear, '2026');
      expect(row.sessionCode, '2027');
    });

    test('unknown status and bool produce issues and safe defaults', () {
      final bytes = _buildWorkbookBytes(
        headers: const [
          'surname',
          'firstName',
          'status',
          'mode',
          'handbook',
          'mediaRelease',
          'accidentWaiver',
        ],
        rows: const [
          [
            'Doe',
            'John',
            'alumni',
            'Part-time',
            'maybe',
            'yes',
            'no',
          ],
        ],
      );
      const service = StudentImportService();

      final result = service.parseWorkbook(bytes);
      expect(result.rows, hasLength(1));
      expect(result.rows.single.status, 'Active');
      expect(result.rows.single.handbook, isFalse);
      expect(result.rows.single.mediaRelease, isTrue);
      expect(result.rows.single.accidentWaiver, isFalse);
      expect(
        result.issues.any((i) => i.contains('unknown status')),
        isTrue,
      );
      expect(
        result.issues.any((i) => i.contains('unexpected mode')),
        isTrue,
      );
      expect(
        result.issues.any((i) => i.contains('unrecognized handbook')),
        isTrue,
      );
    });
  });
}

Uint8List _buildWorkbookBytes({
  required List<String> headers,
  required List<List<String>> rows,
}) {
  final excel = xls.Excel.createExcel();
  excel.delete('Sheet1');
  final sheet = excel['Student Import'];

  for (var i = 0; i < headers.length; i++) {
    sheet
        .cell(xls.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        .value = xls.TextCellValue(headers[i]);
  }

  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      sheet
          .cell(xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1))
          .value = xls.TextCellValue(rows[r][c]);
    }
  }

  final encoded = excel.encode();
  return Uint8List.fromList(encoded ?? <int>[]);
}
