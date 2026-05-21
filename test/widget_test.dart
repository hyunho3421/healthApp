import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:muscle_growth_diary/core/db/app_database.dart';
import 'package:muscle_growth_diary/core/widgets/centered_toast.dart';
import 'package:muscle_growth_diary/features/database/providers/app_database_provider.dart';
import 'package:muscle_growth_diary/features/exercise/application/exercise_service.dart';
import 'package:muscle_growth_diary/features/exercise/data/exercise_repository.dart';
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
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> pickSheetOption(
    WidgetTester tester, {
    required String placeholder,
    required String option,
  }) async {
    await tester.tap(find.text(placeholder).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets('shows empty record list and opens add workout screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Muscle Diary'), findsOneWidget);
    expect(find.text('이번 주 운동 부위'), findsOneWidget);
    expect(find.text('휴식'), findsWidgets);
    expect(find.text('부위 필터'), findsNothing);
    expect(find.text('운동 필터'), findsNothing);
    expect(find.textContaining('아직 운동 기록이 없어요'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();

    expect(find.text('운동 기록 추가'), findsOneWidget);
    expect(find.text('날짜'), findsOneWidget);
    expect(find.text('부위'), findsOneWidget);
    expect(find.text('운동'), findsOneWidget);
    expect(find.text('1세트'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(find.text('저장'), findsOneWidget);
  });

  testWidgets('home body map card does not overflow on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('이번 주 부위별 운동'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom exercise registration saves selected exercise type', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('새 운동 등록'));
    await tester.pumpAndSettle();

    expect(find.text('운동 유형'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '웨이트·머신'), findsOneWidget);

    await pickSheetOption(tester, placeholder: '운동 부위 선택', option: '가슴');
    await tester.enterText(find.widgetWithText(TextFormField, '운동명'), '러닝머신');
    await tester.tap(find.widgetWithText(ChoiceChip, '유산소'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '등록'));
    await tester.pumpAndSettle();

    final repository = ExerciseRepository(database);
    final chest = (await repository.getBodyParts()).firstWhere(
      (part) => part.name == '가슴',
    );
    final exercise = await repository.findExerciseByName(
      bodyPartId: chest.id,
      name: '러닝머신',
    );

    expect(exercise?.type, 'cardio');

    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets('custom exercise can be edited and deleted from picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('새 운동 등록'));
    await tester.pumpAndSettle();
    await pickSheetOption(tester, placeholder: '운동 부위 선택', option: '가슴');
    await tester.enterText(find.widgetWithText(TextFormField, '운동명'), '덤벨 플라이');
    await tester.tap(find.widgetWithText(FilledButton, '등록'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('덤벨 플라이'));
    await tester.pumpAndSettle();
    expect(find.text('내 운동'), findsOneWidget);
    await tester.tap(find.byTooltip('내 운동 관리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('운동 수정'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, '운동명'),
      '덤벨 플라이 수정',
    );
    await tester.tap(find.widgetWithText(FilledButton, '수정'));
    await tester.pumpAndSettle();
    expect(find.text('운동을 수정했습니다.'), findsOneWidget);

    await tester.tap(find.text('덤벨 플라이 수정'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('내 운동 관리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('운동 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    final repository = ExerciseRepository(database);
    final chest = (await repository.getBodyParts()).firstWhere(
      (part) => part.name == '가슴',
    );
    final exercise = await repository.findExerciseByName(
      bodyPartId: chest.id,
      name: '덤벨 플라이 수정',
    );
    expect(exercise, isNull);

    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets(
    'custom exercise registration stays visible above keyboard on small screens',
    (tester) async {
      tester.view.physicalSize = const Size(390, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.view.resetViewInsets();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('새 운동 등록'));
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 340);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, '운동명'),
        '키보드 테스트',
      );
      await tester.pumpAndSettle();

      tester.takeException();
      expect(find.text('운동 유형'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '웨이트·머신'), findsOneWidget);

      final registerButton = find.widgetWithText(FilledButton, '등록');
      expect(registerButton, findsOneWidget);
      expect(tester.getBottomRight(registerButton).dy, lessThanOrEqualTo(300));
    },
  );

  testWidgets('centered toast replaces previous toast instead of stacking', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              CenteredToast.show(
                context,
                '첫 번째 안내',
                duration: const Duration(milliseconds: 10),
              );
              CenteredToast.show(
                context,
                '두 번째 안내',
                duration: const Duration(milliseconds: 10),
              );
            },
            child: const Text('토스트 표시'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('토스트 표시'));
    await tester.pump();

    expect(find.text('첫 번째 안내'), findsNothing);
    expect(find.text('두 번째 안내'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('두 번째 안내'), matching: find.byType(Center)),
      findsWidgets,
    );
    expect(find.byType(SnackBar), findsNothing);

    await tester.pump(const Duration(milliseconds: 10));
  });

  testWidgets('shows newly saved workout on home immediately', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pumpAndSettle();

    await pickSheetOption(tester, placeholder: '운동 부위 선택', option: '가슴');

    await pickSheetOption(tester, placeholder: '운동 선택', option: '벤치프레스');

    await tester.enterText(find.widgetWithText(TextFormField, '무게(kg)'), '60');
    await tester.enterText(find.widgetWithText(TextFormField, '횟수'), '10');
    await tester.ensureVisible(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(TextFormField, '메모'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, '메모'), '즉시 반영');

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(find.text('운동 기록 추가'), findsNothing);
    expect(find.text('운동 기록을 저장했습니다.'), findsOneWidget);
    expect(find.text('벤치프레스'), findsOneWidget);
    expect(find.text('가슴'), findsWidgets);
    expect(find.text('1세트'), findsOneWidget);
    expect(find.text('워밍업 1세트'), findsOneWidget);
    expect(find.text('볼륨'), findsWidgets);
    expect(find.text('600kg'), findsWidgets);
    expect(find.textContaining('kcal'), findsWidgets);
    final savedRecord = (await WorkoutService(
      WorkoutRepository(database),
    ).getWorkoutRecords()).single.entries.single;
    expect(savedRecord.sets.single.isWarmup, isTrue);
    expect(find.text('즉시 반영'), findsOneWidget);
    expect(find.textContaining('아직 운동 기록이 없어요'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets('shows saved workout record summary', (tester) async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');
    await WorkoutService(WorkoutRepository(database)).saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 16),
        memo: '가볍게 시작',
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [
              WorkoutSetDraft(weight: 60, reps: 10),
              WorkoutSetDraft(weight: 65, reps: 8),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2026.05.16'), findsWidgets);
    expect(find.text('벤치프레스'), findsOneWidget);
    expect(find.text('가슴'), findsWidgets);
    expect(find.text('2세트'), findsOneWidget);
    expect(find.text('1120kg'), findsWidgets);
    expect(find.text('20kcal'), findsOneWidget);
    expect(find.text('70kg 기준'), findsOneWidget);
    expect(find.text('가볍게 시작'), findsOneWidget);
  });

  testWidgets('opens dedicated workout record list from home hero', (
    tester,
  ) async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');
    await WorkoutService(WorkoutRepository(database)).saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 16),
        memo: '전용 페이지 확인',
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('운동 기록 전체보기'), findsOneWidget);
    await tester.tap(find.byTooltip('운동 기록 전체보기'));
    await tester.pumpAndSettle();

    expect(find.text('운동 기록'), findsOneWidget);
    expect(find.text('전용 페이지 확인'), findsOneWidget);
    expect(find.text('벤치프레스'), findsOneWidget);
    expect(find.byTooltip('통계'), findsNothing);

    await tester.tap(find.byTooltip('뒤로가기'));
    await tester.pumpAndSettle();

    expect(find.text('Muscle Diary'), findsOneWidget);
  });

  testWidgets(
    'shows daily summary card with volume entries sets and calories',
    (tester) async {
      final exercises = await database.select(database.exercises).get();
      final benchPress = exercises.firstWhere(
        (exercise) => exercise.name == '벤치프레스',
      );
      final squat = exercises.firstWhere((exercise) => exercise.name == '스쿼트');

      await WorkoutService(WorkoutRepository(database)).saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 16),
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [
                WorkoutSetDraft(weight: 60, reps: 10),
                WorkoutSetDraft(weight: 65, reps: 8),
              ],
            ),
            WorkoutEntryDraft(
              exerciseId: squat.id,
              sets: const [WorkoutSetDraft(weight: 100, reps: 5)],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      final summaryFinder = find.byKey(
        const ValueKey('record-date-summary-20260516'),
      );
      expect(summaryFinder, findsOneWidget);
      expect(
        find.descendant(of: summaryFinder, matching: find.text('가슴 · 하체')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summaryFinder, matching: find.text('1620kg')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: summaryFinder, matching: find.text('2종목 · 3세트')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: summaryFinder,
          matching: find.text('예상 31kcal · 70kg 기준'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('daily summary sums calories with exercise type METs', (
    tester,
  ) async {
    final exercises = await database.select(database.exercises).get();
    final benchPress = exercises.firstWhere(
      (exercise) => exercise.name == '벤치프레스',
    );
    final pushUp = exercises.firstWhere((exercise) => exercise.name == '푸시업');

    await WorkoutService(WorkoutRepository(database)).saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 16),
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [
              WorkoutSetDraft(weight: 60, reps: 10),
              WorkoutSetDraft(weight: 65, reps: 8),
            ],
          ),
          WorkoutEntryDraft(
            exerciseId: pushUp.id,
            sets: const [WorkoutSetDraft(weight: 0, reps: 20)],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    final summaryFinder = find.byKey(
      const ValueKey('record-date-summary-20260516'),
    );
    expect(summaryFinder, findsOneWidget);
    expect(
      find.descendant(of: summaryFinder, matching: find.text('2종목 · 3세트')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: summaryFinder,
        matching: find.text('예상 32kcal · 70kg 기준'),
      ),
      findsOneWidget,
    );
    expect(find.text('푸시업'), findsOneWidget);
    expect(find.text('12kcal'), findsOneWidget);
    expect(find.text('70kg 기준'), findsWidgets);
  });

  testWidgets('weekly body part day tap scrolls to that date records', (
    tester,
  ) async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');
    final today = DateTime.now();
    final weekStart = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: today.weekday - DateTime.monday));

    for (var dayOffset = 0; dayOffset < 7; dayOffset += 1) {
      await WorkoutService(WorkoutRepository(database)).saveWorkout(
        WorkoutDraft(
          workoutDate: weekStart.add(Duration(days: dayOffset)),
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    final mondayKey = DateFormat('yyyyMMdd').format(weekStart);
    final mondayDayFinder = find.byKey(ValueKey('weekly-day-$mondayKey'));
    await tester.scrollUntilVisible(
      mondayDayFinder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(mondayDayFinder);
    await tester.pumpAndSettle();
    await tester.tap(mondayDayFinder);
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    final mondayHeaderFinder = find.byKey(
      ValueKey('record-date-header-label-$mondayKey'),
    );
    expect(find.text('운동 기록'), findsOneWidget);
    expect(mondayHeaderFinder, findsOneWidget);
    expect(tester.getTopLeft(mondayHeaderFinder).dy, lessThan(550));
  });

  testWidgets('monthly body part calendar opens and focuses record dates', (
    tester,
  ) async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');
    final now = DateTime.now();
    final recordDate = DateTime(now.year, now.month);
    final emptyDate = DateTime(now.year, now.month, 2);
    final recordDateKey = DateFormat('yyyyMMdd').format(recordDate);
    final emptyDateKey = DateFormat('yyyyMMdd').format(emptyDate);

    final workoutService = WorkoutService(WorkoutRepository(database));
    await workoutService.saveWorkout(
      WorkoutDraft(
        workoutDate: recordDate,
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
          ),
        ],
      ),
    );
    for (var day = 3; day <= 28; day += 1) {
      await workoutService.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(now.year, now.month, day),
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
            ),
          ],
        ),
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    final monthlyCalendarButtonFinder = find.byKey(
      const ValueKey('monthly-body-part-calendar-button'),
    );
    await tester.scrollUntilVisible(
      monthlyCalendarButtonFinder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(monthlyCalendarButtonFinder);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('monthly-body-part-calendar-grid')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('monthly-calendar-prev-month')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('monthly-calendar-next-month')),
      findsNothing,
    );
    expect(
      find.text(DateFormat('yyyy년 M월').format(recordDate)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(ValueKey('monthly-calendar-day-$recordDateKey')),
        matching: find.text('가슴'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(ValueKey('monthly-calendar-day-$emptyDateKey')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('monthly-body-part-calendar-grid')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(ValueKey('monthly-calendar-day-$recordDateKey')),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 500));

    expect(
      find.byKey(const ValueKey('monthly-body-part-calendar-grid')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('record-date-header-label-$recordDateKey')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('record-date-summary-$recordDateKey')),
      findsOneWidget,
    );
  });

  testWidgets(
    'monthly calendar compacts multiple body parts and shows details',
    (tester) async {
      final exercises = await database.select(database.exercises).get();
      final benchPress = exercises.firstWhere(
        (exercise) => exercise.name == '벤치프레스',
      );
      final latPulldown = exercises.firstWhere(
        (exercise) => exercise.name == '랫풀다운',
      );
      final squat = exercises.firstWhere((exercise) => exercise.name == '스쿼트');
      final now = DateTime.now();
      final recordDate = DateTime(now.year, now.month, 15);
      final recordDateKey = DateFormat('yyyyMMdd').format(recordDate);

      await WorkoutService(WorkoutRepository(database)).saveWorkout(
        WorkoutDraft(
          workoutDate: recordDate,
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
            ),
            WorkoutEntryDraft(
              exerciseId: latPulldown.id,
              sets: const [WorkoutSetDraft(weight: 40, reps: 10)],
            ),
            WorkoutEntryDraft(
              exerciseId: squat.id,
              sets: const [WorkoutSetDraft(weight: 100, reps: 5)],
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      final monthlyCalendarButtonFinder = find.byKey(
        const ValueKey('monthly-body-part-calendar-button'),
      );
      await tester.scrollUntilVisible(
        monthlyCalendarButtonFinder,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -180));
      await tester.pumpAndSettle();
      await tester.tap(monthlyCalendarButtonFinder);
      await tester.pumpAndSettle();

      final dayCellFinder = find.byKey(
        ValueKey('monthly-calendar-day-$recordDateKey'),
      );
      expect(
        find.descendant(of: dayCellFinder, matching: find.text('가슴 +2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dayCellFinder, matching: find.text('등')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await tester.longPress(dayCellFinder);
      await tester.pumpAndSettle();

      final dialogFinder = find.byType(AlertDialog);
      expect(dialogFinder, findsOneWidget);
      expect(
        find.descendant(
          of: dialogFinder,
          matching: find.text(
            '${DateFormat('M월 d일').format(recordDate)} 운동 부위',
          ),
        ),
        findsOneWidget,
      );
      for (final bodyPart in const ['가슴', '등', '하체']) {
        expect(
          find.descendant(of: dialogFinder, matching: find.text(bodyPart)),
          findsOneWidget,
        );
      }

      await tester.tap(find.widgetWithText(TextButton, '닫기'));
      await tester.pumpAndSettle();
      expect(dialogFinder, findsNothing);
      expect(
        find.byKey(const ValueKey('monthly-body-part-calendar-grid')),
        findsOneWidget,
      );
    },
  );

  testWidgets('favorite exercise card updates lower stats without navigation', (
    tester,
  ) async {
    final exercises = await database.select(database.exercises).get();
    final benchPress = exercises.firstWhere(
      (exercise) => exercise.name == '벤치프레스',
    );
    final squat = exercises.firstWhere((exercise) => exercise.name == '스쿼트');
    final statsService = StatsService(StatsRepository(database));
    await statsService.addFavoriteExercise(benchPress.id);
    await statsService.addFavoriteExercise(squat.id);
    await WorkoutService(WorkoutRepository(database)).saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime.now(),
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [
              WorkoutSetDraft(weight: 40, reps: 10, isWarmup: true),
              WorkoutSetDraft(weight: 80, reps: 5),
              WorkoutSetDraft(weight: 80, reps: 8),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('통계'));
    await tester.pumpAndSettle();

    expect(find.text('부위 필터'), findsNothing);
    expect(find.text('운동 필터'), findsNothing);
    expect(find.text('전체 운동 통계'), findsNothing);
    expect(find.text('관심 운동 상세 통계'), findsNothing);
    expect(find.text('운동 통계'), findsOneWidget);
    expect(find.text('벤치프레스 통계'), findsOneWidget);
    expect(find.text('주별 기준 가슴 · 벤치프레스 기록입니다.'), findsOneWidget);
    expect(find.text('주 최고 중량'), findsOneWidget);
    expect(find.text('80kg'), findsWidgets);
    expect(find.text('80kg × 8회'), findsNothing);
    expect(find.text('주 총 볼륨'), findsOneWidget);
    expect(find.text('1040kg'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('favorite-exercise-overall-card')),
      findsNothing,
    );
  });

  testWidgets('favorite exercise selection handles no records safely', (
    tester,
  ) async {
    final squat = (await database.select(database.exercises).get()).firstWhere(
      (exercise) => exercise.name == '스쿼트',
    );
    await StatsService(StatsRepository(database)).addFavoriteExercise(squat.id);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('통계'));
    await tester.pumpAndSettle();
    expect(find.text('관심 운동 상세 통계'), findsNothing);
    expect(find.text('스쿼트 통계'), findsOneWidget);
    expect(find.text('주별 기준 하체 · 스쿼트 기록입니다.'), findsOneWidget);
    expect(find.textContaining('아직 운동 기록이 없습니다'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile settings saves body weight for calorie estimates', (
    tester,
  ) async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');
    await WorkoutService(WorkoutRepository(database)).saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 16),
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [
              WorkoutSetDraft(weight: 60, reps: 10),
              WorkoutSetDraft(weight: 65, reps: 8),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('20kcal'), findsOneWidget);
    expect(find.text('70kg 기준'), findsOneWidget);

    await tester.tap(find.byTooltip('설정/프로필'));
    await tester.pumpAndSettle();

    expect(find.text('설정/프로필'), findsOneWidget);
    expect(find.text('체중(kg)'), findsOneWidget);
    expect(find.textContaining('키는 칼로리 예상 계산에 사용하지 않습니다.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, '체중(kg)'), '80');
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(find.text('프로필을 저장했습니다.'), findsOneWidget);
    expect(find.text('예상 23kcal'), findsOneWidget);
    expect(find.textContaining('70kg 기준'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets('opens saved workout from home and updates it immediately', (
    tester,
  ) async {
    final exercises = await database.select(database.exercises).get();
    final benchPress = exercises.firstWhere(
      (exercise) => exercise.name == '벤치프레스',
    );
    await WorkoutService(WorkoutRepository(database)).saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 16),
        memo: '수정 전 메모',
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [WorkoutSetDraft(weight: 60, reps: 10, isWarmup: true)],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('벤치프레스'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('벤치프레스'));
    await tester.pumpAndSettle();

    expect(find.text('운동 기록 수정'), findsOneWidget);
    expect(find.text('2026.05.16'), findsOneWidget);
    expect(find.text('날짜 · 수정 불가'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.text('가슴'), findsWidgets);
    expect(find.text('벤치프레스'), findsOneWidget);
    expect(find.text('운동 기록 수정'), findsOneWidget);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).first).value, isTrue);

    await pickSheetOption(tester, placeholder: '가슴', option: '하체');

    await pickSheetOption(tester, placeholder: '운동 선택', option: '스쿼트');

    await tester.enterText(find.widgetWithText(TextFormField, '무게(kg)'), '100');
    await tester.enterText(find.widgetWithText(TextFormField, '횟수'), '5');
    final memoField = find.byType(TextFormField).last;
    await tester.ensureVisible(memoField);
    await tester.pumpAndSettle();
    await tester.enterText(memoField, '수정 후 메모');

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '수정 저장'));
    await tester.pumpAndSettle();

    expect(find.text('운동 기록 수정'), findsNothing);
    expect(find.text('수정되었습니다'), findsOneWidget);
    expect(find.text('운동 기록을 수정했습니다.'), findsNothing);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('스쿼트'), findsOneWidget);
    expect(find.text('하체'), findsWidgets);
    expect(find.text('워밍업 1세트'), findsOneWidget);
    expect(find.text('500kg'), findsWidgets);
    expect(find.textContaining('kcal'), findsWidgets);
    final updatedRecord = (await WorkoutService(
      WorkoutRepository(database),
    ).getWorkoutRecords()).single.entries.single;
    expect(updatedRecord.sets.single.isWarmup, isTrue);
    expect(find.text('수정 후 메모'), findsOneWidget);
    expect(find.text('벤치프레스'), findsNothing);
    expect(find.text('수정 전 메모'), findsNothing);
  });

  testWidgets('deletes a saved workout after confirmation and refreshes home', (
    tester,
  ) async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');
    await WorkoutService(WorkoutRepository(database)).saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime(2026, 5, 16),
        memo: '삭제할 메모',
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('벤치프레스'), findsOneWidget);
    expect(find.text('삭제할 메모'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('기록 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('기록 삭제'));
    await tester.pumpAndSettle();

    expect(find.text('기록 삭제'), findsOneWidget);
    expect(find.text('벤치프레스 기록을 삭제할까요?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    expect(find.text('운동 기록을 삭제했습니다.'), findsOneWidget);
    expect(find.text('벤치프레스'), findsNothing);
    expect(find.text('삭제할 메모'), findsNothing);
    expect(find.textContaining('아직 운동 기록이 없어요'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1500));
  });

  testWidgets('opens stats screen and shows monthly exercise stats', (
    tester,
  ) async {
    final benchPress = (await database.select(database.exercises).get())
        .firstWhere((exercise) => exercise.name == '벤치프레스');
    await WorkoutService(WorkoutRepository(database)).saveWorkout(
      WorkoutDraft(
        workoutDate: DateTime.now(),
        entries: [
          WorkoutEntryDraft(
            exerciseId: benchPress.id,
            sets: const [
              WorkoutSetDraft(weight: 60, reps: 10),
              WorkoutSetDraft(weight: 70, reps: 5),
            ],
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('통계'));
    await tester.pumpAndSettle();

    expect(find.text('운동 통계'), findsOneWidget);
    expect(find.text('관심 운동'), findsOneWidget);
    expect(find.text('통계로 볼 운동을 추가해 보세요'), findsOneWidget);
    expect(find.text('부위 필터'), findsNothing);
    expect(find.text('운동 필터'), findsNothing);
    expect(find.text('전체 부위'), findsNothing);
    expect(find.text('전체 운동'), findsNothing);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);

    expect(find.text('주 최고 중량'), findsNothing);
    expect(find.text('주 평균 중량'), findsNothing);
    expect(find.text('주 총 볼륨'), findsNothing);
    expect(find.text('전주 대비 총 볼륨'), findsNothing);
    expect(find.text('주별 최고 중량'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, '관심운동 추가'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('관심 운동 추가'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '운동 또는 부위 검색'), '벤치');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '추가').first);
    await tester.pumpAndSettle();

    expect(find.text('최고 70kg × 5회'), findsOneWidget);
    expect(find.text('총 볼륨 950kg'), findsOneWidget);
    expect(find.text('운동일 1일'), findsOneWidget);

    expect(find.text('관심 운동 상세 통계'), findsNothing);
    expect(find.text('벤치프레스 통계'), findsOneWidget);
    expect(find.text('주별 기준 가슴 · 벤치프레스 기록입니다.'), findsOneWidget);
    expect(find.text('70kg'), findsWidgets);
    expect(find.text('950kg'), findsWidgets);

    expect(
      find.byKey(const ValueKey('favorite-exercise-overall-card')),
      findsNothing,
    );
    expect(find.text('전체 운동 통계'), findsNothing);
    expect(find.text('부위 필터'), findsNothing);
    expect(find.text('운동 필터'), findsNothing);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(find.text('주 최고 중량'), findsOneWidget);

    expect(find.text('일간'), findsOneWidget);
    expect(find.text('주간'), findsOneWidget);
    expect(find.text('월간'), findsOneWidget);

    await tester.tap(find.text('일간'));
    await tester.pumpAndSettle();

    expect(find.text('일 최고 중량'), findsOneWidget);
    expect(find.text('일 평균 중량'), findsOneWidget);
    expect(find.text('일 총 볼륨'), findsOneWidget);
    expect(find.text('전일 대비 총 볼륨'), findsOneWidget);
    expect(find.text('일별 최고 중량'), findsOneWidget);

    await tester.tap(find.text('주간'));
    await tester.pumpAndSettle();

    expect(find.text('주 최고 중량'), findsOneWidget);
    expect(find.text('전주 대비 총 볼륨'), findsOneWidget);
    expect(find.text('주별 최고 중량'), findsOneWidget);
  });

  testWidgets(
    'stats screen has no legacy filters and favorite add includes custom exercises',
    (tester) async {
      final exerciseService = ExerciseService(ExerciseRepository(database));
      await exerciseService.addCustomExercise(
        bodyPartId: (await exerciseService.getBodyParts())
            .firstWhere((bodyPart) => bodyPart.name == '가슴')
            .id,
        name: '덤벨 플라이',
        type: 'weight_machine',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('통계'));
      await tester.pumpAndSettle();

      expect(find.text('부위 필터'), findsNothing);
      expect(find.text('운동 필터'), findsNothing);
      expect(
        find.byKey(const ValueKey('stats-body-part-filter-null')),
        findsNothing,
      );
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, '관심운동 추가'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(
        find.widgetWithText(TextField, '운동 또는 부위 검색'),
        '덤벨',
      );
      await tester.pump();

      expect(find.text('덤벨 플라이'), findsOneWidget);
      expect(find.text('가슴'), findsOneWidget);
      expect(find.text('스쿼트'), findsNothing);
    },
  );

  testWidgets(
    'registers custom exercise from add workout screen and selects it',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('새 운동 등록'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('운동 부위 선택'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('등').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        ),
        '원암 덤벨로우',
      );
      await tester.tap(find.widgetWithText(FilledButton, '등록'));
      await tester.pumpAndSettle();

      expect(find.text('운동을 등록했습니다.'), findsOneWidget);
      expect(find.text('원암 덤벨로우'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1500));
    },
  );
}
