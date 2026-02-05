import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/core/utils/date_utils.dart' as app_date_utils;
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/domain/use_cases/sort_students_alphabetically.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/subject_providers.dart';
import 'package:charis_student_care/presentation/providers/test_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/widgets/searchable_dropdown.dart';

const List<String> _modeOptions = ['Full-time', 'Hybrid'];
const List<String?> _academicYearOptions = [null, 'Year 1', 'Year 2', 'Year 3'];

/// Test row edit data class to track unsaved changes
class _TestRowEdit {
  _TestRowEdit({
    this.subjectId,
    this.score = 0,
    this.label,
  });

  int? subjectId;
  int score;
  String? label;

  bool get passed => score >= 70;
}

/// Tests Entry screen: table-based layout for managing student test scores
class TestsScreen extends ConsumerStatefulWidget {
  const TestsScreen({super.key});

  @override
  ConsumerState<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends ConsumerState<TestsScreen> {
  String _selectedMode = 'Full-time';
  String? _academicYear = 'Year 1'; // Default to Year 1
  String _searchQuery = '';
  int? _bulkSubjectId;
  DateTime? _selectedDate; // Date filter for tests

  // Edit tracking
  final Map<int, _TestRowEdit> _edits = {};
  final Map<String, TextEditingController> _controllers = {};

  // Memoization for filtered/sorted lists
  List<Student>? _cachedFilteredStudents;
  String _lastFilterKey = '';

  // Test data cache
  Map<int, Test>? _cachedTests;

  // Debouncing for text input
  final Map<String, Timer> _debounceTimers = {};

  // Infinite scroll state
  int _displayedCount = 25;
  bool _isLoadingMore = false;

  TestDataSource? _dataSource;

  @override
  void dispose() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _loadMore() {
    if (_isLoadingMore) return;
    
    // Check if we have more items to load
    final allFilteredStudents = _cachedFilteredStudents;
    if (allFilteredStudents == null) return;
    
    final total = allFilteredStudents.length;
    if (_displayedCount >= total) return; // Already showing all items
    
    setState(() {
      _isLoadingMore = true;
      _displayedCount = (_displayedCount + 25).clamp(0, total);
      _isLoadingMore = false;
    });
  }

  void _debouncedUpdate(String key, void Function() update,
      {Duration delay = const Duration(milliseconds: 300)}) {
    _debounceTimers[key]?.cancel();
    _debounceTimers[key] = Timer(delay, () {
      update();
      _debounceTimers.remove(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final studentsAsync = ref.watch(studentsStreamProvider('Active'));
    final allTestsAsync = ref.watch(allTestsProvider);

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Text(
            'Tests Entry',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 24,
              fontFamily: 'Questrial',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Manage and record student test scores and assignment submission status for various courses.',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
              fontFamily: 'Questrial',
            ),
          ),
          const SizedBox(height: 24),

          // Filters and bulk actions
          _buildFiltersAndBulkActions(colorScheme, redColor),
          const SizedBox(height: 16),

          // Section title
          Text(
            'Student Test Results',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 18,
              fontFamily: 'Questrial',
            ),
          ),
          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              FilledButton.icon(
                onPressed: _hasUnsavedChanges() ? _saveAllChanges : null,
                icon: const Icon(Icons.save, size: 20),
                label: const Text('Save All Changes'),
                style: FilledButton.styleFrom(
                  backgroundColor: redColor,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                hint: const Text('Bulk Actions'),
                items: const [
                  DropdownMenuItem(
                      value: 'export', child: Text('Export to CSV')),
                ],
                onChanged: (value) {
                  if (value == 'export') {
                    _exportCsv(context);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Table
          Expanded(
            child: studentsAsync.when(
              data: (allStudents) {
                // Filter and sort students
                final dateKey = _selectedDate != null
                    ? app_date_utils.DateUtils.formatIsoDate(_selectedDate!)
                    : 'all';
                final filterKey =
                    '$_selectedMode|$_academicYear|$_searchQuery|$dateKey|$_bulkSubjectId';
                if (_cachedFilteredStudents == null ||
                    _lastFilterKey != filterKey) {
                  final searchQueryLower = _searchQuery.toLowerCase();
                  final filtered = allStudents.where((s) {
                    if (s.mode != _selectedMode) return false;
                    if (_academicYear != null && s.year != _academicYear)
                      return false;
                    if (searchQueryLower.isNotEmpty) {
                      if (!s.surname.toLowerCase().contains(searchQueryLower) &&
                          !s.firstName
                              .toLowerCase()
                              .contains(searchQueryLower) &&
                          !(s.email?.toLowerCase().contains(searchQueryLower) ??
                              false)) {
                        return false;
                      }
                    }
                    return true;
                  }).toList();
                  _cachedFilteredStudents =
                      sortStudentsAlphabetically(filtered);
                  _lastFilterKey = filterKey;
                  // Reset displayed count when filters change
                  _displayedCount = 25;
                }

                final allFilteredStudents = _cachedFilteredStudents!;
                final total = allFilteredStudents.length;
                if (_displayedCount > total) {
                  _displayedCount = total;
                }
                final displayedStudents = allFilteredStudents.sublist(
                    0, _displayedCount.clamp(0, total));

                // Load tests for displayed students
                return allTestsAsync.when(
                  data: (allTests) {
                    // Filter tests by subject and date if filters are active
                    var filteredTests = allTests;
                    
                    // Filter by subject if bulk subject is selected
                    if (_bulkSubjectId != null) {
                      filteredTests = filteredTests
                          .where((test) => test.subjectId == _bulkSubjectId)
                          .toList();
                    }
                    
                    // Filter by date if date filter is active
                    if (_selectedDate != null) {
                      final selectedDateOnly = DateTime(
                        _selectedDate!.year,
                        _selectedDate!.month,
                        _selectedDate!.day,
                      );
                      filteredTests = filteredTests.where((test) {
                        // Use updatedAt if available, otherwise createdAt
                        final testDate = test.updatedAt ?? test.createdAt;
                        final testDateOnly = DateTime(
                          testDate.year,
                          testDate.month,
                          testDate.day,
                        );
                        return testDateOnly.isAtSameMomentAs(selectedDateOnly);
                      }).toList();
                    }
                    
                    // Build test map (latest test per student for the selected subject)
                    final testMap = <int, Test>{};
                    for (final test in filteredTests) {
                      // If bulk subject is selected, prioritize tests matching that subject
                      // Otherwise, use the most recent test per student
                      if (_bulkSubjectId != null) {
                        // For bulk subject, only include tests matching that subject
                        if (test.subjectId == _bulkSubjectId) {
                          if (!testMap.containsKey(test.studentId) ||
                              (test.updatedAt ?? test.createdAt)
                                  .isAfter(testMap[test.studentId]!
                                      .updatedAt ??
                                      testMap[test.studentId]!.createdAt)) {
                            testMap[test.studentId] = test;
                          }
                        }
                      } else {
                        // No bulk subject selected - use most recent test per student
                        if (!testMap.containsKey(test.studentId) ||
                            (test.updatedAt ?? test.createdAt)
                                .isAfter(testMap[test.studentId]!
                                    .updatedAt ??
                                    testMap[test.studentId]!.createdAt)) {
                          testMap[test.studentId] = test;
                        }
                      }
                    }
                    _cachedTests = testMap;

                    // Initialize edits if needed
                    _initializeEdits(displayedStudents, testMap);

                    // Build data source
                    _dataSource ??= TestDataSource(
                      students: displayedStudents,
                      testMap: testMap,
                      edits: _edits,
                      controllers: _controllers,
                      colorScheme: colorScheme,
                      isDark: isDark,
                      redColor: redColor,
                      onSubjectChanged: (studentId, subjectId) {
                        _onSubjectChanged(studentId, subjectId);
                      },
                      onScoreChanged: (studentId, score) {
                        setState(() {
                          _edits[studentId] ??= _TestRowEdit();
                          _edits[studentId]!.score = score;
                        });
                      },
                      onLabelChanged: (studentId, label) {
                        setState(() {
                          _edits[studentId] ??= _TestRowEdit();
                          _edits[studentId]!.label = label;
                        });
                      },
                      ref: ref,
                    );
                    _dataSource!.updateData(displayedStudents, testMap, _edits);

                    if (displayedStudents.isEmpty) {
                      return Center(
                        child: Text(
                          'No students found.',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 14,
                            fontFamily: 'Questrial',
                          ),
                        ),
                      );
                    }

                    return RepaintBoundary(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollUpdateNotification) {
                            final metrics = notification.metrics;
                            // Load more when scrolled 80% down
                            if (metrics.pixels >= metrics.maxScrollExtent * 0.8) {
                              _loadMore();
                            }
                          }
                          return false;
                        },
                        child: SfDataGrid(
                          source: _dataSource!,
                          columnWidthMode: ColumnWidthMode.fill,
                          gridLinesVisibility: GridLinesVisibility.horizontal,
                          headerGridLinesVisibility: GridLinesVisibility.both,
                          columns: [
                            GridColumn(
                              columnName: 'studentName',
                              width: 200,
                              label: _buildHeader('Student Name', colorScheme),
                            ),
                            GridColumn(
                              columnName: 'subject',
                              width: 250,
                              label: _buildHeader('Subject', colorScheme),
                            ),
                            GridColumn(
                              columnName: 'score',
                              width: 100,
                              label: _buildHeader('Score', colorScheme),
                            ),
                            GridColumn(
                              columnName: 'passed',
                              width: 100,
                              label: _buildHeader('Passed', colorScheme),
                            ),
                            GridColumn(
                              columnName: 'notes',
                              width: double.nan,
                              label: _buildHeader('Notes', colorScheme),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(
                    child: Text(
                      'Error loading tests: $err',
                      style: TextStyle(color: colorScheme.error, fontSize: 14),
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(
                  'Error loading students: $err',
                  style: TextStyle(color: colorScheme.error, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(String text, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          fontFamily: 'Questrial',
        ),
      ),
    );
  }

  Widget _buildFiltersAndBulkActions(ColorScheme colorScheme, Color redColor) {
    return Column(
      children: [
        Row(
          children: [
            _buildModeToggle(colorScheme, redColor),
            const SizedBox(width: 16),
            _buildAcademicYearDropdown(colorScheme),
            const SizedBox(width: 16),
            _buildDateFilter(colorScheme),
            const SizedBox(width: 16),
            Expanded(
              child: TextField(
                onChanged: (v) {
                  _debouncedUpdate('search', () {
                    if (mounted) {
                      setState(() {
                        _searchQuery = v;
                        _displayedCount = 25;
                        _cachedFilteredStudents = null;
                      });
                    }
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search students...',
                  hintStyle: TextStyle(
                      color: colorScheme.onSurfaceVariant, fontSize: 14),
                  prefixIcon: Icon(Icons.search,
                      color: colorScheme.onSurfaceVariant, size: 22),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Bulk subject selector
        Row(
          children: [
            const Text(
              'Apply Subject to All Filtered:',
              style: TextStyle(
                fontSize: 14,
                fontFamily: 'Questrial',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildBulkSubjectSelector(colorScheme),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _bulkSubjectId != null ? _applyBulkSubject : null,
              style: FilledButton.styleFrom(
                backgroundColor: redColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              child: const Text('Apply to All Filtered'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModeToggle(ColorScheme colorScheme, Color redColor) {
    return ToggleButtons(
      constraints: const BoxConstraints(minWidth: 90, minHeight: 44),
      borderRadius: BorderRadius.circular(8),
      fillColor: redColor,
      selectedColor: AppColors.charisWhite,
      color: colorScheme.onSurface,
      isSelected: _modeOptions.map((m) => m == _selectedMode).toList(),
      onPressed: (index) {
        setState(() {
          _selectedMode = _modeOptions[index];
          _cachedFilteredStudents = null;
          _displayedCount = 25;
        });
      },
      children: _modeOptions
          .map((l) => Text(l,
              style: const TextStyle(fontFamily: 'Questrial', fontSize: 14)))
          .toList(),
    );
  }

  Widget _buildAcademicYearDropdown(ColorScheme colorScheme) {
    return SizedBox(
      width: 120,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outline),
        ),
        child: DropdownButton<String?>(
          value: _academicYear,
          hint: Text('All',
              style:
                  TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
          isExpanded: true,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(8),
          items: _academicYearOptions
              .map((y) => DropdownMenuItem<String?>(
                    value: y,
                    child: Text(y ?? 'All',
                        style: TextStyle(
                            color: colorScheme.onSurface, fontSize: 14)),
                  ))
              .toList(),
          onChanged: (v) {
            setState(() {
              _academicYear = v;
              _cachedFilteredStudents = null;
              _displayedCount = 25;
            });
          },
        ),
      ),
    );
  }

  Widget _buildDateFilter(ColorScheme colorScheme) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _selectedDate ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null && mounted) {
          setState(() {
            _selectedDate = picked;
            _cachedFilteredStudents = null;
            _displayedCount = 25;
          });
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _selectedDate != null
                  ? app_date_utils.DateUtils.formatDisplayDate(_selectedDate!)
                  : 'All dates',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
            if (_selectedDate != null) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedDate = null;
                    _cachedFilteredStudents = null;
                    _displayedCount = 25;
                  });
                },
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              const SizedBox(width: 8),
              Icon(
                Icons.calendar_today,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBulkSubjectSelector(ColorScheme colorScheme) {
    // Get all subjects from all years
    final allSubjectsAsync = ref.watch(subjectsForYearStreamProvider('Year 1'));

    return allSubjectsAsync.when(
      data: (year1Subjects) {
        final year2Async = ref.watch(subjectsForYearStreamProvider('Year 2'));
        final year3Async = ref.watch(subjectsForYearStreamProvider('Year 3'));

        return year2Async.when(
          data: (year2Subjects) {
            return year3Async.when(
              data: (year3Subjects) {
                final allSubjects = [
                  ...year1Subjects,
                  ...year2Subjects,
                  ...year3Subjects
                ];
                final subjectMap = {for (final s in allSubjects) s.id: s};

                return SearchableDropdown<int>(
                  key: const ValueKey('bulk_subject_selector'),
                  items: allSubjects.map((s) => s.id).toList(),
                  selectedValue: _bulkSubjectId,
                  hint: 'Select subject...',
                  searchHint: 'Search subjects...',
                  itemBuilder: (context, subjectId) {
                    final subject = subjectMap[subjectId];
                    return Text(
                      subject != null
                          ? '${subject.name} (${subject.year})'
                          : 'Unknown',
                      style: const TextStyle(
                        color: AppColors.charisBlack,
                        fontSize: 14,
                        fontFamily: 'Questrial',
                      ),
                    );
                  },
                  displayTextBuilder: (subjectId) {
                    final subject = subjectMap[subjectId];
                    return subject != null
                        ? '${subject.name} (${subject.year})'
                        : 'Unknown';
                  },
                  searchFilter: (subjectId, query) {
                    final subject = subjectMap[subjectId];
                    if (subject == null) return false;
                    return subject.name
                            .toLowerCase()
                            .contains(query.toLowerCase()) ||
                        subject.year
                            .toLowerCase()
                            .contains(query.toLowerCase());
                  },
                  onChanged: (value) {
                    setState(() {
                      _bulkSubjectId = value;
                      if (value != null) {
                        final subject = subjectMap[value];
                        if (subject != null) {
                          _academicYear = subject.year; // Auto-filter by year
                        }
                      }
                      _cachedFilteredStudents = null; // Reset cache
                      _displayedCount = 25; // Reset scroll
                    });
                  },
                );
              },
              loading: () => const SizedBox(
                  height: 44,
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 2))),
              error: (_, __) => const SizedBox(),
            );
          },
          loading: () => const SizedBox(
              height: 44,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          error: (_, __) => const SizedBox(),
        );
      },
      loading: () => const SizedBox(
          height: 44,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (_, __) => const SizedBox(),
    );
  }

  void _initializeEdits(List<Student> students, Map<int, Test> testMap) {
    for (final student in students) {
      if (!_edits.containsKey(student.id)) {
        final test = testMap[student.id];
        _edits[student.id] = _TestRowEdit(
          subjectId: test?.subjectId,
          score: test?.score ?? 0,
          label: test?.label,
        );
      }

      // Initialize controllers
      final scoreKey = '${student.id}_score';
      final labelKey = '${student.id}_label';
      if (!_controllers.containsKey(scoreKey)) {
        _controllers[scoreKey] = TextEditingController(
            text: (_edits[student.id]?.score ?? 0).toString());
      }
      if (!_controllers.containsKey(labelKey)) {
        _controllers[labelKey] =
            TextEditingController(text: _edits[student.id]?.label ?? '');
      }
    }
  }

  /// Finds the most appropriate test for a student+subject combination,
  /// respecting the date filter if provided.
  /// Returns null if no matching test is found.
  Test? _findTestForStudentAndSubject(
    List<Test> allTests,
    int studentId,
    int subjectId,
    DateTime? selectedDate,
  ) {
    // Filter tests matching student and subject
    var matchingTests = allTests
        .where((test) =>
            test.studentId == studentId && test.subjectId == subjectId)
        .toList();

    if (matchingTests.isEmpty) return null;

    // Apply date filter if provided
    if (selectedDate != null) {
      final selectedDateOnly = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      );
      matchingTests = matchingTests.where((test) {
        final testDate = test.updatedAt ?? test.createdAt;
        final testDateOnly = DateTime(
          testDate.year,
          testDate.month,
          testDate.day,
        );
        return testDateOnly.isAtSameMomentAs(selectedDateOnly);
      }).toList();

      // If date filter applied and no matches, return null
      if (matchingTests.isEmpty) return null;
    }

    // Sort by updatedAt (or createdAt) descending and return most recent
    matchingTests.sort((a, b) {
      final aDate = a.updatedAt ?? a.createdAt;
      final bDate = b.updatedAt ?? b.createdAt;
      return bDate.compareTo(aDate);
    });

    return matchingTests.first;
  }

  void _onSubjectChanged(int studentId, int? subjectId) {
    setState(() {
      _edits[studentId] ??= _TestRowEdit();
      _edits[studentId]!.subjectId = subjectId;
      
      // Load existing test data for this student+subject combination
      if (subjectId != null) {
        final allTestsAsync = ref.read(allTestsProvider);
        allTestsAsync.whenData((allTests) {
          // Find test respecting date filter
          final test = _findTestForStudentAndSubject(
            allTests,
            studentId,
            subjectId,
            _selectedDate,
          );
          
          if (!mounted) return;
          
          setState(() {
            if (test != null) {
              _edits[studentId]!.score = test.score;
              _edits[studentId]!.label = test.label;
              
              // Update controllers
              final scoreKey = '${studentId}_score';
              if (!_controllers.containsKey(scoreKey)) {
                _controllers[scoreKey] = TextEditingController();
              }
              _controllers[scoreKey]!.text = test.score.toString();
              
              final labelKey = '${studentId}_label';
              if (!_controllers.containsKey(labelKey)) {
                _controllers[labelKey] = TextEditingController();
              }
              _controllers[labelKey]!.text = test.label ?? '';
              
              // Update cached test map
              if (_cachedTests != null) {
                _cachedTests![studentId] = test;
              }
            } else {
              // No test found - reset to defaults
              _edits[studentId]!.score = 0;
              _edits[studentId]!.label = null;
              
              final scoreKey = '${studentId}_score';
              if (!_controllers.containsKey(scoreKey)) {
                _controllers[scoreKey] = TextEditingController();
              }
              _controllers[scoreKey]!.text = '0';
              
              final labelKey = '${studentId}_label';
              if (!_controllers.containsKey(labelKey)) {
                _controllers[labelKey] = TextEditingController();
              }
              _controllers[labelKey]!.text = '';
              
              // Remove from cache if no test found
              if (_cachedTests != null) {
                _cachedTests!.remove(studentId);
              }
            }
          });
          
          // Update data source after state update completes
          // Use post-frame callback to ensure DataGrid rebuilds properly
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            
            if (_dataSource != null && _cachedTests != null) {
              // Get current displayed students from cached filtered students
              final students = _cachedFilteredStudents ?? [];
              final total = students.length;
              final displayedCount = _displayedCount.clamp(0, total);
              final displayedStudents = students.sublist(0, displayedCount);
              
              _dataSource!.updateData(
                displayedStudents,
                _cachedTests!,
                _edits,
              );
            }
          });
        });
      } else {
        // Subject cleared - reset to defaults
        _edits[studentId]!.score = 0;
        _edits[studentId]!.label = null;
        
        // Update data source immediately
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          
          if (_dataSource != null && _cachedTests != null) {
            final students = _cachedFilteredStudents ?? [];
            final total = students.length;
            final displayedCount = _displayedCount.clamp(0, total);
            final displayedStudents = students.sublist(0, displayedCount);
            
            _dataSource!.updateData(
              displayedStudents,
              _cachedTests!,
              _edits,
            );
          }
        });
      }
    });
  }

  bool _hasUnsavedChanges() {
    if (_cachedTests == null) return false;
    for (final entry in _edits.entries) {
      final studentId = entry.key;
      final edit = entry.value;
      final test = _cachedTests![studentId];

      final dbSubjectId = test?.subjectId;
      final dbScore = test?.score ?? 0;
      final dbLabel = test?.label;

      if (edit.subjectId != dbSubjectId ||
          edit.score != dbScore ||
          edit.label != dbLabel) {
        return true;
      }
    }
    return false;
  }

  Future<void> _applyBulkSubject() async {
    if (_bulkSubjectId == null) return;

    final students = _cachedFilteredStudents ?? [];
    if (students.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No students to update')),
        );
      }
      return;
    }

    // Load test data for all students
    final allTestsAsync = ref.read(allTestsProvider);
    allTestsAsync.whenData((allTests) {
      setState(() {
        for (final student in students) {
          // Find test for this student+subject+date combination
          final test = _findTestForStudentAndSubject(
            allTests,
            student.id,
            _bulkSubjectId!,
            _selectedDate,
          );

          // Update edits with loaded test data or defaults
          _edits[student.id] ??= _TestRowEdit(
            subjectId: _bulkSubjectId,
            score: test?.score ?? 0,
            label: test?.label,
          );
          _edits[student.id]!.subjectId = _bulkSubjectId;
          if (test != null) {
            _edits[student.id]!.score = test.score;
            _edits[student.id]!.label = test.label;
          }

          // Update controllers
          final scoreKey = '${student.id}_score';
          if (!_controllers.containsKey(scoreKey)) {
            _controllers[scoreKey] = TextEditingController();
          }
          _controllers[scoreKey]!.text = (test?.score ?? 0).toString();

          final labelKey = '${student.id}_label';
          if (!_controllers.containsKey(labelKey)) {
            _controllers[labelKey] = TextEditingController();
          }
          _controllers[labelKey]!.text = test?.label ?? '';

          // Update cached test map
          if (_cachedTests != null) {
            if (test != null) {
              _cachedTests![student.id] = test;
            } else {
              // Remove from cache if no test found
              _cachedTests!.remove(student.id);
            }
          }
        }

      });
      
      // Update data source after state update completes
      // Use post-frame callback to ensure DataGrid rebuilds properly
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        
        if (_dataSource != null && _cachedTests != null) {
          final total = students.length;
          final displayedCount = _displayedCount.clamp(0, total);
          final displayedStudents = students.sublist(0, displayedCount);
          
          _dataSource!.updateData(
            displayedStudents,
            _cachedTests!,
            _edits,
          );
        }
      });
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Subject applied to ${students.length} student(s). Click "Save All Changes" to save.',
          ),
        ),
      );
    }
  }

  Future<void> _saveAllChanges() async {
    if (_cachedTests == null) return;

    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('You must be logged in to save changes')),
        );
      }
      return;
    }

    try {
      final repo = ref.read(testRepositoryProvider);
      int savedCount = 0;

      // Only save entries that have changed
      for (final entry in _edits.entries) {
        final studentId = entry.key;
        final edit = entry.value;
        final test = _cachedTests![studentId];

        final dbSubjectId = test?.subjectId;
        final dbScore = test?.score ?? 0;
        final dbLabel = test?.label;

        // Check if any value has changed
        final hasChanges = edit.subjectId != dbSubjectId ||
            edit.score != dbScore ||
            edit.label != dbLabel;

        if (!hasChanges) continue;

        if (test != null) {
          // Update existing test
          await repo.updateTest(
            test.id,
            score: edit.score,
            label: edit.label,
            subjectId: edit.subjectId,
            userRole: auth.role,
            userId: auth.user.id,
          );
        } else {
          // Create new test
          await repo.addTest(
            studentId,
            edit.score,
            label: edit.label,
            subjectId: edit.subjectId,
            userRole: auth.role,
            userId: auth.user.id,
          );
        }
        savedCount++;
      }

      if (savedCount == 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No changes to save')),
          );
        }
        return;
      }

      // Invalidate cache to reload
      setState(() {
        _cachedTests = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Successfully saved $savedCount test record(s)')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving tests: $e')),
        );
      }
    }
  }

  void _exportCsv(BuildContext context) {
    final rows = <String>[];
    final header = ['Student Name', 'Subject', 'Score', 'Passed', 'Notes'];
    rows.add(header.join(','));

    final students = _cachedFilteredStudents ?? [];
    final testMap = _cachedTests ?? {};

    // This is a simplified export - in a real implementation, you'd fetch all subjects
    for (final entry in _edits.entries) {
      final studentId = entry.key;
      final edit = entry.value;
      final student = students.firstWhere((s) => s.id == studentId,
          orElse: () => students.first);
      final test = testMap[studentId];
      final subjectId = edit.subjectId ?? test?.subjectId;

      final name = '${student.surname}, ${student.firstName}';
      final subjectName = subjectId != null ? 'Subject $subjectId' : '';
      final score = edit.score.toString();
      final passed = edit.passed ? 'Passed' : 'Failed';
      final notes = edit.label ?? test?.label ?? '';

      rows.add([
        '"$name"',
        '"$subjectName"',
        score,
        passed,
        '"$notes"',
      ].join(','));
    }

    final csv = rows.join('\n');
    if (mounted) {
      Clipboard.setData(ClipboardData(text: csv));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Exported ${rows.length - 1} rows to clipboard')),
      );
    }
  }
}

/// Data source for the tests table
class TestDataSource extends DataGridSource {
  TestDataSource({
    required List<Student> students,
    required Map<int, Test> testMap,
    required Map<int, _TestRowEdit> edits,
    required Map<String, TextEditingController> controllers,
    required ColorScheme colorScheme,
    required bool isDark,
    required Color redColor,
    required void Function(int studentId, int? subjectId) onSubjectChanged,
    required void Function(int studentId, int score) onScoreChanged,
    required void Function(int studentId, String? label) onLabelChanged,
    required WidgetRef ref,
  })  : _students = students,
        _testMap = testMap,
        _edits = edits,
        _controllers = controllers,
        _colorScheme = colorScheme,
        _isDark = isDark,
        _redColor = redColor,
        _onSubjectChanged = onSubjectChanged,
        _onScoreChanged = onScoreChanged,
        _onLabelChanged = onLabelChanged,
        _ref = ref {
    _buildRows();
  }

  List<Student> _students;
  Map<int, Test> _testMap;
  Map<int, _TestRowEdit> _edits;
  Map<String, TextEditingController> _controllers;
  ColorScheme _colorScheme;
  bool _isDark;
  Color _redColor;
  void Function(int studentId, int? subjectId) _onSubjectChanged;
  void Function(int studentId, int score) _onScoreChanged;
  void Function(int studentId, String? label) _onLabelChanged;
  WidgetRef _ref;

  List<DataGridRow> _dataGridRows = [];

  void updateData(List<Student> students, Map<int, Test> testMap,
      Map<int, _TestRowEdit> edits) {
    _students = students;
    _testMap = testMap;
    _edits = edits;
    _buildRows();
    notifyListeners();
  }

  void _buildRows() {
    _dataGridRows = _students.map((student) {
      final test = _testMap[student.id];
      final edit = _edits[student.id] ??
          _TestRowEdit(
            subjectId: test?.subjectId,
            score: test?.score ?? 0,
            label: test?.label,
          );

      return DataGridRow(cells: [
        DataGridCell<String>(
            columnName: 'studentName',
            value: '${student.surname}, ${student.firstName}'),
        DataGridCell<int?>(
            columnName: 'subject', value: edit.subjectId ?? test?.subjectId),
        DataGridCell<int>(columnName: 'score', value: edit.score),
        DataGridCell<bool>(columnName: 'passed', value: edit.passed),
        DataGridCell<String?>(
            columnName: 'notes', value: edit.label ?? test?.label),
        DataGridCell<Student>(columnName: 'student', value: student),
      ]);
    }).toList();
  }

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final student = row
        .getCells()
        .firstWhere((c) => c.columnName == 'student')
        .value as Student;
    final test = _testMap[student.id];
    final edit = _edits[student.id] ??
        _TestRowEdit(
          subjectId: test?.subjectId,
          score: test?.score ?? 0,
          label: test?.label,
        );

    return DataGridRowAdapter(
      cells: row.getCells()
          .where((cell) => cell.columnName != 'student')
          .map((cell) {
        switch (cell.columnName) {
          case 'studentName':
            return _buildCell(
              Text(
                cell.value as String,
                style: TextStyle(
                  color: _colorScheme.onSurface,
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
            );
          case 'subject':
            return _buildCell(_buildSubjectDropdown(
                student, edit.subjectId ?? test?.subjectId));
          case 'score':
            return _buildCell(_buildScoreField(student, edit.score));
          case 'passed':
            return _buildCell(_buildPassedBadge(edit.passed));
          case 'notes':
            return _buildCell(
                _buildNotesField(student, edit.label ?? test?.label));
          default:
            return _buildCell(const SizedBox());
        }
      }).toList(),
    );
  }

  Widget _buildCell(Widget child) {
    return Container(
      padding: const EdgeInsets.all(8),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  Widget _buildSubjectDropdown(Student student, int? currentSubjectId) {
    // Get subjects for student's year
    final year = student.year ?? 'Year 1';
    final subjectsAsync = _ref.watch(subjectsForYearStreamProvider(year));

    return subjectsAsync.when(
      data: (subjects) {
        final subjectMap = {for (final s in subjects) s.id: s};

        return SearchableDropdown<int>(
          key: ValueKey('subject_${student.id}'),
          items: subjects.map((s) => s.id).toList(),
          selectedValue: currentSubjectId,
          hint: 'Select subject...',
          searchHint: 'Search subjects...',
          itemBuilder: (context, subjectId) {
            final subject = subjectMap[subjectId];
            return Text(
              subject?.name ?? 'Unknown',
              style: const TextStyle(
                color: AppColors.charisBlack,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            );
          },
          displayTextBuilder: (subjectId) {
            final subject = subjectMap[subjectId];
            return subject?.name ?? 'Unknown';
          },
          searchFilter: (subjectId, query) {
            final subject = subjectMap[subjectId];
            return subject?.name.toLowerCase().contains(query.toLowerCase()) ??
                false;
          },
          onChanged: (value) {
            _onSubjectChanged(student.id, value);
          },
        );
      },
      loading: () => const SizedBox(
          height: 32,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
      error: (_, __) => const SizedBox(),
    );
  }

  Widget _buildScoreField(Student student, int currentScore) {
    final key = '${student.id}_score';
    final controller = _controllers[key] ??=
        TextEditingController(text: currentScore.toString());

    return SizedBox(
      width: 80,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          hintText: '0',
          hintStyle:
              TextStyle(color: _colorScheme.onSurfaceVariant, fontSize: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _colorScheme.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _colorScheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _redColor, width: 2),
          ),
          filled: true,
          fillColor: _isDark ? AppColors.surfaceDark : AppColors.charisWhite,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          isDense: true,
        ),
        style: TextStyle(color: _colorScheme.onSurface, fontSize: 13),
        onChanged: (v) {
          final n = int.tryParse(v);
          if (n != null && n >= 0 && n <= 100) {
            _onScoreChanged(student.id, n);
          }
        },
      ),
    );
  }

  Widget _buildPassedBadge(bool passed) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: passed
            ? _colorScheme.primaryContainer.withValues(alpha: 0.5)
            : _colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        passed ? 'Passed' : 'Failed',
        style: TextStyle(
          color: passed
              ? _colorScheme.onPrimaryContainer
              : _colorScheme.onErrorContainer,
          fontSize: 12,
          fontFamily: 'Questrial',
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildNotesField(Student student, String? currentLabel) {
    final key = '${student.id}_label';
    final controller =
        _controllers[key] ??= TextEditingController(text: currentLabel ?? '');

    return TextField(
      controller: controller,
      maxLines: 2,
      decoration: InputDecoration(
        hintText: 'Enter notes...',
        hintStyle:
            TextStyle(color: _colorScheme.onSurfaceVariant, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _redColor, width: 2),
        ),
        filled: true,
        fillColor: _isDark ? AppColors.surfaceDark : AppColors.charisWhite,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        isDense: true,
      ),
      style: TextStyle(color: _colorScheme.onSurface, fontSize: 13),
      onChanged: (v) {
        _onLabelChanged(student.id, v.isEmpty ? null : v);
      },
    );
  }
}
