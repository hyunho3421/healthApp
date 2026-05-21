import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/seed/workout_seed_data.dart';
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

  Future<Exercise?> findExerciseById(int id) {
    return (_database.select(
      _database.exercises,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
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
    String? armDetail,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', '운동명은 비어 있을 수 없습니다.');
    }
    if (!exerciseTypeIds.contains(type)) {
      throw ArgumentError.value(type, 'type', '지원하지 않는 운동 유형입니다.');
    }
    final effectiveArmDetail = await _validateArmDetail(
      bodyPartId: bodyPartId,
      armDetail: armDetail,
    );

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
            armDetail: Value(effectiveArmDetail),
            isCustom: const Value(true),
          ),
        );
  }

  Future<int> countWorkoutEntriesForExercise(int exerciseId) async {
    final count = _database.workoutEntries.id.count();
    final query = _database.selectOnly(_database.workoutEntries)
      ..addColumns([count])
      ..where(_database.workoutEntries.exerciseId.equals(exerciseId));
    return await query.map((row) => row.read(count) ?? 0).getSingle();
  }

  Future<void> updateCustomExercise({
    required int id,
    required int bodyPartId,
    required String name,
    required String type,
    String? armDetail,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', '운동명은 비어 있을 수 없습니다.');
    }
    if (!exerciseTypeIds.contains(type)) {
      throw ArgumentError.value(type, 'type', '지원하지 않는 운동 유형입니다.');
    }
    final effectiveArmDetail = await _validateArmDetail(
      bodyPartId: bodyPartId,
      armDetail: armDetail,
    );

    final current = await findExerciseById(id);
    if (current == null || !current.isCustom) {
      throw StateError('사용자 등록 운동만 수정할 수 있습니다.');
    }

    final existing = await findExerciseByName(
      bodyPartId: bodyPartId,
      name: trimmedName,
    );
    if (existing != null && existing.id != id) {
      throw StateError('이미 등록된 운동입니다: $trimmedName');
    }

    final entryCount = await countWorkoutEntriesForExercise(id);
    if (entryCount > 0 && current.type != type) {
      throw StateError('기록에서 사용 중인 운동은 운동 유형을 바꿀 수 없습니다.');
    }

    final updated =
        await (_database.update(_database.exercises)..where(
              (table) => table.id.equals(id) & table.isCustom.equals(true),
            ))
            .write(
              ExercisesCompanion(
                bodyPartId: Value(bodyPartId),
                name: Value(trimmedName),
                type: Value(type),
                armDetail: Value(effectiveArmDetail),
                updatedAt: Value(DateTime.now()),
              ),
            );
    if (updated == 0) {
      throw StateError('사용자 등록 운동만 수정할 수 있습니다.');
    }
  }

  Future<String?> _validateArmDetail({
    required int bodyPartId,
    required String? armDetail,
  }) async {
    final bodyPart = await (_database.select(
      _database.bodyParts,
    )..where((table) => table.id.equals(bodyPartId))).getSingleOrNull();
    if (bodyPart == null) {
      throw ArgumentError.value(bodyPartId, 'bodyPartId', '존재하지 않는 부위입니다.');
    }
    if (bodyPart.name != '팔') {
      return null;
    }
    if (armDetail != armDetailBiceps && armDetail != armDetailTriceps) {
      throw ArgumentError.value(
        armDetail,
        'armDetail',
        '팔 운동은 이두/삼두를 선택해 주세요.',
      );
    }
    return armDetail;
  }

  Future<void> deleteCustomExercise(int id) async {
    final current = await findExerciseById(id);
    if (current == null || !current.isCustom) {
      throw StateError('사용자 등록 운동만 삭제할 수 있습니다.');
    }

    final entryCount = await countWorkoutEntriesForExercise(id);
    if (entryCount > 0) {
      throw StateError('이 운동은 기록 $entryCount개에서 사용 중이라 삭제할 수 없습니다.');
    }

    await (_database.delete(_database.exercises)
          ..where((table) => table.id.equals(id) & table.isCustom.equals(true)))
        .go();
  }
}
