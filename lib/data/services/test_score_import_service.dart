import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;

enum TestScoreImportFailureType {
  fileParse,
  headerValidation,
  worksheetValidation,
}

class TestScoreImportException implements Exception {
  TestScoreImportException({
    required this.type,
    required this.message,
    this.debugDetails,
  });

  final TestScoreImportFailureType type;
  final String message;
  final String? debugDetails;

  @override
  String toString() => message;
}

class ParsedTestScoreRow {
  ParsedTestScoreRow({
    required this.rowNumber,
    required this.surname,
    required this.firstName,
    required this.score,
    required this.notesProvided,
    this.notes,
  });

  final int rowNumber;
  final String surname;
  final String firstName;
  final int score;

  /// True when the workbook has a notes column, even if this cell is blank.
  final bool notesProvided;
  final String? notes;
}

class TestScoreImportParseResult {
  const TestScoreImportParseResult({
    required this.rows,
    required this.issues,
  });

  final List<ParsedTestScoreRow> rows;
  final List<String> issues;
}

typedef TestScoreExcelDecoder = xls.Excel Function(Uint8List bytes);

class TestScoreImportService {
  const TestScoreImportService({TestScoreExcelDecoder? decoder})
      : _decoder = decoder ?? _defaultDecoder;

  final TestScoreExcelDecoder _decoder;

  static xls.Excel _defaultDecoder(Uint8List bytes) =>
      xls.Excel.decodeBytes(bytes);

  TestScoreImportParseResult parseWorkbook(Uint8List bytes) {
    final xls.Excel workbook;
    try {
      workbook = _decoder(bytes);
    } catch (e) {
      final raw = e.toString();
      if (raw.toLowerCase().contains('custom numfmtid') &&
          raw.toLowerCase().contains('starts at 164')) {
        throw TestScoreImportException(
          type: TestScoreImportFailureType.fileParse,
          message:
              'This workbook uses an unsupported Excel number format. Re-save it as a standard .xlsx file in Excel and try again, or use the Download template button.',
          debugDetails: raw,
        );
      }
      throw TestScoreImportException(
        type: TestScoreImportFailureType.fileParse,
        message:
            'Could not read this Excel file. Please use a standard .xlsx file, preferably from the test score template.',
        debugDetails: raw,
      );
    }

    if (workbook.tables.isEmpty) {
      throw TestScoreImportException(
        type: TestScoreImportFailureType.worksheetValidation,
        message: 'The Excel file has no worksheets.',
      );
    }

    final sheet = workbook.tables.values.firstWhere(
      (table) => table.rows.isNotEmpty,
      orElse: () => workbook.tables.values.first,
    );
    final rows = sheet.rows;
    if (rows.length < 2) {
      throw TestScoreImportException(
        type: TestScoreImportFailureType.worksheetValidation,
        message:
            'The worksheet must have a header row and at least one data row.',
      );
    }

    final headerMap = _buildHeaderMap(rows.first);
    if (!headerMap.containsKey('surname') ||
        !headerMap.containsKey('firstname') ||
        !headerMap.containsKey('score')) {
      throw TestScoreImportException(
        type: TestScoreImportFailureType.headerValidation,
        message:
            'Template must include "surname", "firstName", and "score" columns.',
      );
    }

    final notesProvided = headerMap.containsKey('notes') ||
        headerMap.containsKey('note') ||
        headerMap.containsKey('label');

    final issues = <String>[];
    final parsedRows = <ParsedTestScoreRow>[];
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final rowNumber = rowIndex + 1;
      final surname = (_cellText(row, headerMap, 'surname') ?? '').trim();
      final firstName = (_cellText(row, headerMap, 'firstname') ?? '').trim();
      final scoreRaw = _cellText(row, headerMap, 'score');
      final notesRaw = notesProvided
          ? _cellTextAny(row, headerMap, const ['notes', 'note', 'label'])
          : null;

      final scoreBlank = scoreRaw == null || scoreRaw.trim().isEmpty;
      final notesBlank = notesRaw == null || notesRaw.trim().isEmpty;
      if (surname.isEmpty &&
          firstName.isEmpty &&
          scoreBlank &&
          notesBlank) {
        continue;
      }

      if (surname.isEmpty || firstName.isEmpty) {
        issues.add('Row $rowNumber: missing surname or firstName');
        continue;
      }

      if (scoreBlank) {
        continue;
      }

      final score = _parseScore(scoreRaw.trim());
      if (score == null) {
        issues.add(
          'Row $rowNumber: score "$scoreRaw" must be a whole number from 0 to 100',
        );
        continue;
      }

      parsedRows.add(
        ParsedTestScoreRow(
          rowNumber: rowNumber,
          surname: surname,
          firstName: firstName,
          score: score,
          notesProvided: notesProvided,
          notes: notesBlank ? null : notesRaw.trim(),
        ),
      );
    }

    return TestScoreImportParseResult(rows: parsedRows, issues: issues);
  }

  Map<String, int> _buildHeaderMap(List<xls.Data?> headerRow) {
    final headerMap = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final key = _normalizeHeader(_cellValueText(headerRow[i]?.value));
      if (key.isNotEmpty && !headerMap.containsKey(key)) {
        headerMap[key] = i;
      }
    }
    return headerMap;
  }

  String? _cellText(
    List<xls.Data?> row,
    Map<String, int> headerMap,
    String key,
  ) {
    final index = headerMap[key];
    if (index == null || index < 0 || index >= row.length) {
      return null;
    }
    return _cellValueText(row[index]?.value);
  }

  String? _cellTextAny(
    List<xls.Data?> row,
    Map<String, int> headerMap,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (!headerMap.containsKey(key)) continue;
      return _cellText(row, headerMap, key);
    }
    return null;
  }

  String? _cellValueText(xls.CellValue? value) {
    if (value == null) return null;
    if (value is xls.TextCellValue) {
      return value.value.toString();
    }
    return value.toString();
  }

  String _normalizeHeader(String? value) {
    final trimmed = (value ?? '').trim().toLowerCase();
    if (trimmed.isEmpty) return '';
    final buf = StringBuffer();
    for (final codePoint in trimmed.runes) {
      final ch = String.fromCharCode(codePoint);
      if (ch != ' ' && ch != '_' && ch != '-') {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  int? _parseScore(String raw) {
    final number = num.tryParse(raw);
    if (number == null || number % 1 != 0) return null;
    final score = number.toInt();
    if (score < 0 || score > 100) return null;
    return score;
  }
}
