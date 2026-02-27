import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/core/utils/currency_utils.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';

/// Read-only dialog showing student details and placeholder rows for
/// attendance, tests, ministry hours, and balance.
class StudentDetailDialog extends ConsumerWidget {
  const StudentDetailDialog({super.key, required this.student});

  final Student student;

  static Future<void> show(
      {required BuildContext context, required Student student,}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => StudentDetailDialog(student: student),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final classAsync = student.classId != null
        ? ref.watch(classByIdProvider(student.classId!))
        : const AsyncValue<SchoolClass?>.data(null);
    final yearLabel = classAsync.valueOrNull?.name ?? '—';
    return Dialog(
      backgroundColor:
          isDark ? AppColors.surfaceDarkElevated : AppColors.charisWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                children: [
                  Text(
                    'Student details',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      fontFamily: 'Questrial',
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon:
                        Icon(Icons.close, color: colorScheme.onSurfaceVariant,),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _row('Surname', student.surname, colorScheme),
                    _row('First names', student.firstName, colorScheme),
                    _row('Year', yearLabel, colorScheme),
                    _row('Mode', student.mode ?? '—', colorScheme),
                    _row('Admission year', student.admissionYear ?? '—',
                        colorScheme,),
                    _row('Status', student.status, colorScheme),
                    _row('Phone', student.contactInfo ?? '—', colorScheme),
                    _row('Email', student.email ?? '—', colorScheme),
                    const SizedBox(height: 8),
                    _checkboxRow(
                        'Handbook', student.handbook, colorScheme, redColor,),
                    _checkboxRow('Media Release', student.mediaRelease,
                        colorScheme, redColor,),
                    _checkboxRow('Accident Waiver', student.accidentWaiver,
                        colorScheme, redColor,),
                    const SizedBox(height: 16),
                    Text(
                      'Placeholder (data coming later)',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontFamily: 'Questrial',
                      ),
                    ),
                    const SizedBox(height: 8),
                    _row('Attendance %', '—', colorScheme),
                    _row('Outstanding tests', '0', colorScheme),
                    _row('Ministry hours', '0', colorScheme),
                    _row('Balance', CurrencyUtils.formatRand(0), colorScheme),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.onSurfaceVariant,
                  side: BorderSide(color: colorScheme.outline),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkboxRow(
      String label, bool value, ColorScheme colorScheme, Color redColor,) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Icon(
                  value ? Icons.check_circle : Icons.circle_outlined,
                  color: value ? redColor : colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  value ? 'Yes' : 'No',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
