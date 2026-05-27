class WorkoutDraft {
  const WorkoutDraft({
    required this.workoutDate,
    required this.entries,
    this.memo,
  });

  final DateTime workoutDate;
  final String? memo;
  final List<WorkoutEntryDraft> entries;
}

class WorkoutEntryDraft {
  const WorkoutEntryDraft({
    required this.exerciseId,
    required this.sets,
    this.memo,
  });

  final int exerciseId;
  final String? memo;
  final List<WorkoutSetDraft> sets;
}

class WorkoutSetDraft {
  const WorkoutSetDraft({
    required this.weight,
    required this.reps,
    this.weightUnit = workoutWeightUnitKg,
    this.isWarmup = false,
  });

  final double weight;
  final String weightUnit;
  final int reps;
  final bool isWarmup;
}

const String workoutWeightUnitKg = 'kg';
const String workoutWeightUnitLbs = 'lbs';
const double workoutKgToLbs = 2.20462;

double workoutWeightInKg(double weight, String? weightUnit) {
  return switch (weightUnit) {
    workoutWeightUnitLbs => weight / workoutKgToLbs,
    _ => weight,
  };
}

String normalizeWorkoutWeightUnit(String? weightUnit) {
  return weightUnit == workoutWeightUnitLbs
      ? workoutWeightUnitLbs
      : workoutWeightUnitKg;
}
