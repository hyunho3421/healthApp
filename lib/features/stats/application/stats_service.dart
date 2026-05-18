import '../data/stats_repository.dart';
import '../models/exercise_stats_period.dart';
import '../models/favorite_exercise_stats.dart';
import '../models/monthly_exercise_stats.dart';

class StatsService {
  StatsService(this._repository);

  final StatsRepository _repository;

  Future<List<ExercisePeriodStats>> getExerciseStats({
    required int exerciseId,
    required StatsPeriodUnit periodUnit,
    int? recentCount,
    DateTime? anchorDate,
  }) async {
    if (exerciseId <= 0) {
      throw ArgumentError.value(exerciseId, 'exerciseId', '유효하지 않은 운동입니다.');
    }
    return _loadStats(
      periodUnit: periodUnit,
      recentCount: recentCount,
      anchorDate: anchorDate,
      loader: (from, toExclusive) => _repository.getExerciseStats(
        exerciseId: exerciseId,
        periodUnit: periodUnit,
        fromInclusive: from,
        toExclusive: toExclusive,
      ),
    );
  }

  Future<List<ExercisePeriodStats>> getOverallStats({
    required StatsPeriodUnit periodUnit,
    int? recentCount,
    DateTime? anchorDate,
  }) {
    return _loadStats(
      periodUnit: periodUnit,
      recentCount: recentCount,
      anchorDate: anchorDate,
      loader: (from, toExclusive) => _repository.getOverallStats(
        periodUnit: periodUnit,
        fromInclusive: from,
        toExclusive: toExclusive,
      ),
    );
  }

  Future<List<FavoriteExerciseSummary>> getFavoriteExerciseSummaries({
    required StatsPeriodUnit periodUnit,
    int? recentCount,
    DateTime? anchorDate,
  }) async {
    final count = recentCount ?? periodUnit.defaultRecentCount;
    if (count < 1) {
      throw ArgumentError.value(count, 'recentCount', '조회 기간 수는 1 이상이어야 합니다.');
    }

    final anchor = _periodStart(anchorDate ?? DateTime.now(), periodUnit);
    final from = _addPeriods(anchor, periodUnit, -(count - 1));
    final toExclusive = _addPeriods(anchor, periodUnit, 1);

    return _repository.getFavoriteExerciseSummaries(
      fromInclusive: from,
      toExclusive: toExclusive,
    );
  }

  Future<int> addFavoriteExercise(int exerciseId) {
    if (exerciseId <= 0) {
      throw ArgumentError.value(exerciseId, 'exerciseId', '유효하지 않은 운동입니다.');
    }
    return _repository.addFavoriteExercise(exerciseId);
  }

  Future<void> removeFavoriteExercise(int exerciseId) {
    if (exerciseId <= 0) {
      throw ArgumentError.value(exerciseId, 'exerciseId', '유효하지 않은 운동입니다.');
    }
    return _repository.removeFavoriteExercise(exerciseId);
  }

  Future<List<MonthlyExerciseStats>> getMonthlyExerciseStats({
    required int exerciseId,
    int recentMonths = 6,
    DateTime? anchorMonth,
  }) async {
    final stats = await getExerciseStats(
      exerciseId: exerciseId,
      periodUnit: StatsPeriodUnit.monthly,
      recentCount: recentMonths,
      anchorDate: anchorMonth,
    );

    return [
      for (final stat in stats)
        MonthlyExerciseStats(
          month: stat.periodStart,
          maxWeight: stat.maxWeight,
          averageWeight: stat.averageWeight,
          totalVolume: stat.totalVolume,
          previousMaxWeightDiff: stat.previousMaxWeightDiff,
          previousMaxWeightRate: stat.previousMaxWeightRate,
          previousAverageWeightDiff: stat.previousAverageWeightDiff,
          previousAverageWeightRate: stat.previousAverageWeightRate,
          previousTotalVolumeDiff: stat.previousTotalVolumeDiff,
          previousTotalVolumeRate: stat.previousTotalVolumeRate,
        ),
    ];
  }

  Future<List<ExercisePeriodStats>> _loadStats({
    required StatsPeriodUnit periodUnit,
    required Future<List<ExercisePeriodStatsRow>> Function(
      DateTime fromInclusive,
      DateTime toExclusive,
    )
    loader,
    int? recentCount,
    DateTime? anchorDate,
  }) async {
    final count = recentCount ?? periodUnit.defaultRecentCount;
    if (count < 1) {
      throw ArgumentError.value(count, 'recentCount', '조회 기간 수는 1 이상이어야 합니다.');
    }

    final anchor = _periodStart(anchorDate ?? DateTime.now(), periodUnit);
    final from = _addPeriods(anchor, periodUnit, -(count - 1));
    final toExclusive = _addPeriods(anchor, periodUnit, 1);
    final rows = await loader(from, toExclusive);

    return _withPreviousComparisons(rows);
  }

  List<ExercisePeriodStats> _withPreviousComparisons(
    List<ExercisePeriodStatsRow> rows,
  ) {
    ExercisePeriodStatsRow? previous;
    final stats = <ExercisePeriodStats>[];

    for (final row in rows) {
      stats.add(
        ExercisePeriodStats(
          periodStart: row.periodStart,
          periodUnit: row.periodUnit,
          maxWeight: row.maxWeight,
          averageWeight: row.averageWeight,
          totalVolume: row.totalVolume,
          previousMaxWeightDiff: previous == null
              ? null
              : row.maxWeight - previous.maxWeight,
          previousMaxWeightRate: _rate(row.maxWeight, previous?.maxWeight),
          previousAverageWeightDiff: previous == null
              ? null
              : row.averageWeight - previous.averageWeight,
          previousAverageWeightRate: _rate(
            row.averageWeight,
            previous?.averageWeight,
          ),
          previousTotalVolumeDiff: previous == null
              ? null
              : row.totalVolume - previous.totalVolume,
          previousTotalVolumeRate: _rate(
            row.totalVolume,
            previous?.totalVolume,
          ),
        ),
      );
      previous = row;
    }

    return stats;
  }
}

DateTime _periodStart(DateTime date, StatsPeriodUnit periodUnit) {
  final normalized = DateTime(date.year, date.month, date.day);
  return switch (periodUnit) {
    StatsPeriodUnit.daily => normalized,
    StatsPeriodUnit.weekly => normalized.subtract(
      Duration(days: normalized.weekday - DateTime.monday),
    ),
    StatsPeriodUnit.monthly => DateTime(date.year, date.month),
  };
}

DateTime _addPeriods(DateTime date, StatsPeriodUnit periodUnit, int amount) {
  return switch (periodUnit) {
    StatsPeriodUnit.daily => date.add(Duration(days: amount)),
    StatsPeriodUnit.weekly => date.add(Duration(days: amount * 7)),
    StatsPeriodUnit.monthly => DateTime(date.year, date.month + amount),
  };
}

double? _rate(double current, double? previous) {
  if (previous == null || previous == 0) {
    return null;
  }
  return (current - previous) / previous * 100;
}
