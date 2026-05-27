import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_growth_diary/core/db/app_database.dart';
import 'package:muscle_growth_diary/features/stats/application/stats_service.dart';
import 'package:muscle_growth_diary/features/stats/data/stats_repository.dart';
import 'package:muscle_growth_diary/features/stats/models/exercise_stats_period.dart';
import 'package:muscle_growth_diary/features/workout/application/workout_service.dart';
import 'package:muscle_growth_diary/features/workout/data/workout_repository.dart';
import 'package:muscle_growth_diary/features/workout/models/workout_draft.dart';

void main() {
  late AppDatabase database;
  late WorkoutService workoutService;
  late StatsService statsService;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    workoutService = WorkoutService(WorkoutRepository(database));
    statsService = StatsService(StatsRepository(database));
    await database.seedInitialData();
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'calculates daily stats and previous period total volume deltas',
    () async {
      final benchPress = (await database.select(database.exercises).get())
          .firstWhere((exercise) => exercise.name == '벤치프레스');

      await workoutService.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 4),
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
            ),
          ],
        ),
      );
      await workoutService.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 5),
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 80, reps: 5)],
            ),
          ],
        ),
      );

      final stats = await statsService.getExerciseStats(
        exerciseId: benchPress.id,
        periodUnit: StatsPeriodUnit.daily,
        recentCount: 7,
        anchorDate: DateTime(2026, 5, 5),
      );

      expect(stats.map((stat) => stat.periodKey), ['2026-05-04', '2026-05-05']);
      expect(stats.last.maxWeight, 80);
      expect(stats.last.averageWeight, 80);
      expect(stats.last.totalVolume, 400);
      expect(stats.last.previousTotalVolumeDiff, -200);
      expect(stats.last.previousTotalVolumeRate, closeTo(-33.3333, 0.001));
    },
  );

  test('calculates weekly stats from monday based buckets', () async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');

    await workoutService.saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 3), // Sunday, week starts 2026-04-27.
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [WorkoutSetDraft(weight: 50, reps: 10)],
          ),
        ],
      ),
    );
    await workoutService.saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 4), // Monday, next week.
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [WorkoutSetDraft(weight: 70, reps: 10)],
          ),
        ],
      ),
    );

    final stats = await statsService.getExerciseStats(
      exerciseId: benchPress.id,
      periodUnit: StatsPeriodUnit.weekly,
      recentCount: 3,
      anchorDate: DateTime(2026, 5, 10),
    );

    expect(stats.map((stat) => stat.periodStart), [
      DateTime(2026, 4, 27),
      DateTime(2026, 5, 4),
    ]);
    expect(stats.last.maxWeight, 70);
    expect(stats.last.totalVolume, 700);
    expect(stats.last.previousTotalVolumeDiff, 200);
    expect(stats.last.previousTotalVolumeRate, 40);
  });

  test('converts lbs workout sets to kg for statistics', () async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');

    await workoutService.saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 4),
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [
              WorkoutSetDraft(weight: 220.462, weightUnit: 'lbs', reps: 5),
            ],
          ),
        ],
      ),
    );

    final stats = await statsService.getExerciseStats(
      exerciseId: benchPress.id,
      periodUnit: StatsPeriodUnit.daily,
      recentCount: 7,
      anchorDate: DateTime(2026, 5, 4),
    );

    expect(stats.single.maxWeight, closeTo(100, 0.01));
    expect(stats.single.averageWeight, closeTo(100, 0.01));
    expect(stats.single.totalVolume, closeTo(500, 0.01));
  });

  test(
    'calculates monthly max, average, volume, and previous deltas',
    () async {
      final benchPress = (await database.select(database.exercises).get())
          .firstWhere((exercise) => exercise.name == '벤치프레스');

      await workoutService.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 4, 10),
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [
                WorkoutSetDraft(weight: 60, reps: 10),
                WorkoutSetDraft(weight: 70, reps: 5),
              ],
            ),
          ],
        ),
      );
      await workoutService.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 5),
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [
                WorkoutSetDraft(weight: 70, reps: 10),
                WorkoutSetDraft(weight: 80, reps: 5),
              ],
            ),
          ],
        ),
      );

      final stats = await statsService.getMonthlyExerciseStats(
        exerciseId: benchPress.id,
        recentMonths: 3,
        anchorMonth: DateTime(2026, 5, 1),
      );

      expect(stats.map((stat) => stat.monthKey), ['2026-04', '2026-05']);
      expect(stats.first.maxWeight, 70);
      expect(stats.first.averageWeight, 65);
      expect(stats.first.totalVolume, 950);
      expect(stats.first.previousMaxWeightDiff, isNull);

      expect(stats.last.maxWeight, 80);
      expect(stats.last.averageWeight, 75);
      expect(stats.last.totalVolume, 1100);
      expect(stats.last.previousMaxWeightDiff, 10);
      expect(stats.last.previousAverageWeightDiff, 10);
      expect(stats.last.previousTotalVolumeDiff, 150);
      expect(stats.last.previousMaxWeightRate, closeTo(14.2857, 0.001));
    },
  );

  test('excludes deleted workout entries from monthly stats', () async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');

    final sessionId = await workoutService.saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 5),
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [WorkoutSetDraft(weight: 70, reps: 10)],
          ),
        ],
      ),
    );
    final entryId = (await workoutService.getWorkoutRecords())
        .single
        .entries
        .single
        .entry
        .id;

    await workoutService.deleteWorkoutEntry(
      sessionId: sessionId,
      entryId: entryId,
    );

    final stats = await statsService.getMonthlyExerciseStats(
      exerciseId: benchPress.id,
      recentMonths: 3,
      anchorMonth: DateTime(2026, 5, 1),
    );

    expect(stats, isEmpty);
  });

  test('adds favorite exercise once and keeps card stats in range', () async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');

    await statsService.addFavoriteExercise(benchPress.id);
    await statsService.addFavoriteExercise(benchPress.id);

    await workoutService.saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 4, 30),
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [WorkoutSetDraft(weight: 50, reps: 10)],
          ),
        ],
      ),
    );
    await workoutService.saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 4),
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [
              WorkoutSetDraft(weight: 40, reps: 10, isWarmup: true),
              WorkoutSetDraft(weight: 70, reps: 8),
              WorkoutSetDraft(weight: 80, reps: 5),
              WorkoutSetDraft(weight: 80, reps: 8),
            ],
          ),
        ],
      ),
    );
    await workoutService.saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 5),
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [WorkoutSetDraft(weight: 75, reps: 6)],
          ),
        ],
      ),
    );

    final favorites = await statsService.getFavoriteExerciseSummaries(
      periodUnit: StatsPeriodUnit.daily,
      recentCount: 2,
      anchorDate: DateTime(2026, 5, 5),
    );

    expect(
      await database.select(database.favoriteExercises).get(),
      hasLength(1),
    );
    expect(favorites, hasLength(1));
    expect(favorites.single.exercise.id, benchPress.id);
    expect(favorites.single.bodyPart.name, '가슴');
    expect(favorites.single.stats.maxWeight, 80);
    expect(favorites.single.stats.maxWeightReps, 8);
    expect(favorites.single.stats.totalVolume, 2050);
    expect(favorites.single.stats.setCount, 4);
    expect(favorites.single.stats.workoutDayCount, 2);
    expect(favorites.single.stats.lastWorkoutDate, DateTime(2026, 5, 5));
  });

  test('favorite exercise remains after removing favorite only', () async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');

    await statsService.addFavoriteExercise(benchPress.id);
    await workoutService.saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 4),
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [WorkoutSetDraft(weight: 70, reps: 8)],
          ),
        ],
      ),
    );

    await statsService.removeFavoriteExercise(benchPress.id);

    final favorites = await statsService.getFavoriteExerciseSummaries(
      periodUnit: StatsPeriodUnit.daily,
      recentCount: 2,
      anchorDate: DateTime(2026, 5, 5),
    );
    final stats = await statsService.getExerciseStats(
      exerciseId: benchPress.id,
      periodUnit: StatsPeriodUnit.daily,
      recentCount: 2,
      anchorDate: DateTime(2026, 5, 5),
    );

    expect(favorites, isEmpty);
    expect(stats.single.totalVolume, 560);
  });

  test('favorite exercise with no records is still returned', () async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');

    await statsService.addFavoriteExercise(benchPress.id);

    final favorites = await statsService.getFavoriteExerciseSummaries(
      periodUnit: StatsPeriodUnit.monthly,
      recentCount: 6,
      anchorDate: DateTime(2026, 5, 1),
    );

    expect(favorites, hasLength(1));
    expect(favorites.single.stats.hasRecords, isFalse);
    expect(favorites.single.stats.totalVolume, 0);
    expect(favorites.single.stats.setCount, 0);
    expect(favorites.single.stats.lastWorkoutDate, isNull);
  });

  test(
    'excludes warmup sets from stats and returns empty for warmup-only records',
    () async {
      final benchPress = (await database.select(database.exercises).get())
          .firstWhere((exercise) => exercise.name == '벤치프레스');

      await workoutService.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 4),
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [
                WorkoutSetDraft(weight: 100, reps: 1, isWarmup: true),
                WorkoutSetDraft(weight: 70, reps: 5),
              ],
            ),
          ],
        ),
      );
      await workoutService.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 5),
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [
                WorkoutSetDraft(weight: 40, reps: 10, isWarmup: true),
              ],
            ),
          ],
        ),
      );

      final stats = await statsService.getExerciseStats(
        exerciseId: benchPress.id,
        periodUnit: StatsPeriodUnit.daily,
        recentCount: 7,
        anchorDate: DateTime(2026, 5, 5),
      );

      expect(stats.map((stat) => stat.periodKey), ['2026-05-04']);
      expect(stats.single.maxWeight, 70);
      expect(stats.single.averageWeight, 70);
      expect(stats.single.totalVolume, 350);
    },
  );

  test('returns empty list when there is no data in range', () async {
    final exercise = (await database.select(database.exercises).get()).first;

    final stats = await statsService.getMonthlyExerciseStats(
      exerciseId: exercise.id,
      recentMonths: 6,
      anchorMonth: DateTime(2026, 5, 1),
    );

    expect(stats, isEmpty);
  });
}
