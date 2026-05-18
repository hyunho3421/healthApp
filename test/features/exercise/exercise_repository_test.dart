import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_growth_diary/core/db/app_database.dart';
import 'package:muscle_growth_diary/features/exercise/data/exercise_repository.dart';
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
}
