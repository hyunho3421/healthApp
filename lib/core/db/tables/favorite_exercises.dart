import 'package:drift/drift.dart';

import 'exercises.dart';

class FavoriteExercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get exerciseId => integer()
      .named('exercise_id')
      .references(Exercises, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder =>
      integer().named('sort_order').withDefault(const Constant(0))();
  DateTimeColumn get createdAt =>
      dateTime().named('created_at').withDefault(currentDateAndTime)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {exerciseId},
  ];
}
