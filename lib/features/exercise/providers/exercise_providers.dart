import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/providers/app_database_provider.dart';
import '../application/exercise_service.dart';
import '../data/exercise_repository.dart';

final exerciseRepositoryProvider = Provider<ExerciseRepository>((ref) {
  return ExerciseRepository(ref.watch(appDatabaseProvider));
});

final exerciseServiceProvider = Provider<ExerciseService>((ref) {
  return ExerciseService(ref.watch(exerciseRepositoryProvider));
});
