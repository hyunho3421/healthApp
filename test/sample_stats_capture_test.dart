import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_growth_diary/core/db/app_database.dart';
import 'package:muscle_growth_diary/features/database/providers/app_database_provider.dart';
import 'package:muscle_growth_diary/features/stats/application/stats_service.dart';
import 'package:muscle_growth_diary/features/stats/data/stats_repository.dart';
import 'package:muscle_growth_diary/features/workout/application/workout_service.dart';
import 'package:muscle_growth_diary/features/workout/data/workout_repository.dart';
import 'package:muscle_growth_diary/features/workout/models/workout_draft.dart';
import 'package:muscle_growth_diary/main.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    await database.seedInitialData();
    await _insertSampleBenchPressData(database);
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets('capture stats screen with sample data', (tester) async {
    await _loadAppFonts();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('통계'));
    await tester.pumpAndSettle();

    expect(find.text('기간별 운동 통계'), findsOneWidget);
    expect(find.text('관심 운동'), findsOneWidget);
    expect(find.text('벤치프레스'), findsOneWidget);
    expect(find.text('월간'), findsOneWidget);
    expect(find.text('2026년 5월 11일 주 기준'), findsOneWidget);
    expect(find.text('주 최고 중량'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);

    await expectLater(
      find.byType(MyApp),
      matchesGoldenFile('goldens/sample_stats_bench_press.png'),
    );
  });
}

Future<void> _insertSampleBenchPressData(AppDatabase database) async {
  final workoutService = WorkoutService(WorkoutRepository(database));
  final statsService = StatsService(StatsRepository(database));
  final benchPress = (await database.select(database.exercises).get())
      .firstWhere((exercise) => exercise.name == '벤치프레스');

  await statsService.addFavoriteExercise(benchPress.id);

  await workoutService.saveWorkout(
    WorkoutDraft(
      workoutDate: DateTime(2026, 3, 12),
      entries: [
        WorkoutEntryDraft(
          exerciseId: benchPress.id,
          sets: const [
            WorkoutSetDraft(weight: 55, reps: 10),
            WorkoutSetDraft(weight: 60, reps: 8),
            WorkoutSetDraft(weight: 62.5, reps: 6),
          ],
        ),
      ],
    ),
  );
  await workoutService.saveWorkout(
    WorkoutDraft(
      workoutDate: DateTime(2026, 4, 9),
      entries: [
        WorkoutEntryDraft(
          exerciseId: benchPress.id,
          sets: const [
            WorkoutSetDraft(weight: 62.5, reps: 10),
            WorkoutSetDraft(weight: 67.5, reps: 8),
            WorkoutSetDraft(weight: 70, reps: 5),
          ],
        ),
      ],
    ),
  );
  await workoutService.saveWorkout(
    WorkoutDraft(
      workoutDate: DateTime(2026, 5, 16),
      entries: [
        WorkoutEntryDraft(
          exerciseId: benchPress.id,
          sets: const [
            WorkoutSetDraft(weight: 70, reps: 10),
            WorkoutSetDraft(weight: 75, reps: 8),
            WorkoutSetDraft(weight: 80, reps: 5),
          ],
        ),
      ],
    ),
  );
}

Future<void> _loadAppFonts() async {
  final fontData = await rootBundle.load('assets/fonts/NotoSansKR[wght].ttf');
  await (FontLoader('Noto Sans KR')..addFont(Future.value(fontData))).load();

  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) {
    return;
  }
  final iconFont = File(
    '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  final iconFontData = iconFont.readAsBytesSync().buffer.asByteData();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(Future<ByteData>.value(iconFontData))).load();
}
