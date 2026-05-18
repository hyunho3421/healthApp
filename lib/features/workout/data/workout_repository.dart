import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../models/workout_draft.dart';
import '../models/workout_record.dart';

class WorkoutRepository {
  WorkoutRepository(this._database);

  final AppDatabase _database;

  Future<int> saveWorkout(WorkoutDraft draft) {
    return _database.transaction(() async {
      final sessionId = await _database
          .into(_database.workoutSessions)
          .insert(
            WorkoutSessionsCompanion.insert(
              workoutDate: draft.workoutDate,
              memo: Value(_emptyToNull(draft.memo)),
            ),
          );

      for (
        var entryIndex = 0;
        entryIndex < draft.entries.length;
        entryIndex++
      ) {
        final entry = draft.entries[entryIndex];
        final entryId = await _database
            .into(_database.workoutEntries)
            .insert(
              WorkoutEntriesCompanion.insert(
                sessionId: sessionId,
                exerciseId: entry.exerciseId,
                orderIndex: Value(entryIndex),
                memo: Value(_emptyToNull(entry.memo)),
              ),
            );

        for (var setIndex = 0; setIndex < entry.sets.length; setIndex++) {
          final set = entry.sets[setIndex];
          await _database
              .into(_database.workoutSets)
              .insert(
                WorkoutSetsCompanion.insert(
                  entryId: entryId,
                  setNumber: setIndex + 1,
                  weight: set.weight,
                  reps: set.reps,
                  isWarmup: Value(set.isWarmup),
                ),
              );
        }
      }

      return sessionId;
    });
  }

  Future<void> updateWorkoutEntry({
    required int sessionId,
    required int entryId,
    required WorkoutDraft draft,
  }) {
    return _database.transaction(() async {
      if (draft.entries.length != 1) {
        throw ArgumentError.value(
          draft.entries,
          'entries',
          '수정할 운동은 1개여야 합니다.',
        );
      }

      final now = DateTime.now();
      final updatedSessions =
          await (_database.update(
            _database.workoutSessions,
          )..where((table) => table.id.equals(sessionId))).write(
            WorkoutSessionsCompanion(
              workoutDate: Value(draft.workoutDate),
              memo: Value(_emptyToNull(draft.memo)),
              updatedAt: Value(now),
            ),
          );
      if (updatedSessions != 1) {
        throw StateError('수정할 운동 기록을 찾을 수 없습니다.');
      }

      final entry = draft.entries.single;
      final updatedEntries =
          await (_database.update(_database.workoutEntries)..where(
                (table) =>
                    table.id.equals(entryId) &
                    table.sessionId.equals(sessionId),
              ))
              .write(
                WorkoutEntriesCompanion(
                  exerciseId: Value(entry.exerciseId),
                  memo: Value(_emptyToNull(entry.memo)),
                  updatedAt: Value(now),
                ),
              );
      if (updatedEntries != 1) {
        throw StateError('수정할 운동 항목을 찾을 수 없습니다.');
      }

      await (_database.delete(
        _database.workoutSets,
      )..where((table) => table.entryId.equals(entryId))).go();

      for (var setIndex = 0; setIndex < entry.sets.length; setIndex++) {
        final set = entry.sets[setIndex];
        await _database
            .into(_database.workoutSets)
            .insert(
              WorkoutSetsCompanion.insert(
                entryId: entryId,
                setNumber: setIndex + 1,
                weight: set.weight,
                reps: set.reps,
                isWarmup: Value(set.isWarmup),
                updatedAt: Value(now),
              ),
            );
      }
    });
  }

  Future<List<WorkoutRecord>> getWorkoutRecords({
    DateTime? from,
    DateTime? to,
    int? bodyPartId,
    int? exerciseId,
  }) async {
    final sessionQuery = _database.select(_database.workoutSessions)
      ..orderBy([(table) => OrderingTerm.desc(table.workoutDate)]);

    if (from != null) {
      sessionQuery.where(
        (table) => table.workoutDate.isBiggerOrEqualValue(from),
      );
    }
    if (to != null) {
      sessionQuery.where((table) => table.workoutDate.isSmallerThanValue(to));
    }

    final sessions = await sessionQuery.get();
    final records = <WorkoutRecord>[];

    for (final session in sessions) {
      final entryRows = await _entriesForSession(
        session.id,
        bodyPartId: bodyPartId,
        exerciseId: exerciseId,
      );
      if (entryRows.isEmpty) {
        continue;
      }

      final entryRecords = <WorkoutEntryRecord>[];
      for (final row in entryRows) {
        final sets =
            await (_database.select(_database.workoutSets)
                  ..where((table) => table.entryId.equals(row.entry.id))
                  ..orderBy([(table) => OrderingTerm.asc(table.setNumber)]))
                .get();
        entryRecords.add(
          WorkoutEntryRecord(
            entry: row.entry,
            exercise: row.exercise,
            bodyPart: row.bodyPart,
            sets: sets,
          ),
        );
      }

      records.add(WorkoutRecord(session: session, entries: entryRecords));
    }

    return records;
  }

  Future<void> deleteSession(int sessionId) {
    return (_database.delete(
      _database.workoutSessions,
    )..where((table) => table.id.equals(sessionId))).go();
  }

  Future<void> deleteWorkoutEntry({
    required int sessionId,
    required int entryId,
  }) {
    return _database.transaction(() async {
      final deletedEntries =
          await (_database.delete(_database.workoutEntries)..where(
                (table) =>
                    table.id.equals(entryId) &
                    table.sessionId.equals(sessionId),
              ))
              .go();
      if (deletedEntries != 1) {
        throw StateError('삭제할 운동 기록을 찾을 수 없습니다.');
      }

      final remainingEntries =
          await (_database.select(_database.workoutEntries)
                ..where((table) => table.sessionId.equals(sessionId))
                ..limit(1))
              .get();
      if (remainingEntries.isEmpty) {
        await (_database.delete(
          _database.workoutSessions,
        )..where((table) => table.id.equals(sessionId))).go();
      } else {
        await (_database.update(_database.workoutSessions)
              ..where((table) => table.id.equals(sessionId)))
            .write(WorkoutSessionsCompanion(updatedAt: Value(DateTime.now())));
      }
    });
  }

  Future<List<_EntryJoinRow>> _entriesForSession(
    int sessionId, {
    int? bodyPartId,
    int? exerciseId,
  }) async {
    final join =
        _database.select(_database.workoutEntries).join([
            innerJoin(
              _database.exercises,
              _database.exercises.id.equalsExp(
                _database.workoutEntries.exerciseId,
              ),
            ),
            innerJoin(
              _database.bodyParts,
              _database.bodyParts.id.equalsExp(_database.exercises.bodyPartId),
            ),
          ])
          ..where(_database.workoutEntries.sessionId.equals(sessionId))
          ..orderBy([OrderingTerm.asc(_database.workoutEntries.orderIndex)]);

    if (exerciseId != null) {
      join.where(_database.exercises.id.equals(exerciseId));
    }
    if (bodyPartId != null) {
      join.where(_database.bodyParts.id.equals(bodyPartId));
    }

    final rows = await join.get();
    return rows
        .map(
          (row) => _EntryJoinRow(
            entry: row.readTable(_database.workoutEntries),
            exercise: row.readTable(_database.exercises),
            bodyPart: row.readTable(_database.bodyParts),
          ),
        )
        .toList();
  }
}

class _EntryJoinRow {
  const _EntryJoinRow({
    required this.entry,
    required this.exercise,
    required this.bodyPart,
  });

  final WorkoutEntry entry;
  final Exercise exercise;
  final BodyPart bodyPart;
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
