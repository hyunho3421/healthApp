import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_growth_diary/core/db/app_database.dart';
import 'package:muscle_growth_diary/core/db/seed/workout_seed_data.dart';
import 'package:muscle_growth_diary/features/exercise/data/exercise_repository.dart';
import 'package:muscle_growth_diary/features/workout/application/workout_service.dart';
import 'package:muscle_growth_diary/features/workout/data/workout_repository.dart';
import 'package:muscle_growth_diary/features/workout/models/workout_draft.dart';
import 'package:muscle_growth_diary/core/models/exercise_type.dart';

void main() {
  late AppDatabase database;
  late ExerciseRepository repository;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    repository = ExerciseRepository(database);
    await database.seedInitialData();
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'adds custom exercise and prevents duplicates in same body part',
    () async {
      final chest = (await repository.getBodyParts()).firstWhere(
        (part) => part.name == '가슴',
      );

      final id = await repository.addCustomExercise(
        bodyPartId: chest.id,
        name: '덤벨 플라이',
        type: defaultExerciseTypeId,
      );

      final exercise = await repository.findExerciseByName(
        bodyPartId: chest.id,
        name: '덤벨 플라이',
      );

      expect(exercise?.id, id);
      expect(exercise?.isCustom, isTrue);
      expect(exercise?.type, defaultExerciseTypeId);
      expect(
        () => repository.addCustomExercise(
          bodyPartId: chest.id,
          name: '덤벨 플라이',
          type: defaultExerciseTypeId,
        ),
        throwsStateError,
      );
    },
  );

  test('adds custom arm exercise with required arm detail', () async {
    final arm = (await repository.getBodyParts()).firstWhere(
      (part) => part.name == '팔',
    );

    expect(
      () => repository.addCustomExercise(
        bodyPartId: arm.id,
        name: '바벨 컬',
        type: defaultExerciseTypeId,
      ),
      throwsArgumentError,
    );

    final id = await repository.addCustomExercise(
      bodyPartId: arm.id,
      name: '바벨 컬',
      type: defaultExerciseTypeId,
      armDetail: armDetailBiceps,
    );

    final exercise = await repository.findExerciseById(id);
    expect(exercise?.armDetail, armDetailBiceps);
  });

  test(
    'clears arm detail when custom exercise is moved away from arms',
    () async {
      final parts = await repository.getBodyParts();
      final arm = parts.firstWhere((part) => part.name == '팔');
      final chest = parts.firstWhere((part) => part.name == '가슴');
      final customId = await repository.addCustomExercise(
        bodyPartId: arm.id,
        name: '해머 컬',
        type: defaultExerciseTypeId,
        armDetail: armDetailBiceps,
      );

      await repository.updateCustomExercise(
        id: customId,
        bodyPartId: chest.id,
        name: '해머 컬',
        type: defaultExerciseTypeId,
        armDetail: armDetailBiceps,
      );

      final updated = await repository.findExerciseById(customId);
      expect(updated?.bodyPartId, chest.id);
      expect(updated?.armDetail, isNull);
    },
  );

  test('adds custom exercise with selected exercise type', () async {
    final chest = (await repository.getBodyParts()).firstWhere(
      (part) => part.name == '가슴',
    );

    await repository.addCustomExercise(
      bodyPartId: chest.id,
      name: '러닝머신',
      type: 'cardio',
    );

    final exercise = await repository.findExerciseByName(
      bodyPartId: chest.id,
      name: '러닝머신',
    );

    expect(exercise?.type, 'cardio');
  });

  test('updates custom exercise and protects seeded exercises', () async {
    final parts = await repository.getBodyParts();
    final chest = parts.firstWhere((part) => part.name == '가슴');
    final back = parts.firstWhere((part) => part.name == '등');
    final customId = await repository.addCustomExercise(
      bodyPartId: chest.id,
      name: '덤벨 플라이',
      type: defaultExerciseTypeId,
    );

    await repository.updateCustomExercise(
      id: customId,
      bodyPartId: back.id,
      name: '인클라인 덤벨 플라이',
      type: 'bodyweight',
    );

    final updated = await repository.findExerciseById(customId);
    expect(updated?.bodyPartId, back.id);
    expect(updated?.name, '인클라인 덤벨 플라이');
    expect(updated?.type, 'bodyweight');

    final seededExercise = (await repository.getExercises(
      bodyPartId: chest.id,
    )).firstWhere((exercise) => !exercise.isCustom);
    expect(
      () => repository.updateCustomExercise(
        id: seededExercise.id,
        bodyPartId: chest.id,
        name: '수정 금지',
        type: defaultExerciseTypeId,
      ),
      throwsStateError,
    );
  });

  test(
    'blocks type changes and deletion when custom exercise is used',
    () async {
      final chest = (await repository.getBodyParts()).firstWhere(
        (part) => part.name == '가슴',
      );
      final customId = await repository.addCustomExercise(
        bodyPartId: chest.id,
        name: '덤벨 플라이',
        type: defaultExerciseTypeId,
      );
      await WorkoutService(WorkoutRepository(database)).saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 18),
          entries: [
            WorkoutEntryDraft(
              exerciseId: customId,
              sets: const [WorkoutSetDraft(weight: 10, reps: 12)],
            ),
          ],
        ),
      );

      expect(await repository.countWorkoutEntriesForExercise(customId), 1);
      expect(
        () => repository.updateCustomExercise(
          id: customId,
          bodyPartId: chest.id,
          name: '덤벨 플라이 수정',
          type: 'cardio',
        ),
        throwsStateError,
      );
      expect(() => repository.deleteCustomExercise(customId), throwsStateError);

      await repository.updateCustomExercise(
        id: customId,
        bodyPartId: chest.id,
        name: '덤벨 플라이 수정',
        type: defaultExerciseTypeId,
      );
      expect((await repository.findExerciseById(customId))?.name, '덤벨 플라이 수정');
    },
  );

  test('deletes unused custom exercise only', () async {
    final chest = (await repository.getBodyParts()).firstWhere(
      (part) => part.name == '가슴',
    );
    final customId = await repository.addCustomExercise(
      bodyPartId: chest.id,
      name: '케이블 크로스오버',
      type: defaultExerciseTypeId,
    );

    await repository.deleteCustomExercise(customId);

    expect(await repository.findExerciseById(customId), isNull);
  });
}
