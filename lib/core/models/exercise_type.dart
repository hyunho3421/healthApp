class ExerciseType {
  const ExerciseType({
    required this.id,
    required this.label,
    required this.met,
  });

  final String id;
  final String label;
  final double met;
}

const defaultExerciseTypeId = 'weight_machine';

const exerciseTypes = <ExerciseType>[
  ExerciseType(id: 'weight_machine', label: '웨이트·머신', met: 3.5),
  ExerciseType(id: 'bodyweight', label: '맨몸 운동', met: 4.0),
  ExerciseType(id: 'cardio', label: '유산소', met: 7.0),
  ExerciseType(id: 'stretching_yoga', label: '스트레칭·요가', met: 2.3),
];

const exerciseTypeIds = {
  'weight_machine',
  'bodyweight',
  'cardio',
  'stretching_yoga',
};

ExerciseType exerciseTypeById(String? id) {
  return exerciseTypes.firstWhere(
    (type) => type.id == id,
    orElse: () => exerciseTypes.first,
  );
}

double metForExerciseType(String? id) => exerciseTypeById(id).met;

String labelForExerciseType(String? id) => exerciseTypeById(id).label;

String normalizeExerciseTypeId(String? id) {
  return exerciseTypeIds.contains(id) ? id! : defaultExerciseTypeId;
}
