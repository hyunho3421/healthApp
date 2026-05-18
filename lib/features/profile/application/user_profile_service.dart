import '../data/user_profile_repository.dart';

class UserProfileService {
  UserProfileService(this._repository);

  final UserProfileRepository _repository;

  Future<double?> getBodyWeightKg() => _repository.getBodyWeightKg();

  Future<void> saveBodyWeightKg(double bodyWeightKg) {
    if (bodyWeightKg < 20 || bodyWeightKg > 300) {
      throw ArgumentError.value(
        bodyWeightKg,
        'bodyWeightKg',
        '체중은 20kg 이상 300kg 이하로 입력해주세요.',
      );
    }
    return _repository.saveBodyWeightKg(bodyWeightKg);
  }
}
