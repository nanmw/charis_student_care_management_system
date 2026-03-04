import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'package:charis_student_care/data/services/report_service.dart';
import 'package:charis_student_care/presentation/providers/dashboard_providers.dart';

final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

/// Recent Activities / Audit Log screen.
class RecentActivitiesScreen extends ConsumerStatefulWidget {
  const RecentActivitiesScreen({super.key});

  @override
  ConsumerState<RecentActivitiesScreen> createState() =>
      _RecentActivitiesScreenState();
}

class _RecentActivitiesScreenState
    extends ConsumerState<RecentActivitiesScreen> {
  late DateTime _dateStart;
  late DateTime _dateEnd;
  String _userFilter = '';
  String _screenFilter = '';
  bool _isExporting = false;
  static const int _pageSize = 50;
  final ScrollController _scrollController = ScrollController();
  int _visibleRowCount = _pageSize;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateEnd = now;
    _dateStart = now.subtract(const Duration(days: 7));
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  ActivityReportFilters get _filters => ActivityReportFilters(
        dateStart: _dateStart,
        dateEnd: _dateEnd,
        userFilter: _userFilter.trim().isEmpty ? null : _userFilter.trim(),
        screenFilter:
            _screenFilter.trim().isEmpty ? null : _screenFilter.trim(),
      );

  Future<void> _pickDateStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateStart,
      firstDate: DateTime(2020),
      lastDate: _dateEnd,
    );
    if (picked != null) {
      setState(() {
        _dateStart = DateTime(
          picked.year,
          picked.month,
          picked.day,
          0,
          0,
        );
      });
    }
  }

  Future<void> _pickDateEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateEnd,
      firstDate: _dateStart,
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _dateEnd = DateTime(
          picked.year,
          picked.month,
          picked.day,
          23,
          59,
          59,
        );
      });
    }
  }

  Future<void> _exportReport({required bool asPdf}) async {
    final value = ref.read(recentActivitiesReportProvider(_filters)).valueOrNull;
    if (value == null || value.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No activities to export.')),
        );
      }
      return;
    }
    setState(() => _isExporting = true);
    try {
      final extension = asPdf ? 'pdf' : 'xlsx';
      final suggestedName =
          'Recent_Activities_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.$extension';
      final Uint8List bytes = asPdf
          ? await ReportService.buildRecentActivitiesPdf(value)
          : ReportService.buildRecentActivitiesExcel(value);
      final downloadsDir = await getDownloadsDirectory();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save report',
        fileName: suggestedName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: [extension],
        initialDirectory: downloadsDir?.path,
      );
      if (mounted && path != null && path.isNotEmpty) {
        try {
          String filePath = path;
          if (!filePath.toLowerCase().endsWith('.$extension')) {
            filePath = '$filePath.$extension';
          }
          await File(filePath).writeAsBytes(bytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Report saved to $filePath'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } catch (writeError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Export failed: $writeError'),
                backgroundColor: Theme.of(context).colorScheme.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      debugPrint('Export error: $e\n$st');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final rowsAsync = ref.watch(recentActivitiesReportProvider(_filters));

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Recent Activities',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 24,
              fontFamily: 'Questrial',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Audit log of recent changes, scoped by user role and facilitator scope.',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
              fontFamily: 'Questrial',
            ),
          ),
          const SizedBox(height: 24),
          _buildFilters(colorScheme),
          const SizedBox(height: 16),
          Row(
            children: [
              const Spacer(),
              if (_isExporting)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _isExporting ? null : () => _exportReport(asPdf: true),
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('Download PDF'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _isExporting ? null : () => _exportReport(asPdf: false),
                icon: const Icon(Icons.table_chart, size: 18),
                label: const Text('Download Excel'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: rowsAsync.when(
              data: (rows) {
                if (rows.isEmpty) {
                  return Center(
                    child: Text(
                      'No activities match the selected filters.',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontFamily: 'Questrial',
                      ),
                    ),
                  );
                }
                final total = rows.length;
                final visibleCount =
                    _visibleRowCount < total ? _visibleRowCount : total;
                final visibleRows = rows.take(visibleCount).toList();

                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification.metrics.pixels >=
                            notification.metrics.maxScrollExtent - 200 &&
                        _visibleRowCount < total) {
                      setState(() {
                        _visibleRowCount = (_visibleRowCount + _pageSize)
                            .clamp(0, total);
                      });
                    }
                    return false;
                  },
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Card(
                      elevation: 0,
                      color: colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: colorScheme.outlineVariant
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('Timestamp')),
                            DataColumn(label: Text('User')),
                            DataColumn(label: Text('Student')),
                            DataColumn(label: Text('Screen')),
                            DataColumn(label: Text('What Changed')),
                            DataColumn(label: Text('Operation')),
                            DataColumn(label: Text('Table')),
                          ],
                          rows: visibleRows
                              .map(
                                (r) => DataRow(
                                  cells: [
                                    DataCell(
                                      Text(_dateFormat.format(r.timestamp)),
                                    ),
                                    DataCell(Text(r.user)),
                                    DataCell(Text(r.student ?? '—')),
                                    DataCell(Text(r.screen ?? '—')),
                                    DataCell(Text(r.whatChanged ?? '—')),
                                    DataCell(Text(r.operation)),
                                    DataCell(Text(r.table)),
                                  ],
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  ),
                );
              },
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (err, _) => Center(
                child: Text(
                  'Could not load activities: $err',
                  style: TextStyle(
                    color: colorScheme.error,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Date Range',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDateStart,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        DateFormat('yyyy-MM-dd').format(_dateStart),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('–'),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDateEnd,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        DateFormat('yyyy-MM-dd').format(_dateEnd),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'User',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search by user name or ID',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _userFilter = value;
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Screen',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Filter by screen name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _screenFilter = value;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

