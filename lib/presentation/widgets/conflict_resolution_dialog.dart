import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';

/// Side-by-side conflict resolution dialog (Admin Level 01 only).
/// [onKeepLocal] and [onUseIncoming] are called when user chooses; dialog closes after they complete.
class ConflictResolutionDialog extends StatelessWidget {
  const ConflictResolutionDialog({
    super.key,
    required this.conflict,
    required this.onKeepLocal,
    required this.onUseIncoming,
  });

  final SyncConflict conflict;
  final Future<void> Function() onKeepLocal;
  final Future<void> Function() onUseIncoming;

  static Future<void> show(
    BuildContext context, {
    required SyncConflict conflict,
    required Future<void> Function() onKeepLocal,
    required Future<void> Function() onUseIncoming,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => ConflictResolutionDialog(
        conflict: conflict,
        onKeepLocal: onKeepLocal,
        onUseIncoming: onUseIncoming,
      ),
    );
  }

  Map<String, dynamic> _parseJson(String s) {
    try {
      return jsonDecode(s) as Map<String, dynamic>? ?? {};
    } catch (_) {
      return {'raw': s};
    }
  }

  Widget _buildJsonSection(String title, Map<String, dynamic> data, ColorScheme colorScheme) {
    final entries = data.entries.toList();
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: colorScheme.primary,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 8),
            if (entries.isEmpty)
              Text(
                '—',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12, fontFamily: 'Questrial'),
              )
            else
              ...entries.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 12,
                          fontFamily: 'Questrial',
                        ),
                        children: [
                          TextSpan(
                            text: '${e.key}: ',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          TextSpan(text: '${e.value}'),
                        ],
                      ),
                    ),
                  ),),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final local = _parseJson(conflict.localSnapshot);
    final incoming = _parseJson(conflict.incomingPayload);

    return AlertDialog(
      title: const Text('Resolve sync conflict'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${conflict.entityTable} · record ${conflict.recordId}',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildJsonSection('Your version (local)', local, colorScheme),
                const SizedBox(width: 12),
                _buildJsonSection('Incoming (other device)', incoming, colorScheme),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Device: ${conflict.sourceDeviceId}',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'Questrial',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            await onKeepLocal();
            if (context.mounted) Navigator.of(context).pop();
          },
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
          ),
          child: const Text('Keep local'),
        ),
        FilledButton(
          onPressed: () async {
            await onUseIncoming();
            if (context.mounted) Navigator.of(context).pop();
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.charisRedPrimary,
            foregroundColor: colorScheme.onPrimary,
          ),
          child: const Text('Use incoming'),
        ),
      ],
    );
  }
}
