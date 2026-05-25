import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_growth_diary/features/stats/models/exercise_stats_period.dart';
import 'package:muscle_growth_diary/features/stats/models/monthly_exercise_stats.dart';
import 'package:muscle_growth_diary/features/stats/models/stats_chart_axis.dart';

void main() {
  test(
    'periodOffsetFrom preserves calendar gaps between non-consecutive stats',
    () {
      expect(
        periodOffsetFrom(
          DateTime(2026, 5, 1),
          DateTime(2026, 5, 4),
          StatsPeriodUnit.daily,
        ),
        3,
      );
      expect(
        periodOffsetFrom(
          DateTime(2026, 5, 4),
          DateTime(2026, 5, 18),
          StatsPeriodUnit.weekly,
        ),
        2,
      );
      expect(
        periodOffsetFrom(
          DateTime(2025, 12, 1),
          DateTime(2026, 3, 1),
          StatsPeriodUnit.monthly,
        ),
        3,
      );
    },
  );

  test('daily recent-seven origin is fixed to today minus six days', () {
    final origin = dailyRecentSevenOrigin(DateTime(2026, 5, 25, 23, 59));

    expect(origin, DateTime(2026, 5, 19));
    expect(dailyRecentSevenMaxX, 6);
  });

  test('daily recent-seven ticks include every date through today', () {
    final origin = dailyRecentSevenOrigin(DateTime(2026, 5, 25));

    expect(dailyRecentSevenTickDates(origin), [
      DateTime(2026, 5, 19),
      DateTime(2026, 5, 20),
      DateTime(2026, 5, 21),
      DateTime(2026, 5, 22),
      DateTime(2026, 5, 23),
      DateTime(2026, 5, 24),
      DateTime(2026, 5, 25),
    ]);
    expect(dailyRecentSevenTickDate(origin, 0), DateTime(2026, 5, 19));
    expect(dailyRecentSevenTickDate(origin, 6), DateTime(2026, 5, 25));
    expect(dailyRecentSevenTickDate(origin, 2.5), isNull);
    expect(dailyRecentSevenTickDate(origin, 7), isNull);
  });

  test('daily sparse owner example maps only actual stats to x offsets', () {
    final origin = dailyRecentSevenOrigin(DateTime(2026, 5, 25));
    final workoutDates = [
      DateTime(2026, 5, 19),
      DateTime(2026, 5, 20),
      DateTime(2026, 5, 24),
    ];

    final offsets = [
      for (final date in workoutDates)
        periodOffsetFrom(origin, date, StatsPeriodUnit.daily),
    ];

    expect(offsets, [0, 1, 5]);
    expect(dailyRecentSevenTickDate(origin, 2), DateTime(2026, 5, 21));
    expect(dailyRecentSevenTickDate(origin, 3), DateTime(2026, 5, 22));
    expect(dailyRecentSevenTickDate(origin, 4), DateTime(2026, 5, 23));
  });

  test('weekly axis is current week plus previous four Monday-start weeks', () {
    final window = buildWeightTrendAxisWindow(
      periodUnit: StatsPeriodUnit.weekly,
      stats: [
        _stat(DateTime(2026, 5, 4), StatsPeriodUnit.weekly),
        _stat(DateTime(2026, 5, 18), StatsPeriodUnit.weekly),
      ],
      today: DateTime(2026, 5, 25, 13),
    );

    expect(window.origin, DateTime(2026, 4, 27));
    expect(window.periodCount, weeklyRecentFivePeriodCount);
    expect(window.logicalMaxX, weeklyRecentFiveMaxX);
    expect(window.tickDates, [
      DateTime(2026, 4, 27),
      DateTime(2026, 5, 4),
      DateTime(2026, 5, 11),
      DateTime(2026, 5, 18),
      DateTime(2026, 5, 25),
    ]);
    expect(axisTickDateAt(window, 0), DateTime(2026, 4, 27));
    expect(axisTickDateAt(window, 4), DateTime(2026, 5, 25));
  });

  test(
    'weekly sparse stats map to calendar offsets without fake zero points',
    () {
      final origin = weeklyRecentFiveOrigin(DateTime(2026, 5, 25));
      final workoutWeeks = [DateTime(2026, 5, 4), DateTime(2026, 5, 18)];

      final offsets = [
        for (final week in workoutWeeks)
          periodOffsetFrom(origin, week, StatsPeriodUnit.weekly),
      ];

      expect(offsets, [1, 3]);
      expect(
        axisTickDateAt(
          WeightTrendAxisWindow(
            periodUnit: StatsPeriodUnit.weekly,
            origin: origin,
            periodCount: weeklyRecentFivePeriodCount,
          ),
          2,
        ),
        DateTime(2026, 5, 11),
      );
    },
  );

  test('monthly sparse data shows minimum five-month latest-data axis', () {
    final window = buildWeightTrendAxisWindow(
      periodUnit: StatsPeriodUnit.monthly,
      stats: [
        _stat(DateTime(2026, 3, 1), StatsPeriodUnit.monthly),
        _stat(DateTime(2026, 5, 1), StatsPeriodUnit.monthly),
      ],
      today: DateTime(2026, 6, 20),
    );

    expect(window.origin, DateTime(2026, 1, 1));
    expect(window.periodCount, monthlyMinimumPeriodCount);
    expect(window.tickDates, [
      DateTime(2026, 1, 1),
      DateTime(2026, 2, 1),
      DateTime(2026, 3, 1),
      DateTime(2026, 4, 1),
      DateTime(2026, 5, 1),
    ]);
    expect(
      periodOffsetFrom(
        window.origin,
        DateTime(2026, 3, 1),
        StatsPeriodUnit.monthly,
      ),
      2,
    );
    expect(
      periodOffsetFrom(
        window.origin,
        DateTime(2026, 5, 1),
        StatsPeriodUnit.monthly,
      ),
      4,
    );
  });

  test('monthly axis caps long data to latest twelve calendar months', () {
    final window = buildWeightTrendAxisWindow(
      periodUnit: StatsPeriodUnit.monthly,
      stats: [
        _stat(DateTime(2025, 1, 1), StatsPeriodUnit.monthly),
        _stat(DateTime(2025, 7, 1), StatsPeriodUnit.monthly),
        _stat(DateTime(2026, 5, 1), StatsPeriodUnit.monthly),
      ],
      today: DateTime(2026, 5, 25),
    );

    expect(window.periodCount, monthlyMaximumPeriodCount);
    expect(window.origin, DateTime(2025, 6, 1));
    expect(window.tickDates.first, DateTime(2025, 6, 1));
    expect(window.tickDates.last, DateTime(2026, 5, 1));
    expect(window.containsOffset(-5), isFalse);
    expect(
      periodOffsetFrom(
        window.origin,
        DateTime(2026, 5, 1),
        StatsPeriodUnit.monthly,
      ),
      11,
    );
  });

  test(
    'monthly latest-data basis does not move to current month for old data',
    () {
      final window = buildWeightTrendAxisWindow(
        periodUnit: StatsPeriodUnit.monthly,
        stats: [_stat(DateTime(2025, 10, 1), StatsPeriodUnit.monthly)],
        today: DateTime(2026, 5, 25),
      );

      expect(window.origin, DateTime(2025, 6, 1));
      expect(window.tickDates.last, DateTime(2025, 10, 1));
    },
  );

  test(
    'domain padding keeps endpoint points inside but labels remain logical',
    () {
      final window = buildWeightTrendAxisWindow(
        periodUnit: StatsPeriodUnit.weekly,
        stats: const [],
        today: DateTime(2026, 5, 25),
      );

      expect(window.paddedMinX, lessThan(0));
      expect(window.paddedMaxX, greaterThan(window.logicalMaxX));
      expect(window.containsOffset(0), isTrue);
      expect(window.containsOffset(window.logicalMaxX), isTrue);
      expect(axisTickDateAt(window, window.paddedMinX), isNull);
      expect(axisTickDateAt(window, window.paddedMaxX), isNull);
      expect(axisTickDateAt(window, 0), DateTime(2026, 4, 27));
      expect(axisTickDateAt(window, 4), DateTime(2026, 5, 25));
    },
  );

  test('weightTrendMaxX uses fixed logical ranges for chart windows', () {
    expect(
      weightTrendMaxX([
        _stat(DateTime(2026, 5, 19), StatsPeriodUnit.daily),
        _stat(DateTime(2026, 5, 24), StatsPeriodUnit.daily),
      ]),
      dailyRecentSevenMaxX,
    );
    expect(
      weightTrendMaxX([_stat(DateTime(2026, 5, 4), StatsPeriodUnit.weekly)]),
      weeklyRecentFiveMaxX,
    );
    expect(
      weightTrendMaxX([_stat(DateTime(2026, 5, 1), StatsPeriodUnit.monthly)]),
      monthlyMinimumPeriodCount - 1,
    );
  });
}

ExercisePeriodStats _stat(DateTime periodStart, StatsPeriodUnit periodUnit) {
  return ExercisePeriodStats(
    periodStart: periodStart,
    periodUnit: periodUnit,
    maxWeight: 100,
    averageWeight: 90,
    totalVolume: 1000,
  );
}
