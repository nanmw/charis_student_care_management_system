import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';

import 'package:charis_student_care/core/utils/currency_utils.dart';
import 'package:charis_student_care/presentation/providers/dashboard_providers.dart';
import 'package:charis_student_care/presentation/providers/report_providers.dart';

/// Generates PDF and Excel bytes for the Student Summary report.
class ReportService {
  ReportService._();

  static final _dateFormat = DateFormat('yyyy-MM-dd');

  /// Builds a PDF document for the given [rows] and [filters].
  /// When [includePaymentColumns] is false, Total Paid and Balance columns are omitted (admin-only).
  /// Returns the PDF file as bytes.
  static Future<Uint8List> buildPdf(
    List<StudentReportRow> rows,
    ReportFilters filters, {
    bool includePaymentColumns = true,
  }) async {
    final pdf = pw.Document();
    final dateRangeStr =
        '${_dateFormat.format(filters.dateStart)} – ${_dateFormat.format(filters.dateEnd)}';
    final colCount = includePaymentColumns ? 8 : 6;
    final columnWidths = <int, pw.FlexColumnWidth>{
      for (var i = 0; i < colCount; i++)
        i: i == 0 ? const pw.FlexColumnWidth(2.5) : const pw.FlexColumnWidth(1.2),
    };

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context context) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(
            'Charis Student Care – Student Summary Report',
            style: const pw.TextStyle(
              fontSize: 10,
              color: PdfColors.grey700,
            ),
          ),
        ),
        footer: (pw.Context context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (pw.Context context) => [
          pw.Text(
            'Student Summary Report',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Period: $dateRangeStr • Mode: ${filters.mode}'
            '${filters.classFilter != null ? ' • Class: ${filters.classFilter}' : ''}'
            '${filters.classFilter == null && filters.year != null ? ' • Year: ${filters.year}' : ''}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: columnWidths,
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _cell('Student'),
                  _cell('Att. Days'),
                  _cell('Present'),
                  _cell('Att. %'),
                  _cell('Test Avg'),
                  _cell('Pass/Fail'),
                  if (includePaymentColumns) _cell('Total Paid'),
                  if (includePaymentColumns) _cell('Balance'),
                ],
              ),
              ...rows.map((r) => pw.TableRow(
                    children: [
                      _cell(r.studentName),
                      _cell('${r.attendanceTotalDays}'),
                      _cell('${r.attendancePresentDays}'),
                      _cell(_pct(r.attendancePercentage)),
                      _cell(_pct(r.testAverage)),
                      _cell('${r.testsPassed}/${r.testsFailed}'),
                      if (includePaymentColumns) _cell(CurrencyUtils.formatRand(r.totalPaid)),
                      if (includePaymentColumns) _cell(CurrencyUtils.formatRand(r.balance)),
                    ],
                  ),),
            ],
          ),
          if (rows.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.all(24),
              child: pw.Text(
                'No students match the selected filters.',
                style: const pw.TextStyle(fontSize: 12,),
              ),
            ),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _cell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 9)),
    );
  }

  static String _pct(double v) {
    return v.toStringAsFixed(1);
  }

  /// Builds an Excel workbook for the given [rows] and [filters].
  /// When [includePaymentColumns] is false, Total Paid and Balance columns are omitted (admin-only).
  /// Returns the .xlsx file as bytes.
  static Uint8List buildExcel(
    List<StudentReportRow> rows,
    ReportFilters filters, {
    bool includePaymentColumns = true,
  }) {
    final excel = Excel.createExcel();
    final sheet = excel['Student Summary'];

    final dateRangeStr =
        '${_dateFormat.format(filters.dateStart)} – ${_dateFormat.format(filters.dateEnd)}';

    final headers = [
      'Student',
      'Mode',
      'Attendance Days',
      'Present',
      'Attendance %',
      'Test Average',
      'Tests Passed',
      'Tests Failed',
      if (includePaymentColumns) 'Total Paid',
      if (includePaymentColumns) 'Balance',
    ];
    final colCount = headers.length;
    final lastCol = String.fromCharCode('A'.codeUnitAt(0) + colCount - 1);

    // Title row
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('${lastCol}1'));
    sheet.cell(CellIndex.indexByString('A1')).value =
        TextCellValue('Student Summary Report');
    final subtitle = StringBuffer('Period: $dateRangeStr | Mode: ${filters.mode}');
    if (filters.classFilter != null) {
      subtitle.write(' | Class: ${filters.classFilter}');
    } else if (filters.year != null) {
      subtitle.write(' | Year: ${filters.year}');
    }
    sheet.cell(CellIndex.indexByString('A2')).value =
        TextCellValue(subtitle.toString());

    // Header row
    for (var i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 4)).value =
          TextCellValue(headers[i]);
    }

    // Data rows
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final rowIndex = 5 + i;
      var col = 0;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
          .value = TextCellValue(r.studentName);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
          .value = TextCellValue(r.student.mode ?? '');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
          .value = TextCellValue(r.attendanceTotalDays.toString());
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
          .value = TextCellValue(r.attendancePresentDays.toString());
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
          .value = TextCellValue(r.attendancePercentage.toStringAsFixed(1));
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
          .value = TextCellValue(r.testAverage.toStringAsFixed(1));
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
          .value = TextCellValue(r.testsPassed.toString());
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
          .value = TextCellValue(r.testsFailed.toString());
      if (includePaymentColumns) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
            .value = TextCellValue(CurrencyUtils.formatRand(r.totalPaid));
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
            .value = TextCellValue(CurrencyUtils.formatRand(r.balance));
      }
    }

    final encoded = excel.encode();
    if (encoded == null) return Uint8List(0);
    return Uint8List.fromList(encoded);
  }

  // --- Cohort Summary report ---
  /// When [includeBalanceColumn] is false, Total Balance column is omitted (admin-only).
  static Future<Uint8List> buildCohortSummaryPdf(
    List<CohortReportRow> rows, {
    bool includeBalanceColumn = true,
  }) async {
    final pdf = pw.Document();
    final colCount = includeBalanceColumn ? 7 : 6;
    final columnWidths = <int, pw.FlexColumnWidth>{
      for (var i = 0; i < colCount; i++)
        i: i == 0 ? const pw.FlexColumnWidth(1.5) : const pw.FlexColumnWidth(1.2),
    };
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) => [
          pw.Text(
            'Cohort Summary Report',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: columnWidths,
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  _cell('Year / Mode'),
                  _cell('Students'),
                  _cell('Avg Att. %'),
                  _cell('Outstanding'),
                  _cell('Failed'),
                  _cell('Passed'),
                  if (includeBalanceColumn) _cell('Total Balance'),
                ],
              ),
              ...rows.map((r) => pw.TableRow(
                    children: [
                      _cell(r.cohortLabel),
                      _cell('${r.studentCount}'),
                      _cell(
                        r.avgAttendancePercent != null
                            ? _pct(r.avgAttendancePercent!)
                            : '—',
                      ),
                      _cell('${r.outstandingTests}'),
                      _cell('${r.failedTests}'),
                      _cell('${r.passedTests}'),
                      if (includeBalanceColumn) _cell(CurrencyUtils.formatRand(r.totalBalance)),
                    ],
                  ),),
            ],
          ),
          if (rows.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.all(24),
              child: pw.Text(
                'No cohort data.',
                style: const pw.TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
    return pdf.save();
  }

  /// When [includeBalanceColumn] is false, Total Balance column is omitted (admin-only).
  static Uint8List buildCohortSummaryExcel(List<CohortReportRow> rows, {bool includeBalanceColumn = true}) {
    final excel = Excel.createExcel();
    final sheet = excel['Cohort Summary'];
    final headers = [
      'Year / Mode',
      'Students',
      'Avg Att. %',
      'Outstanding',
      'Failed',
      'Passed',
      if (includeBalanceColumn) 'Total Balance',
    ];
    for (var i = 0; i < headers.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final rowIndex = 1 + i;
      var col = 0;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
          .value = TextCellValue(r.cohortLabel);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
          .value = TextCellValue(r.studentCount.toString());
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
          .value = TextCellValue(r.avgAttendancePercent != null
              ? r.avgAttendancePercent!.toStringAsFixed(1)
              : '—',);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
          .value = TextCellValue(r.outstandingTests.toString());
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
          .value = TextCellValue(r.failedTests.toString());
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
          .value = TextCellValue(r.passedTests.toString());
      if (includeBalanceColumn) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: col++, rowIndex: rowIndex))
            .value = TextCellValue(CurrencyUtils.formatRand(r.totalBalance));
      }
    }
    final encoded = excel.encode();
    if (encoded == null) return Uint8List(0);
    return Uint8List.fromList(encoded);
  }

  /// Recent Activities / Audit Log report (PDF).
  static Future<Uint8List> buildRecentActivitiesPdf(
    List<ActivityReportRow> rows,
  ) async {
    const headers = [
      'Timestamp',
      'User',
      'Student',
      'Screen',
      'What Changed',
      'Operation',
      'Table',
    ];
    final tableRows = rows
        .map((r) => [
              _dateFormat.format(r.timestamp),
              r.user,
              r.student ?? '—',
              r.screen ?? '—',
              r.whatChanged ?? '—',
              r.operation,
              r.table,
            ],)
        .toList();
    return buildTablePdf('Recent Activities', headers, tableRows);
  }

  /// Recent Activities / Audit Log report (Excel).
  static Uint8List buildRecentActivitiesExcel(
    List<ActivityReportRow> rows,
  ) {
    const headers = [
      'Timestamp',
      'User',
      'Student',
      'Screen',
      'What Changed',
      'Operation',
      'Table',
    ];
    final tableRows = rows
        .map((r) => [
              _dateFormat.format(r.timestamp),
              r.user,
              r.student ?? '—',
              r.screen ?? '—',
              r.whatChanged ?? '—',
              r.operation,
              r.table,
            ],)
        .toList();
    return buildTableExcel(
      'Recent Activities',
      'Recent Activities',
      headers,
      tableRows,
    );
  }

  /// Generic table report (PDF). [headers] and [rows] must have same column count.
  static Future<Uint8List> buildTablePdf(
    String title,
    List<String> headers,
    List<List<String>> rows,
  ) async {
    final pdf = pw.Document();
    final colCount = headers.length;
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) => [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {
              for (var i = 0; i < colCount; i++) i: const pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: headers.map((h) => _cell(h)).toList(),
              ),
              ...rows.map((row) => pw.TableRow(
                    children: row
                        .map((cell) => _cell(cell.length > 50 ? '${cell.substring(0, 47)}...' : cell))
                        .toList(),
                  ),),
            ],
          ),
          if (rows.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.all(24),
              child: pw.Text('No data.', style: const pw.TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
    return pdf.save();
  }

  /// Generic table report (Excel).
  static Uint8List buildTableExcel(
    String title,
    String sheetName,
    List<String> headers,
    List<List<String>> rows,
  ) {
    final excel = Excel.createExcel();
    final sheet = excel[sheetName.length > 31 ? sheetName.substring(0, 31) : sheetName];
    for (var i = 0; i < headers.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }
    for (var i = 0; i < rows.length; i++) {
      for (var j = 0; j < rows[i].length && j < headers.length; j++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: j, rowIndex: 1 + i))
            .value = TextCellValue(rows[i][j]);
      }
    }
    final encoded = excel.encode();
    if (encoded == null) return Uint8List(0);
    return Uint8List.fromList(encoded);
  }
}
