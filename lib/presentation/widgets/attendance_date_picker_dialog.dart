import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

/// Returns true when [a] and [b] represent the same calendar day.
bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// Dialog that shows a calendar with markers on days that have attendance.
/// All days are selectable. Calls [onDateSelected] when the user picks a date and confirms.
class AttendanceDatePickerDialog extends StatefulWidget {
  const AttendanceDatePickerDialog({
    super.key,
    required this.initialDate,
    required this.datesWithAttendance,
    required this.onDateSelected,
  });

  final DateTime initialDate;
  final Set<DateTime> datesWithAttendance;
  final void Function(DateTime date) onDateSelected;

  @override
  State<AttendanceDatePickerDialog> createState() =>
      _AttendanceDatePickerDialogState();
}

class _AttendanceDatePickerDialogState extends State<AttendanceDatePickerDialog> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.initialDate;
    _selectedDay = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Select attendance date',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 8),
            TableCalendar<int>(
              firstDay: DateTime(2020),
              lastDay: DateTime(2030),
              focusedDay: _focusedDay,
              currentDay: DateTime.now(),
              selectedDayPredicate: (day) => _isSameDay(day, _selectedDay),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              onPageChanged: (focusedDay) {
                setState(() => _focusedDay = focusedDay);
              },
              eventLoader: (day) {
                final hasAttendance = widget.datesWithAttendance.any(
                    (d) => d.year == day.year && d.month == day.month && d.day == day.day,);
                return hasAttendance ? [1] : [];
              },
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, day, events) {
                  if (events.isEmpty) return null;
                  return Positioned(
                    bottom: 2,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              calendarStyle: CalendarStyle(
                selectedDecoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleTextStyle: TextStyle(
                  fontSize: 16,
                  fontFamily: 'Questrial',
                  color: colorScheme.onSurface,
                ),
                leftChevronIcon: Icon(Icons.chevron_left, color: colorScheme.onSurface),
                rightChevronIcon: Icon(Icons.chevron_right, color: colorScheme.onSurface),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Days with a dot have attendance recorded.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(fontFamily: 'Questrial')),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    widget.onDateSelected(_selectedDay);
                    Navigator.of(context).pop();
                  },
                  child: const Text('OK', style: TextStyle(fontFamily: 'Questrial')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
