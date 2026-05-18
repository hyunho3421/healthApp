import '../../../core/db/app_database.dart';

class WorkoutRecord {
  const WorkoutRecord({required this.session, required this.entries});

  final WorkoutSession session;
  final List<WorkoutEntryRecord> entries;
}

class WorkoutEntryRecord {
  const WorkoutEntryRecord({
    required this.entry,
    required this.exercise,
    required this.bodyPart,
    required this.sets,
  });

  final WorkoutEntry entry;
  final Exercise exercise;
  final BodyPart bodyPart;
  final List<WorkoutSet> sets;
}
