import 'package:drift/drift.dart';

import 'body_parts.dart';

class Exercises extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bodyPartId =>
      integer().named('body_part_id').references(BodyParts, #id)();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get type => text().withLength(min: 1, max: 30)();
  TextColumn get armDetail => text().named('arm_detail').nullable()();
  BoolColumn get isCustom =>
      boolean().named('is_custom').withDefault(const Constant(false))();
  DateTimeColumn get createdAt =>
      dateTime().named('created_at').withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt =>
      dateTime().named('updated_at').withDefault(currentDateAndTime)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {bodyPartId, name},
  ];
}
