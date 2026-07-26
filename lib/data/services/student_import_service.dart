import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;

enum StudentImportFailureType {
  fileParse,
  headerValidation,
  worksheetValidation,
}

class StudentImportException implements Exception {
  StudentImportException({
    required this.type,
    required this.message,
    this.debugDetails,
  });

  final StudentImportFailureType type;
  final String message;
  final String? debugDetails;

  @override
  String toString() => message;
}

class ParsedStudentImportRow {
  ParsedStudentImportRow({
    required this.rowNumber,
    required this.surname,
    required this.firstName,
    this.status,
    this.className,
    this.mode,
    this.admissionYear,
    this.contactInfo,
    this.email,
    required this.handbook,
    required this.mediaRelease,
    required this.accidentWaiver,
    this.sessionCode,
  });

  final int rowNumber;
  final String surname;
  final String firstName;
  final String? status;
  final String? className;
  final String? mode;
  final String? admissionYear;
  final String? contactInfo;
  final String? email;
  final bool handbook;
  final bool mediaRelease;
  final bool accidentWaiver;
  final String? sessionCode;
}

class StudentImportParseResult {
  const StudentImportParseResult({
    required this.rows,
    required this.issues,
    this.detailedIssues = const <StudentImportIssue>[],
  });

  final List<ParsedStudentImportRow> rows;
  final List<String> issues;
  final List<StudentImportIssue> detailedIssues;
}

enum StudentImportIssueType { parse, header, rowValidation, mapping }

class StudentImportIssue {
  const StudentImportIssue({
    required this.type,
    required this.message,
    this.rowNumber,
  });

  final StudentImportIssueType type;
  final String message;
  final int? rowNumber;
}

typedef ExcelDecoder = xls.Excel Function(Uint8List bytes);

class StudentImportService {
  const StudentImportService({ExcelDecoder? decoder})
      : _decoder = decoder ?? _defaultDecoder;

  final ExcelDecoder _decoder;

  static xls.Excel _defaultDecoder(Uint8List bytes) => xls.Excel.decodeBytes(bytes);

  StudentImportParseResult parseWorkbook(Uint8List bytes) {
    final xls.Excel workbook;
    try {
      workbook = _decoder(bytes);
    } catch (e) {
      final raw = e.toString();
      if (raw.toLowerCase().contains('custom numfmtid') &&
          raw.toLowerCase().contains('starts at 164')) {
        throw StudentImportException(
          type: StudentImportFailureType.fileParse,
          message:
              'This workbook uses an unsupported Excel number format. Re-save it as a standard .xlsx file in Excel and try again, or use the Download Template button.',
          debugDetails: raw,
        );
      }
      throw StudentImportException(
        type: StudentImportFailureType.fileParse,
        message:
            'Could not read this Excel file. Please use a standard .xlsx file, preferably from the student import template.',
        debugDetails: raw,
      );
    }

    if (workbook.tables.isEmpty) {
      throw StudentImportException(
        type: StudentImportFailureType.worksheetValidation,
        message: 'The Excel file has no worksheets.',
      );
    }

    final sheet = workbook.tables.values.firstWhere(
      (table) => table.rows.isNotEmpty,
      orElse: () => workbook.tables.values.first,
    );
    final rows = sheet.rows;
    if (rows.length < 2) {
      throw StudentImportException(
        type: StudentImportFailureType.worksheetValidation,
        message: 'The worksheet must have a header row and at least one data row.',
      );
    }

    final headerMap = _buildHeaderMap(rows.first);
    if (!headerMap.containsKey('surname') || !headerMap.containsKey('firstname')) {
      throw StudentImportException(
        type: StudentImportFailureType.headerValidation,
        message: 'Template must include at least "surname" and "firstName" columns.',
      );
    }

    final issues = <String>[];
    final detailedIssues = <StudentImportIssue>[];
    final parsedRows = <ParsedStudentImportRow>[];
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final surname = (_getCell(row, headerMap, 'surname') ?? '').trim();
      final firstName = (_getCell(row, headerMap, 'firstname') ?? '').trim();
      if (surname.isEmpty || firstName.isEmpty) {
        final message = 'Row ${rowIndex + 1}: missing surname or firstName';
        issues.add(message);
        detailedIssues.add(
          StudentImportIssue(
            type: StudentImportIssueType.rowValidation,
            message: message,
            rowNumber: rowIndex + 1,
          ),
        );
        continue;
      }

      final className = _normalizedOptional(
        _getAnyCell(row, headerMap, const ['classname', 'class']),
      );

      final statusRaw = _getAnyCell(row, headerMap, const ['status']);
      String? status;
      if (statusRaw != null && statusRaw.trim().isNotEmpty) {
        if (_isKnownStatus(statusRaw)) {
          status = _normalizeStatus(statusRaw);
        } else {
          status = 'Active';
          final message =
              'Row ${rowIndex + 1}: unknown status "$statusRaw", defaulting to Active';
          issues.add(message);
          detailedIssues.add(
            StudentImportIssue(
              type: StudentImportIssueType.rowValidation,
              message: message,
              rowNumber: rowIndex + 1,
            ),
          );
        }
      }

      final modeRaw = _getAnyCell(row, headerMap, const ['mode']);
      final mode = _normalizedOptional(modeRaw);
      if (mode != null && !_isKnownMode(mode)) {
        final message =
            'Row ${rowIndex + 1}: unexpected mode "$mode" (expected Full-time or Hybrid)';
        issues.add(message);
        detailedIssues.add(
          StudentImportIssue(
            type: StudentImportIssueType.rowValidation,
            message: message,
            rowNumber: rowIndex + 1,
          ),
        );
      }

      final handbookRaw = _getAnyCell(row, headerMap, const ['handbook']);
      final mediaRaw = _getAnyCell(row, headerMap, const ['mediarelease']);
      final waiverRaw = _getAnyCell(row, headerMap, const ['accidentwaiver']);
      final handbookParsed = _parseBoolCell(handbookRaw);
      final mediaParsed = _parseBoolCell(mediaRaw);
      final waiverParsed = _parseBoolCell(waiverRaw);
      if (handbookRaw != null &&
          handbookRaw.trim().isNotEmpty &&
          handbookParsed == null) {
        final message =
            'Row ${rowIndex + 1}: unrecognized handbook value "$handbookRaw", defaulting to false';
        issues.add(message);
        detailedIssues.add(
          StudentImportIssue(
            type: StudentImportIssueType.rowValidation,
            message: message,
            rowNumber: rowIndex + 1,
          ),
        );
      }
      if (mediaRaw != null &&
          mediaRaw.trim().isNotEmpty &&
          mediaParsed == null) {
        final message =
            'Row ${rowIndex + 1}: unrecognized mediaRelease value "$mediaRaw", defaulting to false';
        issues.add(message);
        detailedIssues.add(
          StudentImportIssue(
            type: StudentImportIssueType.rowValidation,
            message: message,
            rowNumber: rowIndex + 1,
          ),
        );
      }
      if (waiverRaw != null &&
          waiverRaw.trim().isNotEmpty &&
          waiverParsed == null) {
        final message =
            'Row ${rowIndex + 1}: unrecognized accidentWaiver value "$waiverRaw", defaulting to false';
        issues.add(message);
        detailedIssues.add(
          StudentImportIssue(
            type: StudentImportIssueType.rowValidation,
            message: message,
            rowNumber: rowIndex + 1,
          ),
        );
      }

      parsedRows.add(
        ParsedStudentImportRow(
          rowNumber: rowIndex + 1,
          surname: surname,
          firstName: firstName,
          status: status,
          className: (className != null && className.isNotEmpty) ? className : null,
          mode: mode,
          admissionYear: _normalizedOptional(
            _getAnyCell(row, headerMap, const [
              'admissionyear',
              'admission_year',
              'admissionyr',
            ]),
          ),
          contactInfo: _normalizedOptional(
            _getAnyCell(row, headerMap, const [
              'contactinfo',
              'contact',
              'phone',
              'phonenumber',
            ]),
          ),
          email: _normalizedOptional(_getAnyCell(row, headerMap, const ['email'])),
          handbook: handbookParsed ?? false,
          mediaRelease: mediaParsed ?? false,
          accidentWaiver: waiverParsed ?? false,
          sessionCode: _normalizedOptional(
            _getAnyCell(row, headerMap, const [
              'academicsession',
              'session',
              'sessioncode',
            ]),
          ),
        ),
      );
    }

    return StudentImportParseResult(
      rows: parsedRows,
      issues: issues,
      detailedIssues: detailedIssues,
    );
  }

  Map<String, int> _buildHeaderMap(List<xls.Data?> headerRow) {
    final headerMap = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final value = headerRow[i]?.value;
      final key = _normalizeHeader(value?.toString() ?? '');
      if (key.isNotEmpty && !headerMap.containsKey(key)) {
        headerMap[key] = i;
      }
    }
    return headerMap;
  }

  String? _getCell(List<xls.Data?> row, Map<String, int> headerMap, String key) {
    final index = headerMap[key];
    if (index == null || index < 0 || index >= row.length) {
      return null;
    }
    return row[index]?.value?.toString();
  }

  String? _getAnyCell(
    List<xls.Data?> row,
    Map<String, int> headerMap,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = _getCell(row, headerMap, key);
      if (value != null) return value;
    }
    return null;
  }

  String _normalizeHeader(String value) {
    final trimmed = value.trim().toLowerCase();
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

  bool? _parseBoolCell(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;
    if (v == 'true' || v == 'yes' || v == 'y' || v == '1') return true;
    if (v == 'false' || v == 'no' || v == 'n' || v == '0') return false;
    return null;
  }

  bool _isKnownStatus(String raw) {
    final v = raw.trim().toLowerCase();
    return v == 'active' ||
        v == 'withdrawn' ||
        v == 'transferred' ||
        v == 'correspondence';
  }

  bool _isKnownMode(String mode) {
    final v = mode.trim().toLowerCase();
    return v == 'full-time' || v == 'fulltime' || v == 'hybrid';
  }

  String _normalizeStatus(String raw) {
    final v = raw.trim().toLowerCase();
    switch (v) {
      case 'active':
        return 'Active';
      case 'withdrawn':
        return 'Withdrawn';
      case 'transferred':
        return 'Transferred';
      case 'correspondence':
        return 'Correspondence';
      default:
        return 'Active';
    }
  }

  String? _normalizedOptional(String? raw) {
    final value = _normalizeScalar(raw);
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String? _normalizeScalar(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final number = num.tryParse(value);
    if (number != null) {
      if (number is int) return number.toString();
      if (number % 1 == 0) return number.toInt().toString();
    }
    return value;
  }
}
