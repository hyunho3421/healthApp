import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../database/providers/app_database_provider.dart';
import '../application/stats_service.dart';
import '../data/stats_repository.dart';

final statsRepositoryProvider = Provider<StatsRepository>((ref) {
  return StatsRepository(ref.watch(appDatabaseProvider));
});

final statsServiceProvider = Provider<StatsService>((ref) {
  return StatsService(ref.watch(statsRepositoryProvider));
});
