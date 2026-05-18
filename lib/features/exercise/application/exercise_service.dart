import '../../../core/db/app_database.dart';
import '../data/exercise_repository.dart';

class ExerciseService {
  ExerciseService(this._repository);

  final ExerciseRepository _repository;

  Future<List<BodyPart>> getBodyParts() => _repository.getBodyParts();

  Future<List<Exercise>> getExercises({int? bodyPartId}) {
    return _repository.getExercises(bodyPartId: bodyPartId);
  }

  Future<int> addCustomExercise({
    required int bodyPartId,
    required String name,
    required String type,
  }) {
    return _repository.addCustomExercise(
      bodyPartId: bodyPartId,
      name: name,
      type: type,
    );
  }

  Future<Exercise?> findExerciseById(int id) =>
      _repository.findExerciseById(id);

  Future<int> countWorkoutEntriesForExercise(int exerciseId) {
    return _repository.countWorkoutEntriesForExercise(exerciseId);
  }

  Future<void> updateCustomExercise({
    required int id,
    required int bodyPartId,
    required String name,
    required String type,
  }) {
    return _repository.updateCustomExercise(
      id: id,
      bodyPartId: bodyPartId,
      name: name,
      type: type,
    );
  }

  Future<void> deleteCustomExercise(int id) {
    return _repository.deleteCustomExercise(id);
  }
}
