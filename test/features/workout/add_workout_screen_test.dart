import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:muscle_growth_diary/core/db/app_database.dart';
import 'package:muscle_growth_diary/features/database/providers/app_database_provider.dart';
import 'package:muscle_growth_diary/features/workout/application/workout_service.dart';
import 'package:muscle_growth_diary/features/workout/data/workout_repository.dart';
import 'package:muscle_growth_diary/features/workout/models/workout_draft.dart';
import 'package:muscle_growth_diary/features/workout/models/workout_record.dart';
import 'package:muscle_growth_diary/features/workout/presentation/add_workout_screen.dart';
import 'package:muscle_growth_diary/features/workout/providers/workout_providers.dart';

void main() {
  late AppDatabase database;
  late WorkoutService service;

  setUp(() async {
    database = AppDatabase.forTesting(NativeDatabase.memory());
    service = WorkoutService(WorkoutRepository(database));
    await database.seedInitialData();
  });

  tearDown(() async {
    await database.close();
  });

  testWidgets(
    'rest timer counts seconds and resets without workout persistence fields',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: const MaterialApp(home: AddWorkoutScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('쉬는시간'), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('0초'), findsNothing);
      expect(find.text('시작'), findsNothing);
      expect(find.text('초기화'), findsNothing);
      expect(tester.widget<Text>(find.text('0:00')).semanticsLabel, '쉬는시간 0초');

      final startButton = find.byTooltip('시작');
      final resetButton = find.byTooltip('초기화');
      expect(startButton, findsOneWidget);
      expect(resetButton, findsOneWidget);
      expect(tester.getSize(startButton), tester.getSize(resetButton));

      final restTimerOffset = tester.getTopLeft(find.text('쉬는시간')).dy;
      final setsOffset = tester.getTopLeft(find.text('세트')).dy;
      expect(restTimerOffset, lessThan(setsOffset));

      await tester.tap(startButton);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('측정 중'), findsOneWidget);
      expect(find.text('0:02'), findsOneWidget);
      expect(find.text('2초'), findsNothing);
      expect(find.text('일시정지'), findsNothing);
      expect(tester.widget<Text>(find.text('0:02')).semanticsLabel, '쉬는시간 2초');

      await tester.tap(find.byTooltip('일시정지'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('대기 중'), findsOneWidget);
      expect(find.text('0:02'), findsOneWidget);
      expect(find.text('2초'), findsNothing);
      expect(tester.widget<Text>(find.text('0:02')).semanticsLabel, '쉬는시간 2초');

      await tester.tap(resetButton);
      await tester.pump();

      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('0초'), findsNothing);
      expect(tester.widget<Text>(find.text('0:00')).semanticsLabel, '쉬는시간 0초');
    },
  );

  testWidgets(
    'set weight unit selector converts kg display to lbs and saves kg value',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final exercises = await database.select(database.exercises).get();
      final benchPress = exercises.firstWhere(
        (exercise) => exercise.name == '벤치프레스',
      );
      final sessionId = await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 20),
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 100, reps: 5)],
            ),
          ],
        ),
      );
      final record = await service.findWorkoutRecordForDateAndExercise(
        date: DateTime(2026, 5, 20),
        exerciseId: benchPress.id,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            home: AddWorkoutScreen.editing(
              editSessionId: sessionId,
              editingEntry: record!.entries.single,
              initialDate: record.session.workoutDate,
              initialMemo: record.session.memo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('무게 단위'), findsOneWidget);
      expect(find.text('무게(kg)'), findsOneWidget);
      expect(_fieldValues(tester), containsAllInOrder(['100', '5']));

      await tester.tap(find.text('lbs'));
      await tester.pumpAndSettle();

      expect(find.text('무게(lbs)'), findsOneWidget);
      expect(_fieldValues(tester), containsAllInOrder(['220.46', '5']));

      await tester.tap(find.text('수정 저장'));
      await tester.pumpAndSettle();

      final savedRecord = await service.findWorkoutRecordForDateAndExercise(
        date: DateTime(2026, 5, 20),
        exerciseId: benchPress.id,
      );
      expect(
        savedRecord!.entries.single.sets.single.weight,
        closeTo(100, 0.01),
      );

      await _settleToastTimers(tester);
    },
  );

  testWidgets(
    'add flow locks exercise selection after loading an existing same-day record',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final today = DateTime.now();
      final workoutDate = DateTime(today.year, today.month, today.day);
      final exercises = await database.select(database.exercises).get();
      final benchPress = exercises.firstWhere(
        (exercise) => exercise.name == '벤치프레스',
      );

      final sessionId = await service.saveWorkout(
        WorkoutDraft(
          workoutDate: workoutDate,
          memo: '기존 기록 메모',
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
            ),
          ],
        ),
      );
      final existingRecord = await service.findWorkoutRecordForDateAndExercise(
        date: workoutDate,
        exerciseId: benchPress.id,
      );
      final entryId = existingRecord!.entries.single.entry.id;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: const MaterialApp(home: AddWorkoutScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await _selectPickerOption(tester, '운동 부위 선택', '가슴');
      await _selectPickerOption(tester, '운동 선택', '벤치프레스');

      expect(
        _fieldValues(tester),
        containsAllInOrder(['60', '10', '기존 기록 메모']),
      );

      await tester.tap(find.text('벤치프레스').first);
      await tester.pumpAndSettle();

      expect(find.text('인클라인 벤치프레스'), findsNothing);

      await tester.tap(find.text('수정 저장'));
      await tester.pumpAndSettle();

      final records = await service.getWorkoutRecords(
        from: workoutDate,
        to: workoutDate.add(const Duration(days: 1)),
      );
      expect(records, hasLength(1));
      expect(records.single.session.id, sessionId);
      expect(records.single.entries, hasLength(1));
      expect(records.single.entries.single.entry.id, entryId);
      expect(records.single.entries.single.exercise.id, benchPress.id);

      await _settleToastTimers(tester);
    },
  );

  testWidgets(
    'editing screen reloads same-day exercise records and clears fields when missing',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final exercises = await database.select(database.exercises).get();
      final benchPress = exercises.firstWhere(
        (exercise) => exercise.name == '벤치프레스',
      );
      final inclineBenchPress = exercises.firstWhere(
        (exercise) => exercise.name == '인클라인 벤치프레스',
      );
      final cableCrossover = exercises.firstWhere(
        (exercise) => exercise.name == '케이블크로스오버',
      );

      final benchSessionId = await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 16, 9),
          memo: '벤치 메모',
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
            ),
          ],
        ),
      );
      await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 16, 18),
          memo: '인클라인 메모',
          entries: [
            WorkoutEntryDraft(
              exerciseId: inclineBenchPress.id,
              sets: const [
                WorkoutSetDraft(weight: 80, reps: 8, isWarmup: true),
              ],
            ),
          ],
        ),
      );
      await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 16, 20),
          memo: '케이블 메모',
          entries: [
            WorkoutEntryDraft(
              exerciseId: cableCrossover.id,
              sets: const [WorkoutSetDraft(weight: 45, reps: 12)],
            ),
          ],
        ),
      );
      final benchRecord = await service.findWorkoutRecordForDateAndExercise(
        date: DateTime(2026, 5, 16),
        exerciseId: benchPress.id,
      );
      final editingEntry = benchRecord!.entries.single;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: MaterialApp(
            home: AddWorkoutScreen.editing(
              editSessionId: benchSessionId,
              editingEntry: editingEntry,
              initialDate: benchRecord.session.workoutDate,
              initialMemo: benchRecord.session.memo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(_fieldValues(tester), containsAllInOrder(['60', '10', '벤치 메모']));

      await _selectExercise(tester, '벤치프레스', '인클라인 벤치프레스');

      expect(_fieldValues(tester), containsAllInOrder(['80', '8', '인클라인 메모']));
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

      await _selectExercise(tester, '인클라인 벤치프레스', '체스트프레스');

      expect(_fieldValues(tester), containsAllInOrder(['', '', '']));
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

      await _selectExercise(tester, '체스트프레스', '케이블크로스오버');

      expect(_fieldValues(tester), containsAllInOrder(['45', '12', '케이블 메모']));
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

      await _settleToastTimers(tester);
    },
  );

  testWidgets(
    'editing screen ignores late same-day lookup results after another exercise is selected',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final exercises = await database.select(database.exercises).get();
      final benchPress = exercises.firstWhere(
        (exercise) => exercise.name == '벤치프레스',
      );
      final inclineBenchPress = exercises.firstWhere(
        (exercise) => exercise.name == '인클라인 벤치프레스',
      );

      final benchSessionId = await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 16, 9),
          memo: '벤치 메모',
          entries: [
            WorkoutEntryDraft(
              exerciseId: benchPress.id,
              sets: const [WorkoutSetDraft(weight: 60, reps: 10)],
            ),
          ],
        ),
      );
      await service.saveWorkout(
        WorkoutDraft(
          workoutDate: DateTime(2026, 5, 16, 18),
          memo: '늦은 인클라인 메모',
          entries: [
            WorkoutEntryDraft(
              exerciseId: inclineBenchPress.id,
              sets: const [
                WorkoutSetDraft(weight: 80, reps: 8, isWarmup: true),
              ],
            ),
          ],
        ),
      );
      final benchRecord = await service.findWorkoutRecordForDateAndExercise(
        date: DateTime(2026, 5, 16),
        exerciseId: benchPress.id,
      );
      final delayedService = _DelayedWorkoutService(
        WorkoutRepository(database),
        delayedExerciseId: inclineBenchPress.id,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            workoutServiceProvider.overrideWithValue(delayedService),
          ],
          child: MaterialApp(
            home: AddWorkoutScreen.editing(
              editSessionId: benchSessionId,
              editingEntry: benchRecord!.entries.single,
              initialDate: benchRecord.session.workoutDate,
              initialMemo: benchRecord.session.memo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _selectExerciseWithoutSettlingLookup(tester, '벤치프레스', '인클라인 벤치프레스');
      await _selectExercise(tester, '인클라인 벤치프레스', '체스트프레스');

      expect(_fieldValues(tester), containsAllInOrder(['', '', '']));
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

      delayedService.completeDelayedLookup();
      await tester.pumpAndSettle();

      expect(_fieldValues(tester), containsAllInOrder(['', '', '']));
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

      await _settleToastTimers(tester);
    },
  );
}

Future<void> _selectPickerOption(
  WidgetTester tester,
  String currentText,
  String nextText,
) async {
  await tester.tap(find.text(currentText).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(nextText).last);
  await tester.pumpAndSettle();
}

Future<void> _selectExercise(
  WidgetTester tester,
  String currentExercise,
  String nextExercise,
) async {
  await tester.tap(find.text(currentExercise).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(nextExercise).last);
  await tester.pumpAndSettle();
}

Future<void> _selectExerciseWithoutSettlingLookup(
  WidgetTester tester,
  String currentExercise,
  String nextExercise,
) async {
  await tester.tap(find.text(currentExercise).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(nextExercise).last);
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _settleToastTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

List<String> _fieldValues(WidgetTester tester) {
  return tester
      .widgetList<TextFormField>(find.byType(TextFormField))
      .map((field) => field.controller?.text ?? '')
      .toList();
}

class _DelayedWorkoutService extends WorkoutService {
  _DelayedWorkoutService(super.repository, {required this.delayedExerciseId});

  final int delayedExerciseId;
  final _delayedLookupCompleter = Completer<void>();

  void completeDelayedLookup() {
    if (!_delayedLookupCompleter.isCompleted) {
      _delayedLookupCompleter.complete();
    }
  }

  @override
  Future<WorkoutRecord?> findWorkoutRecordForDateAndExercise({
    required DateTime date,
    required int exerciseId,
  }) async {
    if (exerciseId == delayedExerciseId) {
      await _delayedLookupCompleter.future;
    }
    return super.findWorkoutRecordForDateAndExercise(
      date: date,
      exerciseId: exerciseId,
    );
  }
}
