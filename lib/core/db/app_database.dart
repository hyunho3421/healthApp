import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/exercise_type.dart';
import 'seed/workout_seed_data.dart';
import 'tables/body_parts.dart';
import 'tables/exercises.dart';
import 'tables/favorite_exercises.dart';
import 'tables/user_profiles.dart';
import 'tables/workout_entries.dart';
import 'tables/workout_sessions.dart';
import 'tables/workout_sets.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    BodyParts,
    Exercises,
    WorkoutSessions,
    WorkoutEntries,
    WorkoutSets,
    UserProfiles,
    FavoriteExercises,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await seedInitialData();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(workoutSets, workoutSets.isWarmup);
      }
      if (from < 3) {
        await m.createTable(userProfiles);
      }
      if (from < 4) {
        await customStatement(
          "UPDATE exercises SET type = '$defaultExerciseTypeId' "
          "WHERE type != '$defaultExerciseTypeId'",
        );
      }
      if (from < 5) {
        await m.createTable(favoriteExercises);
      }
      if (from < 6) {
        await customStatement(
          "UPDATE body_parts SET name = '복근' "
          "WHERE name = '코어' "
          "AND NOT EXISTS (SELECT 1 FROM body_parts WHERE name = '복근')",
        );
      }
      if (from < 7) {
        await customStatement(
          'ALTER TABLE exercises ADD COLUMN arm_detail TEXT',
        );
      }
      if (from < 8) {
        await m.addColumn(workoutSets, workoutSets.weightUnit);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      if (!details.wasCreated) {
        await seedInitialData();
      }
    },
  );

  Future<void> seedInitialData() async {
    await transaction(() async {
      for (final seed in bodyPartSeeds) {
        final companion = BodyPartsCompanion.insert(
          name: seed.name,
          sortOrder: seed.sortOrder,
        );
        await into(bodyParts).insert(
          companion,
          onConflict: DoUpdate((_) => companion, target: [bodyParts.name]),
        );
      }

      final parts = await select(bodyParts).get();
      final partIdByName = {for (final part in parts) part.name: part.id};

      for (final seed in exerciseSeeds) {
        final bodyPartId = partIdByName[seed.bodyPartName];
        if (bodyPartId == null) {
          throw StateError('Missing body part seed: ${seed.bodyPartName}');
        }

        final companion = ExercisesCompanion.insert(
          bodyPartId: bodyPartId,
          name: seed.name,
          type: seed.type,
          armDetail: Value(seed.armDetail),
          isCustom: const Value(false),
        );
        await into(exercises).insert(
          companion,
          onConflict: DoUpdate(
            (_) => companion,
            target: [exercises.bodyPartId, exercises.name],
          ),
        );
      }
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'muscle_growth_diary.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
