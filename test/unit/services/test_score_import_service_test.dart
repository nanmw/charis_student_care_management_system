import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/data/services/test_score_import_service.dart';

void main() {
  group('TestScoreImportService', () {
    const service = TestScoreImportService();

    test('throws header validation when required columns are missing', () {
      final bytes = _buildWorkbookBytes(
        headers: const ['surname', 'firstName'],
        rows: const [
          ['Doe', 'John'],
        ],
      );

      expect(
        () => service.parseWorkbook(bytes),
        throwsA(
          isA<TestScoreImportException>().having(
            (e) => e.type,
            'type',
            TestScoreImportFailureType.headerValidation,
          ),
        ),
      );
    });

    test('maps numFmtId decode exception to actionable parse error', () {
      final failing = TestScoreImportService(
        decoder: (_) => throw Exception(
          'custom numFmtId starts at 164 but found a value of 42',
        ),
      );

      expect(
        () => failing.parseWorkbook(Uint8List(0)),
        throwsA(
          isA<TestScoreImportException>()
              .having(
                (e) => e.type,
                'type',
                TestScoreImportFailureType.fileParse,
              )
              .having(
                (e) => e.message,
                'message',
                contains('unsupported Excel number format'),
              ),
        ),
      );
    });

    test('skips blank scores without reporting an issue', () {
      final bytes = _buildWorkbookBytes(
        headers: const ['surname', 'firstName', 'score', 'notes'],
        rows: const [
          ['Doe', 'John', '', 'absent'],
          ['Ade', 'Ada', '80', ''],
        ],
      );

      final result = service.parseWorkbook(bytes);

      expect(result.issues, isEmpty);
      expect(result.rows, hasLength(1));
      expect(result.rows.single.surname, 'Ade');
      expect(result.rows.single.score, 80);
      expect(result.rows.single.notes, isNull);
      expect(result.rows.single.notesProvided, isTrue);
    });

    test('reports invalid and out-of-range scores', () {
      final bytes = _buildWorkbookBytes(
        headers: const ['surname', 'firstName', 'score'],
        rows: const [
          ['Doe', 'John', 'high'],
          ['Ade', 'Ada', '101'],
          ['Oka', 'Ben', '85.5'],
        ],
      );

      final result = service.parseWorkbook(bytes);

      expect(result.rows, isEmpty);
      expect(result.issues, hasLength(3));
      expect(result.issues.every((i) => i.contains('whole number')), isTrue);
    });

    test('accepts numeric text 85.0 and optional notes', () {
      final bytes = _buildWorkbookBytes(
        headers: const ['surname', 'firstName', 'score', 'notes'],
        rows: const [
          ['Doe', 'John', '85.0', 'Quiz 1'],
        ],
      );

      final result = service.parseWorkbook(bytes);

      expect(result.issues, isEmpty);
      expect(result.rows.single.score, 85);
      expect(result.rows.single.notes, 'Quiz 1');
    });

    test('accepts an Excel numeric score cell', () {
      final bytes = _buildWorkbookBytes(
        headers: const ['surname', 'firstName', 'score'],
        rows: const [
          ['Doe', 'John', '85'],
        ],
        numericScoreColumn: 2,
      );

      final result = service.parseWorkbook(bytes);

      expect(result.issues, isEmpty);
      expect(result.rows.single.score, 85);
      expect(result.rows.single.notesProvided, isFalse);
    });

    test('reports a row that is missing a name', () {
      final bytes = _buildWorkbookBytes(
        headers: const ['surname', 'firstName', 'score'],
        rows: const [
          ['', 'John', '70'],
        ],
      );

      final result = service.parseWorkbook(bytes);

      expect(result.rows, isEmpty);
      expect(result.issues.single, contains('missing surname or firstName'));
    });
  });
}

Uint8List _buildWorkbookBytes({
  required List<String> headers,
  required List<List<String>> rows,
  int? numericScoreColumn,
}) {
  final excel = xls.Excel.createExcel();
  excel.delete('Sheet1');
  final sheet = excel['Test Scores'];

  for (var i = 0; i < headers.length; i++) {
    sheet
        .cell(xls.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
        .value = xls.TextCellValue(headers[i]);
  }

  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      final raw = rows[r][c];
      final xls.CellValue cellValue;
      if (numericScoreColumn != null &&
          c == numericScoreColumn &&
          raw.isNotEmpty) {
        cellValue = xls.IntCellValue(int.parse(raw));
      } else {
        cellValue = xls.TextCellValue(raw);
      }
      sheet
          .cell(
            xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1),
          )
          .value = cellValue;
    }
  }

  final encoded = excel.encode();
  return Uint8List.fromList(encoded ?? <int>[]);
}
