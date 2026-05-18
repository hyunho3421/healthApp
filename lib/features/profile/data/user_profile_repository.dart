import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';

class UserProfileRepository {
  UserProfileRepository(this._database);

  final AppDatabase _database;

  Future<UserProfile?> getProfile() {
    return (_database.select(
      _database.userProfiles,
    )..limit(1)).getSingleOrNull();
  }

  Future<double?> getBodyWeightKg() async {
    final profile = await getProfile();
    return profile?.bodyWeightKg;
  }

  Future<void> saveBodyWeightKg(double bodyWeightKg) async {
    final existing = await getProfile();
    final now = DateTime.now();

    if (existing == null) {
      await _database
          .into(_database.userProfiles)
          .insert(
            UserProfilesCompanion.insert(
              bodyWeightKg: Value(bodyWeightKg),
              updatedAt: Value(now),
            ),
          );
      return;
    }

    await (_database.update(
      _database.userProfiles,
    )..where((profile) => profile.id.equals(existing.id))).write(
      UserProfilesCompanion(
        bodyWeightKg: Value(bodyWeightKg),
        updatedAt: Value(now),
      ),
    );
  }
}
