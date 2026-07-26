import 'package:flutter/material.dart';

/// Shared table visuals aligned with Students screen baseline.
class AppTableStyle {
  AppTableStyle._();

  /// Syncfusion [SfDataGrid] defaults: 49px data rows, 56px header.
  static const double dataGridRowHeight = 38;
  static const double dataGridHeaderRowHeight = 36;
  /// Report grids with multi-line subject headers (e.g. Tests report tab).
  static const double dataGridMultiLineHeaderRowHeight = 72;
  /// Report grids with vertical (rotated) subject headers (e.g. Tests report tab).
  static const double dataGridVerticalHeaderRowHeight = 180;

  static const EdgeInsets headerPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 6);
  static const EdgeInsets cellPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 6);

  /// Compact Edit/Delete [TextButton]s inside grid cells.
  static ButtonStyle dataGridTextButtonStyle() {
    return TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    );
  }

  static TextStyle headerTextStyle(ColorScheme colorScheme) {
    return TextStyle(
      color: colorScheme.onSurface,
      fontWeight: FontWeight.w600,
      fontSize: 14,
      fontFamily: 'Questrial',
    );
  }

  /// Matches [dataGridBodyTextStyle] line height for grid header labels.
  static TextStyle dataGridHeaderTextStyle(ColorScheme colorScheme) {
    return TextStyle(
      color: colorScheme.onSurface,
      fontWeight: FontWeight.w600,
      fontSize: 14,
      height: 1.1,
      fontFamily: 'Questrial',
    );
  }

  static TextStyle bodyTextStyle(ColorScheme colorScheme) {
    return TextStyle(
      color: colorScheme.onSurface,
      fontSize: 14,
      fontFamily: 'Questrial',
    );
  }

  /// Tighter line height for Syncfusion [SfDataGrid] cells (default grid row is 49px otherwise).
  static TextStyle dataGridBodyTextStyle(ColorScheme colorScheme) {
    return TextStyle(
      color: colorScheme.onSurface,
      fontSize: 14,
      height: 1.1,
      fontFamily: 'Questrial',
    );
  }

  static Widget sfHeaderCell(
    BuildContext context,
    String text, {
    Alignment alignment = Alignment.centerLeft,
    bool compactLineHeight = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: headerPadding,
      alignment: alignment,
      color: colorScheme.surfaceContainerHighest,
      child: Text(
        text,
        style: compactLineHeight
            ? dataGridHeaderTextStyle(colorScheme)
            : headerTextStyle(colorScheme),
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  static TableBorder materialTableBorder(ColorScheme colorScheme) {
    return TableBorder.all(color: colorScheme.outlineVariant);
  }

  static BoxDecoration materialTableContainerDecoration(ColorScheme colorScheme) {
    return BoxDecoration(
      color: colorScheme.surface,
      border: Border.all(color: colorScheme.outlineVariant),
    );
  }

  static WidgetStateProperty<Color?> dataTableHeadingColor(ColorScheme colorScheme) {
    return WidgetStateProperty.all(colorScheme.surfaceContainerHighest);
  }

  static WidgetStateProperty<TextStyle?> dataTableHeadingTextStyle(ColorScheme colorScheme) {
    return WidgetStateProperty.all(headerTextStyle(colorScheme));
  }

  static WidgetStateProperty<TextStyle?> dataTableBodyTextStyle(ColorScheme colorScheme) {
    return WidgetStateProperty.all(bodyTextStyle(colorScheme));
  }

}
