import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_growth_diary/core/db/app_database.dart';
import 'package:muscle_growth_diary/features/workout/application/workout_service.dart';
import 'package:muscle_growth_diary/features/workout/data/workout_repository.dart';
import 'package:muscle_growth_diary/features/workout/models/workout_draft.dart';

void main() {
  late AppDatabase database;
  late WorkoutService service;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    service = WorkoutService(WorkoutRepository(database));
    await database.seedInitialData();
  });

  tearDown(() async {
    await database.close();
  });

  test('saves workout draft and reads it back by date', () async {
    final exercise = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');

    final sessionId = await service.saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 16),
        memo: '가볍게 시작',
        entries: [
          WorkoutEntryDraft(
            exerciseId: exercise.id,
            sets: const [
              WorkoutSetDraft(weight: 60, reps: 10),
              WorkoutSetDraft(weight: 65, reps: 8),
            ],
          ),
        ],
      ),
    );

    final records = await service.getWorkoutRecords(
      from: DateTime(2026, 5, 1),
      to: DateTime(2026, 6, 1),
    );

    expect(records, hasLength(1));
    expect(records.single.session.id, sessionId);
    expect(records.single.entries.single.exercise.name, '벤치프레스');
    expect(records.single.entries.single.bodyPart.name, '가슴');
    expect(records.single.entries.single.sets.map((set) => set.weight), [
      60,
      65,
    ]);
  });

  test('updates an existing workout entry transactionally', () async {
    final exercises = await database.select(database.exercises).get();
    final benchPress = exercises.firstWhere(
      (exercise) => exercise.name == '벤치프레스',
    );
    final squat = exercises.firstWhere((exercise) => exercise.name == '스쿼트');

    final sessionId = await service.saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 16),
        memo: '수정 전',
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
          ),
        ],
      ),
    );
    final entryId =
        (await service.getWorkoutRecords()).single.entries.single.entry.id;

    await service.updateWorkoutEntry(
      sessionId: sessionId,
      entryId: entryId,
      draft: WorkoutDraft(
        workoutDate: DateTime(2026, 5, 17),
        memo: '수정 후',
        entries: [
          WorkoutEntryDraft(
            exerciseId: squat.id,
            sets: const [
              WorkoutSetDraft(weight: 100, reps: 5),
              WorkoutSetDraft(weight: 105, reps: 3),
            ],
          ),
        ],
      ),
    );

    final records = await service.getWorkoutRecords(
      from: DateTime(2026, 5, 1),
      to: DateTime(2026, 6, 1),
    );

    expect(records, hasLength(1));
    expect(records.single.session.id, sessionId);
    expect(records.single.session.workoutDate, DateTime(2026, 5, 17));
    expect(records.single.session.memo, '수정 후');
    expect(records.single.entries.single.entry.id, entryId);
    expect(records.single.entries.single.exercise.name, '스쿼트');
    expect(records.single.entries.single.bodyPart.name, '하체');
    expect(records.single.entries.single.sets.map((set) => set.weight), [
      100,
      105,
    ]);
    expect(records.single.entries.single.sets.map((set) => set.reps), [5, 3]);
  });

  test('deletes a workout entry and removes the empty session', () async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');

    final sessionId = await service.saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 16),
        memo: '삭제 대상',
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
          ),
        ],
      ),
    );
    final entryId =
        (await service.getWorkoutRecords()).single.entries.single.entry.id;

    await service.deleteWorkoutEntry(sessionId: sessionId, entryId: entryId);

    expect(await service.getWorkoutRecords(), isEmpty);
    expect(await database.select(database.workoutSessions).get(), isEmpty);
    expect(await database.select(database.workoutEntries).get(), isEmpty);
    expect(await database.select(database.workoutSets).get(), isEmpty);
  });

  test('persists warmup flags when saving and updating workouts', () async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');

    final sessionId = await service.saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 16),
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [
              WorkoutSetDraft(weight: 40, reps: 10, isWarmup: true),
              WorkoutSetDraft(weight: 60, reps: 8),
            ],
          ),
        ],
      ),
    );

    var record = (await service.getWorkoutRecords()).single.entries.single;
    expect(record.sets.map((set) => set.isWarmup), [true, false]);

    await service.updateWorkoutEntry(
      sessionId: sessionId,
      entryId: record.entry.id,
      draft: WorkoutDraft(
        workoutDate: DateTime(2026, 5, 17),
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [
              WorkoutSetDraft(weight: 45, reps: 8),
              WorkoutSetDraft(weight: 70, reps: 5, isWarmup: true),
            ],
          ),
        ],
      ),
    );

    record = (await service.getWorkoutRecords()).single.entries.single;
    expect(record.sets.map((set) => set.isWarmup), [false, true]);
  });

  test('validates empty entries and invalid set values', () async {
    expect(
      () => service.saveWorkout(
        WorkoutDraft(workoutDate: DateTime(2026, 5, 16), entries: const []),
      ),
      throwsArgumentError,
    );

    expect(
      () => service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 16),
          entries: const [
            WorkoutEntryDraft(
              exerciseId: 1,
              sets: [WorkoutSetDraft(weight: 10, reps: 0)],
            ),
          ],
        ),
      ),
      throwsArgumentError,
    );
  });
}
