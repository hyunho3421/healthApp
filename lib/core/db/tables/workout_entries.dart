import 'package:drift/drift.dart';

import 'exercises.dart';
import 'workout_sessions.dart';

class WorkoutEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer()
      .named('session_id')
      .references(WorkoutSessions, #id, onDelete: KeyAction.cascade)();
  IntColumn get exerciseId =>
      integer().named('exercise_id').references(Exercises, #id)();
  IntColumn get orderIndex =>
      integer().named('order_index').withDefault(const Constant(0))();
  TextColumn get memo => text().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().named('created_at').withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().named('updated_at').withDefault(currentDateAndTime)();
}
