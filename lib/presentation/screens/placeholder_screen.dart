import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Simple placeholder for shell routes not yet implemented.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, this.title});

  /// Optional section title (e.g. "Attendance"); defaults to "Coming soon".
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sectionName =
        title ?? _titleFromPath(GoRouterState.of(context).matchedLocation);

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.construction_outlined,
              size: 48,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              sectionName,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 20,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This section is coming soon.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _titleFromPath(String path) {
    switch (path) {
      case '/attendance':
        return 'Attendance';
      case '/ministry-hours':
        return 'Ministry Hours';
      case '/tests':
        return 'Tests';
      case '/payments':
        return 'Payments';
      case '/reports':
        return 'Reports / Export';
      default:
        return 'Coming soon';
    }
  }
}
