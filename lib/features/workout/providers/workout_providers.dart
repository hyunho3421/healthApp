import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/providers/app_database_provider.dart';
import '../application/workout_service.dart';
import '../data/workout_repository.dart';

final workoutRepositoryProvider = Provider<WorkoutRepository>((ref) {
  return WorkoutRepository(ref.watch(appDatabaseProvider));
});

final workoutServiceProvider = Provider<WorkoutService>((ref) {
  return WorkoutService(ref.watch(workoutRepositoryProvider));
});
