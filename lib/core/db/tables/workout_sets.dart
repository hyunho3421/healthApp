import 'package:drift/drift.dart';

import 'workout_entries.dart';

class WorkoutSets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get entryId => integer()
      .named('entry_id')
      .references(WorkoutEntries, #id, onDelete: KeyAction.cascade)();
  IntColumn get setNumber => integer().named('set_number')();
  RealColumn get weight => real()();
  IntColumn get reps => integer()();
  BoolColumn get isWarmup =>
      boolean().named('is_warmup').withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().named('created_at').withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().named('updated_at').withDefault(currentDateAndTime)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {entryId, setNumber},
  ];
}
