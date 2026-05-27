import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../models/exercise_stats_period.dart';
import '../models/favorite_exercise_stats.dart';
import '../models/monthly_exercise_stats.dart';
import '../../workout/models/workout_draft.dart';

class StatsRepository {
  StatsRepository(this._database);

  final AppDatabase _database;

  Future<List<ExercisePeriodStatsRow>> getExerciseStats({
    required int exerciseId,
    required StatsPeriodUnit periodUnit,
    DateTime? fromInclusive,
    DateTime? toExclusive,
  }) async {
    return _getStats(
      periodUnit: periodUnit,
      fromInclusive: fromInclusive,
      toExclusive: toExclusive,
      exerciseId: exerciseId,
    );
  }

  Future<List<ExercisePeriodStatsRow>> getOverallStats({
    required StatsPeriodUnit periodUnit,
    DateTime? fromInclusive,
    DateTime? toExclusive,
  }) async {
    return _getStats(
      periodUnit: periodUnit,
      fromInclusive: fromInclusive,
      toExclusive: toExclusive,
    );
  }

  Future<List<FavoriteExerciseSummary>> getFavoriteExerciseSummaries({
    DateTime? fromInclusive,
    DateTime? toExclusive,
  }) async {
    final favoriteRows =
        await (_database.select(_database.favoriteExercises)..orderBy([
              (table) => OrderingTerm.asc(table.sortOrder),
              (table) => OrderingTerm.asc(table.createdAt),
            ]))
            .get();

    final summaries = <FavoriteExerciseSummary>[];
    for (final favorite in favoriteRows) {
      final exercise =
          await (_database.select(_database.exercises)
                ..where((table) => table.id.equals(favorite.exerciseId)))
              .getSingleOrNull();
      if (exercise == null) {
        continue;
      }
      final bodyPart = await (_database.select(
        _database.bodyParts,
      )..where((table) => table.id.equals(exercise.bodyPartId))).getSingle();
      summaries.add(
        FavoriteExerciseSummary(
          favorite: favorite,
          exercise: exercise,
          bodyPart: bodyPart,
          stats: await getFavoriteExerciseStats(
            exerciseId: exercise.id,
            fromInclusive: fromInclusive,
            toExclusive: toExclusive,
          ),
        ),
      );
    }

    return summaries;
  }

  Future<FavoriteExerciseStats> getFavoriteExerciseStats({
    required int exerciseId,
    DateTime? fromInclusive,
    DateTime? toExclusive,
  }) async {
    final join =
        _database.select(_database.workoutSets).join([
            innerJoin(
              _database.workoutEntries,
              _database.workoutEntries.id.equalsExp(
                _database.workoutSets.entryId,
              ),
            ),
            innerJoin(
              _database.workoutSessions,
              _database.workoutSessions.id.equalsExp(
                _database.workoutEntries.sessionId,
              ),
            ),
          ])
          ..where(_database.workoutEntries.exerciseId.equals(exerciseId))
          ..where(_database.workoutSets.isWarmup.equals(false));

    if (fromInclusive != null) {
      join.where(
        _database.workoutSessions.workoutDate.isBiggerOrEqualValue(
          fromInclusive,
        ),
      );
    }
    if (toExclusive != null) {
      join.where(
        _database.workoutSessions.workoutDate.isSmallerThanValue(toExclusive),
      );
    }

    final rows = await join.get();
    if (rows.isEmpty) {
      return const FavoriteExerciseStats.empty();
    }

    double maxWeight = 0;
    int maxWeightReps = 0;
    double totalVolume = 0;
    var setCount = 0;
    DateTime? lastWorkoutDate;
    final workoutDays = <DateTime>{};

    for (final row in rows) {
      final set = row.readTable(_database.workoutSets);
      final session = row.readTable(_database.workoutSessions);
      final workoutDay = DateTime(
        session.workoutDate.year,
        session.workoutDate.month,
        session.workoutDate.day,
      );
      workoutDays.add(workoutDay);
      final weightKg = workoutWeightInKg(set.weight, set.weightUnit);
      if (lastWorkoutDate == null || workoutDay.isAfter(lastWorkoutDate)) {
        lastWorkoutDate = workoutDay;
      }
      if (maxWeightReps == 0 ||
          weightKg > maxWeight ||
          (weightKg == maxWeight && set.reps > maxWeightReps)) {
        maxWeight = weightKg;
        maxWeightReps = set.reps;
      }
      totalVolume += weightKg * set.reps;
      setCount += 1;
    }

    return FavoriteExerciseStats(
      maxWeight: maxWeight,
      maxWeightReps: maxWeightReps,
      totalVolume: totalVolume,
      setCount: setCount,
      workoutDayCount: workoutDays.length,
      lastWorkoutDate: lastWorkoutDate,
    );
  }

  Future<int> addFavoriteExercise(int exerciseId) async {
    final existing = await (_database.select(
      _database.favoriteExercises,
    )..where((table) => table.exerciseId.equals(exerciseId))).getSingleOrNull();
    if (existing != null) {
      return existing.id;
    }

    final currentFavorites = await _database
        .select(_database.favoriteExercises)
        .get();
    final nextSortOrder = currentFavorites.isEmpty
        ? 0
        : currentFavorites
                  .map((favorite) => favorite.sortOrder)
                  .reduce((a, b) => a > b ? a : b) +
              1;

    return _database
        .into(_database.favoriteExercises)
        .insert(
          FavoriteExercisesCompanion.insert(
            exerciseId: exerciseId,
            sortOrder: Value(nextSortOrder),
          ),
        );
  }

  Future<void> removeFavoriteExercise(int exerciseId) async {
    await (_database.delete(
      _database.favoriteExercises,
    )..where((table) => table.exerciseId.equals(exerciseId))).go();
  }

  Future<List<MonthlyExerciseStatsRow>> getMonthlyExerciseStats({
    required int exerciseId,
    DateTime? fromMonth,
    DateTime? toMonthExclusive,
  }) async {
    final rows = await getExerciseStats(
      exerciseId: exerciseId,
      periodUnit: StatsPeriodUnit.monthly,
      fromInclusive: fromMonth == null
          ? null
          : DateTime(fromMonth.year, fromMonth.month),
      toExclusive: toMonthExclusive == null
          ? null
          : DateTime(toMonthExclusive.year, toMonthExclusive.month),
    );

    return [
      for (final row in rows)
        MonthlyExerciseStatsRow(
          month: row.periodStart,
          maxWeight: row.maxWeight,
          averageWeight: row.averageWeight,
          totalVolume: row.totalVolume,
        ),
    ];
  }

  Future<List<ExercisePeriodStatsRow>> _getStats({
    required StatsPeriodUnit periodUnit,
    DateTime? fromInclusive,
    DateTime? toExclusive,
    int? exerciseId,
  }) async {
    final join = _database.select(_database.workoutSets).join([
      innerJoin(
        _database.workoutEntries,
        _database.workoutEntries.id.equalsExp(_database.workoutSets.entryId),
      ),
      innerJoin(
        _database.workoutSessions,
        _database.workoutSessions.id.equalsExp(
          _database.workoutEntries.sessionId,
        ),
      ),
    ])..where(_database.workoutSets.isWarmup.equals(false));

    if (exerciseId != null) {
      join.where(_database.workoutEntries.exerciseId.equals(exerciseId));
    }
    if (fromInclusive != null) {
      join.where(
        _database.workoutSessions.workoutDate.isBiggerOrEqualValue(
          fromInclusive,
        ),
      );
    }
    if (toExclusive != null) {
      join.where(
        _database.workoutSessions.workoutDate.isSmallerThanValue(toExclusive),
      );
    }

    final rows = await join.get();
    final buckets = <DateTime, _StatsAccumulator>{};

    for (final row in rows) {
      final set = row.readTable(_database.workoutSets);
      final session = row.readTable(_database.workoutSessions);
      final periodStart = _periodStart(session.workoutDate, periodUnit);
      buckets.putIfAbsent(periodStart, _StatsAccumulator.new).add(set);
    }

    final periods = buckets.keys.toList()..sort();
    return [
      for (final periodStart in periods)
        ExercisePeriodStatsRow(
          periodStart: periodStart,
          periodUnit: periodUnit,
          maxWeight: buckets[periodStart]!.maxWeight,
          averageWeight: buckets[periodStart]!.averageWeight,
          totalVolume: buckets[periodStart]!.totalVolume,
        ),
    ];
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

class _StatsAccumulator {
  double maxWeight = 0;
  double totalWeight = 0;
  double totalVolume = 0;
  int setCount = 0;

  double get averageWeight => setCount == 0 ? 0 : totalWeight / setCount;

  void add(WorkoutSet set) {
    final weightKg = workoutWeightInKg(set.weight, set.weightUnit);
    if (setCount == 0 || weightKg > maxWeight) {
      maxWeight = weightKg;
    }
    totalWeight += weightKg;
    totalVolume += weightKg * set.reps;
    setCount += 1;
  }
}
