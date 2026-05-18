import '../data/workout_repository.dart';
import '../models/workout_draft.dart';
import '../models/workout_record.dart';

class WorkoutService {
  WorkoutService(this._repository);

  final WorkoutRepository _repository;

  Future<int> saveWorkout(WorkoutDraft draft) {
    _validateDraft(draft);
    return _repository.saveWorkout(draft);
  }

  Future<void> updateWorkoutEntry({
    required int sessionId,
    required int entryId,
    required WorkoutDraft draft,
  }) {
    _validateDraft(draft);
    return _repository.updateWorkoutEntry(
      sessionId: sessionId,
      entryId: entryId,
      draft: draft,
    );
  }

  Future<List<WorkoutRecord>> getWorkoutRecords({
    DateTime? from,
    DateTime? to,
    int? bodyPartId,
    int? exerciseId,
  }) {
    return _repository.getWorkoutRecords(
      from: from,
      to: to,
      bodyPartId: bodyPartId,
      exerciseId: exerciseId,
    );
  }

  Future<void> deleteSession(int sessionId) =>
      _repository.deleteSession(sessionId);

  Future<void> deleteWorkoutEntry({
    required int sessionId,
    required int entryId,
  }) => _repository.deleteWorkoutEntry(sessionId: sessionId, entryId: entryId);
}

void _validateDraft(WorkoutDraft draft) {
  if (draft.entries.isEmpty) {
    throw ArgumentError.value(draft.entries, 'entries', '운동은 1개 이상 필요합니다.');
  }

  for (final entry in draft.entries) {
    if (entry.exerciseId <= 0) {
      throw ArgumentError.value(
        entry.exerciseId,
        'exerciseId',
        '유효하지 않은 운동입니다.',
      );
    }
    if (entry.sets.isEmpty) {
      throw ArgumentError.value(entry.sets, 'sets', '세트는 1개 이상 필요합니다.');
    }
    for (final set in entry.sets) {
      if (set.weight < 0) {
        throw ArgumentError.value(set.weight, 'weight', '무게는 0 이상이어야 합니다.');
      }
      if (set.reps < 1) {
        throw ArgumentError.value(set.reps, 'reps', '횟수는 1 이상이어야 합니다.');
      }
    }
  }
}
