import 'dart:math' as math;

import 'exercise_stats_period.dart';
import 'monthly_exercise_stats.dart';

const int dailyRecentSevenPeriodCount = 7;
const int dailyRecentSevenMaxOffset = dailyRecentSevenPeriodCount - 1;
const double dailyRecentSevenMaxX = 6.0;

const int weeklyRecentFivePeriodCount = 5;
const int weeklyRecentFiveMaxOffset = weeklyRecentFivePeriodCount - 1;
const double weeklyRecentFiveMaxX = 4.0;

const int monthlyMinimumPeriodCount = 5;
const int monthlyMaximumPeriodCount = 12;

/// Small x-domain padding that keeps endpoint dots/curved strokes from being
/// clipped by fl_chart while preserving integer logical tick labels.
const double weightTrendDomainPadding = 0.20;

class WeightTrendAxisWindow {
  const WeightTrendAxisWindow({
    required this.periodUnit,
    required this.origin,
    required this.periodCount,
    this.domainPadding = weightTrendDomainPadding,
  });

  final StatsPeriodUnit periodUnit;
  final DateTime origin;
  final int periodCount;
  final double domainPadding;

  int get maxOffset => math.max(0, periodCount - 1);
  double get logicalMinX => 0;
  double get logicalMaxX => maxOffset.toDouble();
  double get paddedMinX => logicalMinX - domainPadding;
  double get paddedMaxX => logicalMaxX + domainPadding;

  List<DateTime> get tickDates => [
    for (var offset = 0; offset < periodCount; offset++)
      addPeriods(origin, periodUnit, offset),
  ];

  bool containsOffset(double offset) =>
      offset >= logicalMinX && offset <= logicalMaxX;
}

/// Builds the logical x-axis for the weight trend chart.
///
/// Daily is current-date based for the recent seven days. Weekly is also
/// current-date based and always displays the current week plus the previous
/// four Monday-start weeks. Monthly is latest-data based by default, preserving
/// calendar gaps, with a minimum five-month and maximum twelve-month window.
WeightTrendAxisWindow buildWeightTrendAxisWindow({
  required StatsPeriodUnit periodUnit,
  required List<ExercisePeriodStats> stats,
  required DateTime today,
}) {
  return switch (periodUnit) {
    StatsPeriodUnit.daily => WeightTrendAxisWindow(
      periodUnit: periodUnit,
      origin: dailyRecentSevenOrigin(today),
      periodCount: dailyRecentSevenPeriodCount,
    ),
    StatsPeriodUnit.weekly => WeightTrendAxisWindow(
      periodUnit: periodUnit,
      origin: weeklyRecentFiveOrigin(today),
      periodCount: weeklyRecentFivePeriodCount,
    ),
    StatsPeriodUnit.monthly => _monthlyAxisWindow(stats),
  };
}

/// Returns the x-axis position for [periodStart] relative to [origin].
///
/// The weight trend chart must preserve real calendar distance between records.
/// Using the list index compresses missing days/weeks/months and makes the trend
/// look wrong when workouts are not recorded in consecutive periods.
double periodOffsetFrom(
  DateTime origin,
  DateTime periodStart,
  StatsPeriodUnit periodUnit,
) {
  final normalizedOrigin = periodStartFor(origin, periodUnit);
  final normalizedPeriodStart = periodStartFor(periodStart, periodUnit);

  return switch (periodUnit) {
    StatsPeriodUnit.daily =>
      normalizedPeriodStart.difference(normalizedOrigin).inDays.toDouble(),
    StatsPeriodUnit.weekly =>
      normalizedPeriodStart.difference(normalizedOrigin).inDays / 7,
    StatsPeriodUnit.monthly =>
      ((normalizedPeriodStart.year - normalizedOrigin.year) * 12 +
              normalizedPeriodStart.month -
              normalizedOrigin.month)
          .toDouble(),
  };
}

/// Returns the daily weight chart origin: today-inclusive recent 7 days.
///
/// Example: when [today] is 2026-05-25, the origin is 2026-05-19 and valid
/// daily chart offsets are 0..6. The UI uses these offsets for labels even when
/// there is no stat for a date.
DateTime dailyRecentSevenOrigin(DateTime today) {
  final normalizedToday = periodStartFor(today, StatsPeriodUnit.daily);
  return normalizedToday.subtract(
    const Duration(days: dailyRecentSevenMaxOffset),
  );
}

/// Returns the weekly weight chart origin: current Monday-start week inclusive
/// plus the previous four weeks.
DateTime weeklyRecentFiveOrigin(DateTime today) {
  final currentWeek = periodStartFor(today, StatsPeriodUnit.weekly);
  return currentWeek.subtract(
    const Duration(days: weeklyRecentFiveMaxOffset * 7),
  );
}

/// Returns all daily tick dates for the recent-seven x-axis.
List<DateTime> dailyRecentSevenTickDates(DateTime origin) {
  return [
    for (var offset = 0; offset < dailyRecentSevenPeriodCount; offset++)
      addPeriods(origin, StatsPeriodUnit.daily, offset),
  ];
}

/// Returns the tick date for a daily recent-seven x-axis value.
///
/// Non-integer values and values outside 0..6 are not labels.
DateTime? dailyRecentSevenTickDate(DateTime origin, double value) {
  return axisTickDateAt(
    WeightTrendAxisWindow(
      periodUnit: StatsPeriodUnit.daily,
      origin: origin,
      periodCount: dailyRecentSevenPeriodCount,
    ),
    value,
  );
}

/// Returns the logical tick date for an integer x-axis [value].
///
/// Padded synthetic domain edges and non-integer values are deliberately not
/// labelled.
DateTime? axisTickDateAt(WeightTrendAxisWindow window, double value) {
  final offset = value.round();
  if ((value - offset).abs() > 0.01 ||
      offset < 0 ||
      offset > window.maxOffset) {
    return null;
  }
  return addPeriods(window.origin, window.periodUnit, offset);
}

/// Returns whether [offset] is inside the daily recent-seven chart domain.
bool isDailyRecentSevenOffset(double offset) {
  return offset >= 0 && offset <= dailyRecentSevenMaxX;
}

/// Returns a safe chart maxX.
///
/// Prefer [buildWeightTrendAxisWindow] for chart rendering. This legacy helper
/// remains for existing tests/callers.
double weightTrendMaxX(List<ExercisePeriodStats> stats) {
  if (stats.isEmpty) {
    return 1;
  }

  final periodUnit = stats.first.periodUnit;
  if (periodUnit == StatsPeriodUnit.daily) {
    return dailyRecentSevenMaxX;
  }
  if (periodUnit == StatsPeriodUnit.weekly) {
    return weeklyRecentFiveMaxX;
  }

  final window = _monthlyAxisWindow(stats);
  return window.logicalMaxX;
}

DateTime periodStartFor(DateTime date, StatsPeriodUnit periodUnit) {
  final normalized = DateTime(date.year, date.month, date.day);
  return switch (periodUnit) {
    StatsPeriodUnit.daily => normalized,
    StatsPeriodUnit.weekly => normalized.subtract(
      Duration(days: normalized.weekday - DateTime.monday),
    ),
    StatsPeriodUnit.monthly => DateTime(date.year, date.month),
  };
}

DateTime addPeriods(DateTime date, StatsPeriodUnit periodUnit, int amount) {
  return switch (periodUnit) {
    StatsPeriodUnit.daily => date.add(Duration(days: amount)),
    StatsPeriodUnit.weekly => date.add(Duration(days: amount * 7)),
    StatsPeriodUnit.monthly => DateTime(date.year, date.month + amount),
  };
}

WeightTrendAxisWindow _monthlyAxisWindow(List<ExercisePeriodStats> stats) {
  if (stats.isEmpty) {
    return WeightTrendAxisWindow(
      periodUnit: StatsPeriodUnit.monthly,
      origin: periodStartFor(DateTime.now(), StatsPeriodUnit.monthly),
      periodCount: monthlyMinimumPeriodCount,
    );
  }

  final monthlyStats =
      stats.where((stat) => stat.periodUnit == StatsPeriodUnit.monthly).toList()
        ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
  final sortedStats = monthlyStats.isEmpty ? stats : monthlyStats;
  final latestMonth = periodStartFor(
    sortedStats.last.periodStart,
    StatsPeriodUnit.monthly,
  );
  final earliestMonth = periodStartFor(
    sortedStats.first.periodStart,
    StatsPeriodUnit.monthly,
  );
  final dataSpan =
      periodOffsetFrom(
        earliestMonth,
        latestMonth,
        StatsPeriodUnit.monthly,
      ).round() +
      1;
  final periodCount = dataSpan.clamp(
    monthlyMinimumPeriodCount,
    monthlyMaximumPeriodCount,
  );
  final origin = addPeriods(
    latestMonth,
    StatsPeriodUnit.monthly,
    -(periodCount - 1),
  );

  return WeightTrendAxisWindow(
    periodUnit: StatsPeriodUnit.monthly,
    origin: origin,
    periodCount: periodCount,
  );
}
