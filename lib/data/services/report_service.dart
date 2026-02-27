import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';

import 'package:charis_student_care/core/utils/currency_utils.dart';
import 'package:charis_student_care/presentation/providers/report_providers.dart';

/// Generates PDF and Excel bytes for the Student Summary report.
class ReportService {
  ReportService._();

  static final _dateFormat = DateFormat('yyyy-MM-dd');

  /// Builds a PDF document for the given [rows] and [filters].
  /// Returns the PDF file as bytes.
  static Future<Uint8List> buildPdf(
    List<StudentReportRow> rows,
    ReportFilters filters,
  ) async {
    final pdf = pw.Document();
    final dateRangeStr =
        '${_dateFormat.format(filters.dateStart)} – ${_dateFormat.format(filters.dateEnd)}';

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
            '${filters.year != null ? ' • Year: ${filters.year}' : ''}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 16),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(2.5),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1),
              5: const pw.FlexColumnWidth(1),
              6: const pw.FlexColumnWidth(1.2),
              7: const pw.FlexColumnWidth(1.2),
            },
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
                  _cell('Total Paid'),
                  _cell('Balance'),
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
                      _cell(CurrencyUtils.formatRand(r.totalPaid)),
                      _cell(CurrencyUtils.formatRand(r.balance)),
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
  /// Returns the .xlsx file as bytes.
  static Uint8List buildExcel(
    List<StudentReportRow> rows,
    ReportFilters filters,
  ) {
    final excel = Excel.createExcel();
    final sheet = excel['Student Summary'];

    final dateRangeStr =
        '${_dateFormat.format(filters.dateStart)} – ${_dateFormat.format(filters.dateEnd)}';

    // Title row
    sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('H1'));
    sheet.cell(CellIndex.indexByString('A1')).value =
        TextCellValue('Student Summary Report');
    sheet.cell(CellIndex.indexByString('A2')).value =
        TextCellValue('Period: $dateRangeStr | Mode: ${filters.mode}');

    // Header row
    final headers = [
      'Student',
      'Mode',
      'Attendance Days',
      'Present',
      'Attendance %',
      'Test Average',
      'Tests Passed',
      'Tests Failed',
      'Total Paid',
      'Balance',
    ];
    for (var i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 4)).value =
          TextCellValue(headers[i]);
    }

    // Data rows
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final rowIndex = 5 + i;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
          .value = TextCellValue(r.studentName);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex))
          .value = TextCellValue(r.student.mode ?? '');
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex))
          .value = TextCellValue(r.attendanceTotalDays.toString());
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex))
          .value = TextCellValue(r.attendancePresentDays.toString());
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex))
          .value = TextCellValue(r.attendancePercentage.toStringAsFixed(1));
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex))
          .value = TextCellValue(r.testAverage.toStringAsFixed(1));
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex))
          .value = TextCellValue(r.testsPassed.toString());
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: rowIndex))
          .value = TextCellValue(r.testsFailed.toString());
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: rowIndex))
          .value = TextCellValue(CurrencyUtils.formatRand(r.totalPaid));
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 9, rowIndex: rowIndex))
          .value = TextCellValue(CurrencyUtils.formatRand(r.balance));
    }

    final encoded = excel.encode();
    if (encoded == null) return Uint8List(0);
    return Uint8List.fromList(encoded);
  }

  // --- Cohort Summary report ---
  static Future<Uint8List> buildCohortSummaryPdf(
    List<CohortReportRow> rows,
  ) async {
    final pdf = pw.Document();
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
            columnWidths: {
              0: const pw.FlexColumnWidth(1.5),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1),
              5: const pw.FlexColumnWidth(1),
              6: const pw.FlexColumnWidth(1.2),
            },
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
                  _cell('Total Balance'),
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
                      _cell(CurrencyUtils.formatRand(r.totalBalance)),
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

  static Uint8List buildCohortSummaryExcel(List<CohortReportRow> rows) {
    final excel = Excel.createExcel();
    final sheet = excel['Cohort Summary'];
    final headers = [
      'Year / Mode',
      'Students',
      'Avg Att. %',
      'Outstanding',
      'Failed',
      'Passed',
      'Total Balance',
    ];
    for (var i = 0; i < headers.length; i++) {
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
          .value = TextCellValue(headers[i]);
    }
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      final rowIndex = 1 + i;
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex))
          .value = TextCellValue(r.cohortLabel);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex))
          .value = TextCellValue(r.studentCount.toString());
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex))
          .value = TextCellValue(r.avgAttendancePercent != null
              ? r.avgAttendancePercent!.toStringAsFixed(1)
              : '—',);
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex))
          .value = TextCellValue(r.outstandingTests.toString());
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex))
          .value = TextCellValue(r.failedTests.toString());
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex))
          .value = TextCellValue(r.passedTests.toString());
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex))
          .value = TextCellValue(CurrencyUtils.formatRand(r.totalBalance));
    }
    final encoded = excel.encode();
    if (encoded == null) return Uint8List(0);
    return Uint8List.fromList(encoded);
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
