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
}
