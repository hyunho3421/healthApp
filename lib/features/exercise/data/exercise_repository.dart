import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/models/exercise_type.dart';

class ExerciseRepository {
  ExerciseRepository(this._database);

  final AppDatabase _database;

  Future<List<BodyPart>> getBodyParts() {
    return (_database.select(
      _database.bodyParts,
    )..orderBy([(table) => OrderingTerm.asc(table.sortOrder)])).get();
  }

  Future<List<Exercise>> getExercises({int? bodyPartId}) {
    final query = _database.select(_database.exercises)
      ..orderBy([(table) => OrderingTerm.asc(table.name)]);

    if (bodyPartId != null) {
      query.where((table) => table.bodyPartId.equals(bodyPartId));
    }

    return query.get();
  }

  Future<Exercise?> findExerciseByName({
    required int bodyPartId,
    required String name,
  }) {
    return (_database.select(_database.exercises)..where(
          (table) =>
              table.bodyPartId.equals(bodyPartId) & table.name.equals(name),
        ))
        .getSingleOrNull();
  }

  Future<int> addCustomExercise({
    required int bodyPartId,
    required String name,
    required String type,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', '운동명은 비어 있을 수 없습니다.');
    }
    if (!exerciseTypeIds.contains(type)) {
      throw ArgumentError.value(type, 'type', '지원하지 않는 운동 유형입니다.');
    }

    final existing = await findExerciseByName(
      bodyPartId: bodyPartId,
      name: trimmedName,
    );
    if (existing != null) {
      throw StateError('이미 등록된 운동입니다: $trimmedName');
    }

    return _database
        .into(_database.exercises)
        .insert(
          ExercisesCompanion.insert(
            bodyPartId: bodyPartId,
            name: trimmedName,
            type: type,
            isCustom: const Value(true),
          ),
        );
  }
}
