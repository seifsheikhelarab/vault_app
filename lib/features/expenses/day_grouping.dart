import 'package:flutter/material.dart' show DateUtils;

import '../../core/format/date_labels.dart';
import '../../data/db/vault_database.dart';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Short human date used by the capture sheet's date picker button.
String formatFullDate(DateTime d) =>
    '${weekdaysShort[d.weekday - 1]}, ${d.day} ${monthsShort[d.month - 1]} ${d.year}';

/// List-section header for a day bucket: Today/Yesterday, else
/// `"Wed, 19 Aug"` (with the year when it differs from the current one).
String formatDayHeader(DateTime day) {
  final today = _dateOnly(DateTime.now());
  final target = _dateOnly(day);
  final diff = today.difference(target).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  final base = '${weekdaysShort[target.weekday - 1]}, '
      '${target.day} ${monthsShort[target.month - 1]}';
  return target.year == today.year ? base : '$base ${target.year}';
}

/// Consecutive-day slice of the expense page: rows arrive newest-first, so
/// each group holds one local calendar day and its running total.
class ExpenseDayGroup {
  ExpenseDayGroup({required this.day, required this.rows});

  /// Local midnight of the covered day.
  final DateTime day;
  final List<ExpenseRow> rows;

  int get totalMinor =>
      rows.fold(0, (sum, row) => sum + row.amountMinor);
}

/// Groups a newest-first page into day buckets. Rows sharing a local date
/// land in the same group regardless of how many pages fed them.
List<ExpenseDayGroup> groupByDay(List<ExpenseRow> rows) {
  final groups = <ExpenseDayGroup>[];
  for (final row in rows) {
    final day = DateUtils.dateOnly(row.occurredAt.toLocal());
    if (groups.isNotEmpty && DateUtils.dateOnly(groups.last.day) == day) {
      groups.last.rows.add(row);
    } else {
      groups.add(ExpenseDayGroup(day: day, rows: [row]));
    }
  }
  return groups;
}
