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

  test(
    'finds an existing same-day exercise record ignoring time components',
    () async {
      final exercises = await database.select(database.exercises).get();
      final benchPress = exercises.firstWhere(
        (exercise) => exercise.name == '벤치프레스',
      );
      final squat = exercises.firstWhere((exercise) => exercise.name == '스쿼트');

      final benchSessionId = await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 16, 9, 30),
          memo: '오전 벤치',
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
            ),
          ],
        ),
      );
      await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 16, 18),
          entries: [
            WorkoutEntryDraft(
              exerciseId: squat.id,
              sets: const [WorkoutSetDraft(weight: 100, reps: 5)],
            ),
          ],
        ),
      );

      final existing = await service.findWorkoutRecordForDateAndExercise(
        date: DateTime(2026, 5, 16, 23, 59),
        exerciseId: benchPress.id,
      );
      final missing = await service.findWorkoutRecordForDateAndExercise(
        date: DateTime(2026, 5, 17),
        exerciseId: benchPress.id,
      );

      expect(existing, isNotNull);
      expect(existing!.session.id, benchSessionId);
      expect(existing.entries, hasLength(1));
      expect(existing.entries.single.exercise.id, benchPress.id);
      expect(existing.entries.single.sets.single.weight, 60);
      expect(missing, isNull);
    },
  );

  test(
    'finds only the matching same-day exercise entry from a multi-entry session',
    () async {
      final exercises = await database.select(database.exercises).get();
      final benchPress = exercises.firstWhere(
        (exercise) => exercise.name == '벤치프레스',
      );
      final inclineBenchPress = exercises.firstWhere(
        (exercise) => exercise.name == '인클라인 벤치프레스',
      );
      final chestPress = exercises.firstWhere(
        (exercise) => exercise.name == '체스트프레스',
      );

      final sessionId = await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 16, 9, 30),
          memo: '가슴 운동',
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
            ),
            WorkoutEntryDraft(
              exerciseId: inclineBenchPress.id,
              sets: const [
                WorkoutSetDraft(weight: 80, reps: 8, isWarmup: true),
              ],
            ),
          ],
        ),
      );

      final existing = await service.findWorkoutRecordForDateAndExercise(
        date: DateTime(2026, 5, 16, 23, 59),
        exerciseId: inclineBenchPress.id,
      );
      final missing = await service.findWorkoutRecordForDateAndExercise(
        date: DateTime(2026, 5, 16, 23, 59),
        exerciseId: chestPress.id,
      );

      expect(existing, isNotNull);
      expect(existing!.session.id, sessionId);
      expect(existing.entries, hasLength(1));
      expect(existing.entries.single.exercise.id, inclineBenchPress.id);
      expect(existing.entries.single.sets.single.weight, 80);
      expect(existing.entries.single.sets.single.reps, 8);
      expect(existing.entries.single.sets.single.isWarmup, isTrue);
      expect(missing, isNull);
    },
  );

  test(
    'updates located same-day exercise record instead of creating a duplicate',
    () async {
      final benchPress = (await database.select(database.exercises).get())
          .firstWhere((exercise) => exercise.name == '벤치프레스');

      final originalSessionId = await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 16, 9, 30),
          memo: '수정 전',
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
            ),
          ],
        ),
      );

      final existing = await service.findWorkoutRecordForDateAndExercise(
        date: DateTime(2026, 5, 16, 20),
        exerciseId: benchPress.id,
      );

      expect(existing, isNotNull);
      final existingEntry = existing!.entries.single;
      await service.updateWorkoutEntry(
        sessionId: existing.session.id,
        entryId: existingEntry.entry.id,
        draft: WorkoutDraft(
          workoutDate: DateTime(2026, 5, 16),
          memo: '수정 후',
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [
                WorkoutSetDraft(weight: 65, reps: 8),
                WorkoutSetDraft(weight: 70, reps: 6, isWarmup: true),
              ],
            ),
          ],
        ),
      );

      final records = await service.getWorkoutRecords(
        from: DateTime(2026, 5, 16),
        to: DateTime(2026, 5, 17),
        exerciseId: benchPress.id,
      );

      expect(records, hasLength(1));
      expect(records.single.session.id, originalSessionId);
      expect(records.single.session.memo, '수정 후');
      expect(records.single.entries, hasLength(1));
      expect(records.single.entries.single.entry.id, existingEntry.entry.id);
      expect(records.single.entries.single.exercise.id, benchPress.id);
      expect(records.single.entries.single.sets.map((set) => set.weight), [
        65,
        70,
      ]);
      expect(records.single.entries.single.sets.map((set) => set.reps), [8, 6]);
      expect(records.single.entries.single.sets.map((set) => set.isWarmup), [
        false,
        true,
      ]);
    },
  );

  test(
    'finds immediately previous exercise entry before a selected date',
    () async {
      final exercises = await database.select(database.exercises).get();
      final benchPress = exercises.firstWhere(
        (exercise) => exercise.name == '벤치프레스',
      );
      final squat = exercises.firstWhere((exercise) => exercise.name == '스쿼트');

      await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 14),
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 50, reps: 12)],
            ),
          ],
        ),
      );
      await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 15),
          entries: [
            WorkoutEntryDraft(
              exerciseId: squat.id,
              sets: const [WorkoutSetDraft(weight: 100, reps: 5)],
            ),
          ],
        ),
      );
      await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 16),
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
            ),
          ],
        ),
      );
      await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 17),
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 70, reps: 8)],
            ),
          ],
        ),
      );

      final previous = await service.findPreviousWorkoutEntryForExercise(
        beforeDate: DateTime(2026, 5, 17),
        exerciseId: benchPress.id,
      );
      final missing = await service.findPreviousWorkoutEntryForExercise(
        beforeDate: DateTime(2026, 5, 14),
        exerciseId: benchPress.id,
      );

      expect(previous, isNotNull);
      expect(previous!.sets.single.weight, 60);
      expect(previous.sets.single.reps, 10);
      expect(missing, isNull);
    },
  );

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

  test(
    'paginates workout records with stable date and session cursor',
    () async {
      final benchPress = (await database.select(database.exercises).get())
          .firstWhere((exercise) => exercise.name == '벤치프레스');

      for (var day = 1; day <= 5; day++) {
        await service.saveWorkout(
          WorkoutDraft(
            workoutDate: DateTime(2026, 5, day),
            entries: [
              WorkoutEntryDraft(
                exerciseId: benchPress.id,
                sets: [
                  WorkoutSetDraft(weight: (60 + day).toDouble(), reps: 10),
                ],
              ),
            ],
          ),
        );
      }
      final sameDayFirstId = await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 6),
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 70, reps: 5)],
            ),
          ],
        ),
      );
      final sameDaySecondId = await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 6),
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 75, reps: 5)],
            ),
          ],
        ),
      );

      final firstPage = await service.getWorkoutRecords(limit: 3);

      expect(firstPage, hasLength(3));
      expect(firstPage[0].session.id, sameDaySecondId);
      expect(firstPage[1].session.id, sameDayFirstId);
      expect(firstPage.map((record) => record.session.workoutDate.day), [
        6,
        6,
        5,
      ]);

      final cursor = firstPage.last.session;
      final secondPage = await service.getWorkoutRecords(
        limit: 3,
        beforeDate: cursor.workoutDate,
        beforeSessionId: cursor.id,
      );

      expect(secondPage.map((record) => record.session.workoutDate.day), [
        4,
        3,
        2,
      ]);
      expect({
        ...firstPage,
        ...secondPage,
      }, hasLength(firstPage.length + secondPage.length));
    },
  );

  test('counts all workout sets independently from paged records', () async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');

    await service.saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 16),
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [
              WorkoutSetDraft(weight: 60, reps: 10),
              WorkoutSetDraft(weight: 65, reps: 8),
            ],
          ),
        ],
      ),
    );
    await service.saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 17),
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [WorkoutSetDraft(weight: 70, reps: 5)],
          ),
        ],
      ),
    );

    expect(await service.getWorkoutRecords(limit: 1), hasLength(1));
    expect(await service.getWorkoutSetCount(), 3);
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
