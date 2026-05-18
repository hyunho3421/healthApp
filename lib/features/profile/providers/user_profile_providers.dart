import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../database/providers/app_database_provider.dart';
import '../application/user_profile_service.dart';
import '../data/user_profile_repository.dart';

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return UserProfileRepository(ref.watch(appDatabaseProvider));
});

final userProfileServiceProvider = Provider<UserProfileService>((ref) {
  return UserProfileService(ref.watch(userProfileRepositoryProvider));
});

final userProfileChangeVersionProvider = StateProvider<int>((ref) => 0);

void notifyUserProfileChanged(WidgetRef ref) {
  ref.read(userProfileChangeVersionProvider.notifier).state++;
}
