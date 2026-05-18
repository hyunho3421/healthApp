import '../../../core/db/app_database.dart';

class FavoriteExerciseSummary {
  const FavoriteExerciseSummary({
    required this.favorite,
    required this.exercise,
    required this.bodyPart,
    required this.stats,
  });

  final FavoriteExercise favorite;
  final Exercise exercise;
  final BodyPart bodyPart;
  final FavoriteExerciseStats stats;
}

class FavoriteExerciseStats {
  const FavoriteExerciseStats({
    required this.maxWeight,
    required this.maxWeightReps,
    required this.totalVolume,
    required this.setCount,
    required this.workoutDayCount,
    this.lastWorkoutDate,
  });

  const FavoriteExerciseStats.empty()
    : maxWeight = 0,
      maxWeightReps = 0,
      totalVolume = 0,
      setCount = 0,
      workoutDayCount = 0,
      lastWorkoutDate = null;

  final double maxWeight;
  final int maxWeightReps;
  final double totalVolume;
  final int setCount;
  final int workoutDayCount;
  final DateTime? lastWorkoutDate;

  bool get hasRecords => workoutDayCount > 0;
}
