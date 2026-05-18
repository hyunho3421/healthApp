import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_growth_diary/core/db/app_database.dart';
import 'package:muscle_growth_diary/core/db/seed/workout_seed_data.dart';
import 'package:muscle_growth_diary/core/models/exercise_type.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('seeds default body parts and exercises idempotently', () async {
    await database.seedInitialData();
    await database.seedInitialData();

    final bodyParts = await database.select(database.bodyParts).get();
    final exercises = await database.select(database.exercises).get();

    expect(bodyParts, hasLength(bodyPartSeeds.length));
    expect(exercises, hasLength(exerciseSeeds.length));
    expect(bodyParts.map((part) => part.name), containsAll(['가슴', '등', '하체']));
    expect(exercises.where((exercise) => exercise.isCustom), isEmpty);
    expect(
      exercises.map((exercise) => exercise.type).toSet(),
      everyElement(isIn(exerciseTypeIds)),
    );
    expect(
      exercises.firstWhere((exercise) => exercise.name == '푸시업').type,
      'bodyweight',
    );
    expect(
      exercises.firstWhere((exercise) => exercise.name == '벤치프레스').type,
      defaultExerciseTypeId,
    );
  });

  test('cascades session deletion to entries and sets', () async {
    await database.seedInitialData();
    final exercise = (await database.select(database.exercises).get()).first;

    final sessionId = await database
        .into(database.workoutSessions)
        .insert(
          WorkoutSessionsCompanion.insert(workoutDate: DateTime(2026, 5, 16)),
        );
    final entryId = await database
        .into(database.workoutEntries)
        .insert(
          WorkoutEntriesCompanion.insert(
            sessionId: sessionId,
            exerciseId: exercise.id,
            orderIndex: const Value(0),
          ),
        );
    await database
        .into(database.workoutSets)
        .insert(
          WorkoutSetsCompanion.insert(
            entryId: entryId,
            setNumber: 1,
            weight: 60,
            reps: 10,
          ),
        );
    expect(
      (await database.select(database.workoutSets).get()).single.isWarmup,
      isFalse,
    );

    await (database.delete(
      database.workoutSessions,
    )..where((row) => row.id.equals(sessionId))).go();

    expect(await database.select(database.workoutEntries).get(), isEmpty);
    expect(await database.select(database.workoutSets).get(), isEmpty);
  });
}
