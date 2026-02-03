import 'package:flutter/material.dart';

/// Reusable app footer shown at the bottom of all screens for a uniform look.
class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  static const String _copyright =
      '© 2026 Charis Student Care. All rights reserved.';

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
      ),
      child: Center(
        child: Text(
          _copyright,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontFamily: 'Questrial',
          ),
        ),
      ),
    );
  }
}
