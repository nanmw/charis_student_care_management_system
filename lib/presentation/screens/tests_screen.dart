import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/test_providers.dart';

/// Test score entry screen: list of active students with their tests and "Add test" action.
class TestsScreen extends ConsumerWidget {
  const TestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final studentsAsync = ref.watch(studentsStreamProvider('Active'));

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Test Scores',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 24,
              fontFamily: 'Questrial',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter and view test scores (0–100). Pass = 70+. Outstanding = count of scores below 70.',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
              fontFamily: 'Questrial',
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: studentsAsync.when(
              data: (students) {
                if (students.isEmpty) {
                  return Center(
                    child: Text(
                      'No active students.',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontFamily: 'Questrial',
                      ),
                    ),
                  );
                }
                return RepaintBoundary(
                  child: ListView.builder(
                    itemCount: students.length,
                    itemBuilder: (context, index) {
                      final student = students[index];
                      return _StudentTestCard(
                        studentId: student.id,
                        studentName: '${student.surname}, ${student.firstName}',
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(
                  'Error loading students: $err',
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
}

class _StudentTestCard extends ConsumerWidget {
  const _StudentTestCard({
    required this.studentId,
    required this.studentName,
  });

  final int studentId;
  final String studentName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final testsAsync = ref.watch(testsForStudentProvider(studentId));
    final auth = ref.watch(authStateProvider).valueOrNull;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    studentName,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      fontFamily: 'Questrial',
                    ),
                  ),
                ),
                if (auth is Authenticated)
                  TextButton.icon(
                    onPressed: () => _showAddTestDialog(
                      context,
                      ref,
                      studentId: studentId,
                      studentName: studentName,
                      userRole: auth.role,
                      userId: auth.user.id,
                    ),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Add test'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primaryActionRed,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            testsAsync.when(
              data: (List<Test> tests) {
                if (tests.isEmpty) {
                  return Text(
                    'No tests recorded.',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                      fontFamily: 'Questrial',
                    ),
                  );
                }
                final outstanding = tests.where((t) => t.score < 70).length;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (outstanding > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Chip(
                          label: Text(
                            '$outstanding outstanding',
                            style: const TextStyle(
                              fontSize: 12,
                              fontFamily: 'Questrial',
                            ),
                          ),
                          backgroundColor: colorScheme.errorContainer,
                          labelStyle: TextStyle(
                            color: colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: tests
                          .map<Widget>(
                            (t) => _TestChip(
                              score: t.score,
                              label: t.label,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                );
              },
              loading: () => const SizedBox(
                height: 24,
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
              ),
              error: (e, _) => Text(
                'Error: $e',
                style: TextStyle(color: colorScheme.error, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestChip extends StatelessWidget {
  const _TestChip({required this.score, this.label});

  final int score;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final passed = score >= 70;
    final text = label?.trim().isNotEmpty == true ? '$label: $score' : '$score';

    return Chip(
      label: Text(
        text,
        style: const TextStyle(fontSize: 12, fontFamily: 'Questrial'),
      ),
      backgroundColor: passed
          ? colorScheme.primaryContainer.withValues(alpha: 0.5)
          : colorScheme.errorContainer.withValues(alpha: 0.5),
      labelStyle: TextStyle(
        color: passed ? colorScheme.onPrimaryContainer : colorScheme.onErrorContainer,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

Future<void> _showAddTestDialog(
  BuildContext context,
  WidgetRef ref, {
  required int studentId,
  required String studentName,
  required UserRole userRole,
  required String userId,
}) async {
  final scoreController = TextEditingController();
  final labelController = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Add test score', style: TextStyle(fontFamily: 'Questrial')),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  studentName,
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Questrial',
                      ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: scoreController,
                  decoration: const InputDecoration(
                    labelText: 'Score (0–100)',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter a score';
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 0 || n > 100) return 'Score must be 0–100';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'Label (optional)',
                    hintText: 'e.g. Quiz 1',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(true);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryActionRed,
            ),
            child: const Text('Save'),
          ),
        ],
      );
    },
  );

  if (ok == true && context.mounted) {
    final score = int.tryParse(scoreController.text.trim()) ?? 0;
    final label = labelController.text.trim().isEmpty ? null : labelController.text.trim();
    final repo = ref.read(testRepositoryProvider);
    try {
      await repo.addTest(
        studentId,
        score,
        label: label,
        userRole: userRole,
        userId: userId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test score saved.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  scoreController.dispose();
  labelController.dispose();
}
