class BodyPartSeed {
  const BodyPartSeed({required this.name, required this.sortOrder});

  final String name;
  final int sortOrder;
}

class ExerciseSeed {
  const ExerciseSeed({
    required this.bodyPartName,
    required this.name,
    required this.type,
  });

  final String bodyPartName;
  final String name;
  final String type;
}

const bodyPartSeeds = <BodyPartSeed>[
  BodyPartSeed(name: '가슴', sortOrder: 0),
  BodyPartSeed(name: '등', sortOrder: 1),
  BodyPartSeed(name: '어깨', sortOrder: 2),
  BodyPartSeed(name: '하체', sortOrder: 3),
  BodyPartSeed(name: '팔', sortOrder: 4),
  BodyPartSeed(name: '코어', sortOrder: 5),
];

const exerciseSeeds = <ExerciseSeed>[
  ExerciseSeed(bodyPartName: '가슴', name: '벤치프레스', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '가슴', name: '인클라인 벤치프레스', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '가슴', name: '체스트프레스', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '가슴', name: '푸시업', type: 'bodyweight'),
  ExerciseSeed(bodyPartName: '가슴', name: '케이블크로스오버', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '등', name: '랫풀다운', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '등', name: '바벨로우', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '등', name: '데드리프트', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '등', name: '풀업', type: 'bodyweight'),
  ExerciseSeed(bodyPartName: '등', name: '케이블로우', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '어깨', name: '오버헤드프레스', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '어깨', name: '숄더프레스', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '어깨', name: '레터럴레이즈', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '어깨', name: '페이스풀', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '하체', name: '스쿼트', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '하체', name: '레그프레스', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '하체', name: '레그익스텐션', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '하체', name: '스쿼트(맨몸)', type: 'bodyweight'),
  ExerciseSeed(bodyPartName: '팔', name: '덤벨컬', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '팔', name: '케이블푸쉬다운', type: 'weight_machine'),
  ExerciseSeed(bodyPartName: '코어', name: '크런치', type: 'bodyweight'),
  ExerciseSeed(bodyPartName: '코어', name: '플랭크', type: 'bodyweight'),
];
