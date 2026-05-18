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
    this.isWarmup = false,
  });

  final double weight;
  final int reps;
  final bool isWarmup;
}
