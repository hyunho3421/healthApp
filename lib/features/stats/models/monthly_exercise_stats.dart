import 'exercise_stats_period.dart';

class ExercisePeriodStats {
  const ExercisePeriodStats({
    required this.periodStart,
    required this.periodUnit,
    required this.maxWeight,
    required this.averageWeight,
    required this.totalVolume,
    this.previousMaxWeightDiff,
    this.previousMaxWeightRate,
    this.previousAverageWeightDiff,
    this.previousAverageWeightRate,
    this.previousTotalVolumeDiff,
    this.previousTotalVolumeRate,
  });

  final DateTime periodStart;
  final StatsPeriodUnit periodUnit;
  final double maxWeight;
  final double averageWeight;
  final double totalVolume;

  final double? previousMaxWeightDiff;
  final double? previousMaxWeightRate;
  final double? previousAverageWeightDiff;
  final double? previousAverageWeightRate;
  final double? previousTotalVolumeDiff;
  final double? previousTotalVolumeRate;

  /// Backward-compatible alias for existing monthly UI/tests.
  DateTime get month => periodStart;

  String get periodKey => switch (periodUnit) {
    StatsPeriodUnit.daily =>
      '${periodStart.year.toString().padLeft(4, '0')}-'
          '${periodStart.month.toString().padLeft(2, '0')}-'
          '${periodStart.day.toString().padLeft(2, '0')}',
    StatsPeriodUnit.weekly =>
      '${periodStart.year.toString().padLeft(4, '0')}-W'
          '${_weekNumber(periodStart).toString().padLeft(2, '0')}',
    StatsPeriodUnit.monthly => monthKey,
  };

  String get monthKey =>
      '${periodStart.year.toString().padLeft(4, '0')}-'
      '${periodStart.month.toString().padLeft(2, '0')}';
}

class MonthlyExerciseStats extends ExercisePeriodStats {
  const MonthlyExerciseStats({
    required DateTime month,
    required super.maxWeight,
    required super.averageWeight,
    required super.totalVolume,
    super.previousMaxWeightDiff,
    super.previousMaxWeightRate,
    super.previousAverageWeightDiff,
    super.previousAverageWeightRate,
    super.previousTotalVolumeDiff,
    super.previousTotalVolumeRate,
  }) : super(periodStart: month, periodUnit: StatsPeriodUnit.monthly);
}

class ExercisePeriodStatsRow {
  const ExercisePeriodStatsRow({
    required this.periodStart,
    required this.periodUnit,
    required this.maxWeight,
    required this.averageWeight,
    required this.totalVolume,
  });

  final DateTime periodStart;
  final StatsPeriodUnit periodUnit;
  final double maxWeight;
  final double averageWeight;
  final double totalVolume;

  DateTime get month => periodStart;
}

class MonthlyExerciseStatsRow extends ExercisePeriodStatsRow {
  const MonthlyExerciseStatsRow({
    required DateTime month,
    required super.maxWeight,
    required super.averageWeight,
    required super.totalVolume,
  }) : super(periodStart: month, periodUnit: StatsPeriodUnit.monthly);
}

int _weekNumber(DateTime date) {
  final firstDayOfYear = DateTime(date.year);
  final daysOffset = date.difference(firstDayOfYear).inDays;
  return (daysOffset / 7).floor() + 1;
}
