import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/models/exercise_type.dart';
import '../../../core/widgets/centered_toast.dart';
import '../../profile/providers/user_profile_providers.dart';
import '../../profile/presentation/profile_settings_screen.dart';
import '../../stats/presentation/stats_screen.dart';
import '../../workout/models/workout_record.dart';
import '../../workout/presentation/add_workout_screen.dart';
import '../../workout/providers/workout_providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const int _recordsPageSize = 20;

  final ScrollController _recordsScrollController = ScrollController();
  final List<WorkoutRecord> _records = [];
  late Future<_HomeSummary> _homeSummaryFuture;
  late Future<double?> _bodyWeightKgFuture;
  DateTime? _focusedWorkoutDate;
  int _focusRequestId = 0;
  bool _isInitialRecordsLoading = true;
  bool _isLoadingMoreRecords = false;
  bool _hasMoreRecords = true;
  Object? _recordsLoadError;

  @override
  void initState() {
    super.initState();
    _recordsScrollController.addListener(_onRecordsScroll);
    _homeSummaryFuture = _loadHomeSummary();
    _bodyWeightKgFuture = ref
        .read(userProfileServiceProvider)
        .getBodyWeightKg();
    _loadInitialRecords();
  }

  @override
  void dispose() {
    _recordsScrollController
      ..removeListener(_onRecordsScroll)
      ..dispose();
    super.dispose();
  }

  Future<List<WorkoutRecord>> _loadRecordsPage({
    DateTime? beforeDate,
    int? beforeSessionId,
  }) {
    return ref
        .read(workoutServiceProvider)
        .getWorkoutRecords(
          limit: _recordsPageSize + 1,
          beforeDate: beforeDate,
          beforeSessionId: beforeSessionId,
        );
  }

  Future<_HomeSummary> _loadHomeSummary() async {
    final today = DateTime.now();
    final weekStart = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: today.weekday - DateTime.monday));
    final weekEnd = weekStart.add(const Duration(days: 7));
    final monthStart = DateTime(today.year, today.month);
    final monthEnd = DateTime(today.year, today.month + 1);
    final service = ref.read(workoutServiceProvider);

    final results = await Future.wait<Object>([
      service.getWorkoutRecords(from: weekStart, to: weekEnd),
      service.getWorkoutRecords(from: monthStart, to: monthEnd),
      service.getWorkoutSetCount(),
    ]);

    return _HomeSummary(
      weeklyRecords: results[0] as List<WorkoutRecord>,
      monthlyRecords: results[1] as List<WorkoutRecord>,
      totalSetCount: results[2] as int,
    );
  }

  Future<void> _loadInitialRecords() async {
    setState(() {
      _homeSummaryFuture = _loadHomeSummary();
      _isInitialRecordsLoading = true;
      _isLoadingMoreRecords = false;
      _hasMoreRecords = true;
      _recordsLoadError = null;
      _records.clear();
    });

    try {
      final page = await _loadRecordsPage();
      if (!mounted) {
        return;
      }
      setState(() {
        _records
          ..clear()
          ..addAll(page.take(_recordsPageSize));
        _hasMoreRecords = page.length > _recordsPageSize;
        _isInitialRecordsLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _recordsLoadError = error;
        _isInitialRecordsLoading = false;
      });
    }
  }

  void _refreshRecords() {
    if (!mounted) {
      return;
    }
    _loadInitialRecords();
  }

  Future<void> _loadMoreRecords() async {
    if (_isInitialRecordsLoading ||
        _isLoadingMoreRecords ||
        !_hasMoreRecords ||
        _records.isEmpty) {
      return;
    }

    final lastRecord = _records.last;
    setState(() {
      _isLoadingMoreRecords = true;
      _recordsLoadError = null;
    });

    try {
      final page = await _loadRecordsPage(
        beforeDate: lastRecord.session.workoutDate,
        beforeSessionId: lastRecord.session.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _records.addAll(page.take(_recordsPageSize));
        _hasMoreRecords = page.length > _recordsPageSize;
        _isLoadingMoreRecords = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _recordsLoadError = error;
        _isLoadingMoreRecords = false;
      });
    }
  }

  void _onRecordsScroll() {
    if (!_recordsScrollController.hasClients) {
      return;
    }
    final position = _recordsScrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      _loadMoreRecords();
    }
  }

  Future<void> _openAddWorkout() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddWorkoutScreen()));
    if (!mounted || saved != true) {
      return;
    }
    _refreshRecords();
    CenteredToast.show(context, '운동 기록을 저장했습니다.');
  }

  void _focusWorkoutDate(DateTime date) {
    _focusWorkoutDateAfterLoading(date);
  }

  Future<void> _focusWorkoutDateAfterLoading(DateTime date) async {
    final targetDate = DateTime(date.year, date.month, date.day);
    while (_hasMoreRecords &&
        !_records.any(
          (record) => _isSameDay(record.session.workoutDate, targetDate),
        )) {
      final lastRecord = _records.isEmpty ? null : _records.last;
      if (lastRecord != null &&
          lastRecord.session.workoutDate.isBefore(targetDate)) {
        break;
      }
      await _loadMoreRecords();
      if (_recordsLoadError != null) {
        break;
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _focusedWorkoutDate = targetDate;
      _focusRequestId += 1;
    });
  }

  Future<void> _openEditWorkout(_RecordEntryItem item) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddWorkoutScreen.editing(
          editSessionId: item.sessionId,
          editingEntry: item.entry,
          initialDate: item.date,
          initialMemo: item.sessionMemo,
        ),
      ),
    );
    if (!mounted || saved != true) {
      return;
    }
    _refreshRecords();
    CenteredToast.show(context, '수정되었습니다');
  }

  Future<void> _confirmDeleteWorkout(_RecordEntryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('기록 삭제'),
        content: Text('${item.entry.exercise.name} 기록을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    try {
      await ref
          .read(workoutServiceProvider)
          .deleteWorkoutEntry(
            sessionId: item.sessionId,
            entryId: item.entry.entry.id,
          );
      if (!mounted) {
        return;
      }
      _refreshRecords();
      CenteredToast.show(context, '운동 기록을 삭제했습니다.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      CenteredToast.show(context, '삭제에 실패했습니다: $error');
    }
  }

  void _openStats() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const StatsScreen()));
  }

  Future<void> _openWorkoutRecords() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const _WorkoutRecordListScreen()),
    );
    if (!mounted || changed != true) {
      return;
    }
    _refreshRecords();
  }

  Future<void> _openProfileSettings() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
    );
    if (!mounted || saved != true) {
      return;
    }
    setState(() {
      _bodyWeightKgFuture = ref
          .read(userProfileServiceProvider)
          .getBodyWeightKg();
    });
    CenteredToast.show(context, '프로필을 저장했습니다.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: _isInitialRecordsLoading
            ? const Center(child: CircularProgressIndicator())
            : _recordsLoadError != null && _records.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('기록을 불러오지 못했습니다: $_recordsLoadError'),
                ),
              )
            : Column(
                children: [
                  FutureBuilder<_HomeSummary>(
                    future: _homeSummaryFuture,
                    builder: (context, summarySnapshot) {
                      final summary = summarySnapshot.data;
                      final weeklyRecords =
                          summary?.weeklyRecords ?? const <WorkoutRecord>[];
                      final monthlyRecords =
                          summary?.monthlyRecords ?? const <WorkoutRecord>[];
                      return Column(
                        children: [
                          _HomeHero(
                            records: weeklyRecords,
                            totalSetCount: summary?.totalSetCount ?? 0,
                            onRecordsTap: _openWorkoutRecords,
                            onProfileTap: _openProfileSettings,
                            onStatsTap: _openStats,
                          ),
                          _WeeklyBodyPartSummary(
                            records: weeklyRecords,
                            monthlyRecords: monthlyRecords,
                            onDateTap: _focusWorkoutDate,
                          ),
                        ],
                      );
                    },
                  ),
                  Expanded(
                    child: _records.isEmpty
                        ? const _EmptyRecordsState()
                        : FutureBuilder<double?>(
                            future: _bodyWeightKgFuture,
                            builder: (context, weightSnapshot) =>
                                _WorkoutRecordList(
                                  records: _records,
                                  scrollController: _recordsScrollController,
                                  isLoadingMore: _isLoadingMoreRecords,
                                  hasMoreRecords: _hasMoreRecords,
                                  loadMoreError: _recordsLoadError,
                                  onLoadMoreRetry: _loadMoreRecords,
                                  bodyWeightKg: weightSnapshot.data ?? 70,
                                  usesDefaultBodyWeight:
                                      weightSnapshot.data == null,
                                  focusedDate: _focusedWorkoutDate,
                                  focusRequestId: _focusRequestId,
                                  onRecordTap: _openEditWorkout,
                                  onRecordDelete: _confirmDeleteWorkout,
                                ),
                          ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddWorkout,
        icon: const Icon(Icons.add),
        label: const Text('기록 추가'),
      ),
    );
  }
}

class _WorkoutRecordListScreen extends ConsumerStatefulWidget {
  const _WorkoutRecordListScreen();

  @override
  ConsumerState<_WorkoutRecordListScreen> createState() =>
      _WorkoutRecordListScreenState();
}

class _WorkoutRecordListScreenState
    extends ConsumerState<_WorkoutRecordListScreen> {
  static const int _recordsPageSize = 20;

  final ScrollController _recordsScrollController = ScrollController();
  final List<WorkoutRecord> _records = [];
  late Future<double?> _bodyWeightKgFuture;
  bool _isInitialRecordsLoading = true;
  bool _isLoadingMoreRecords = false;
  bool _hasMoreRecords = true;
  Object? _recordsLoadError;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _recordsScrollController.addListener(_onRecordsScroll);
    _bodyWeightKgFuture = ref
        .read(userProfileServiceProvider)
        .getBodyWeightKg();
    _loadInitialRecords();
  }

  @override
  void dispose() {
    _recordsScrollController
      ..removeListener(_onRecordsScroll)
      ..dispose();
    super.dispose();
  }

  Future<List<WorkoutRecord>> _loadRecordsPage({
    DateTime? beforeDate,
    int? beforeSessionId,
  }) {
    return ref
        .read(workoutServiceProvider)
        .getWorkoutRecords(
          limit: _recordsPageSize + 1,
          beforeDate: beforeDate,
          beforeSessionId: beforeSessionId,
        );
  }

  Future<void> _loadInitialRecords() async {
    setState(() {
      _isInitialRecordsLoading = true;
      _isLoadingMoreRecords = false;
      _hasMoreRecords = true;
      _recordsLoadError = null;
      _records.clear();
    });

    try {
      final page = await _loadRecordsPage();
      if (!mounted) {
        return;
      }
      setState(() {
        _records
          ..clear()
          ..addAll(page.take(_recordsPageSize));
        _hasMoreRecords = page.length > _recordsPageSize;
        _isInitialRecordsLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _recordsLoadError = error;
        _isInitialRecordsLoading = false;
      });
    }
  }

  Future<void> _loadMoreRecords() async {
    if (_isInitialRecordsLoading ||
        _isLoadingMoreRecords ||
        !_hasMoreRecords ||
        _records.isEmpty) {
      return;
    }

    final lastRecord = _records.last;
    setState(() {
      _isLoadingMoreRecords = true;
      _recordsLoadError = null;
    });

    try {
      final page = await _loadRecordsPage(
        beforeDate: lastRecord.session.workoutDate,
        beforeSessionId: lastRecord.session.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _records.addAll(page.take(_recordsPageSize));
        _hasMoreRecords = page.length > _recordsPageSize;
        _isLoadingMoreRecords = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _recordsLoadError = error;
        _isLoadingMoreRecords = false;
      });
    }
  }

  void _onRecordsScroll() {
    if (!_recordsScrollController.hasClients) {
      return;
    }
    final position = _recordsScrollController.position;
    if (position.pixels >= position.maxScrollExtent - 320) {
      _loadMoreRecords();
    }
  }

  Future<void> _openAddWorkout() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddWorkoutScreen()));
    if (!mounted || saved != true) {
      return;
    }
    _changed = true;
    _loadInitialRecords();
    CenteredToast.show(context, '운동 기록을 저장했습니다.');
  }

  Future<void> _openEditWorkout(_RecordEntryItem item) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AddWorkoutScreen.editing(
          editSessionId: item.sessionId,
          editingEntry: item.entry,
          initialDate: item.date,
          initialMemo: item.sessionMemo,
        ),
      ),
    );
    if (!mounted || saved != true) {
      return;
    }
    _changed = true;
    _loadInitialRecords();
    CenteredToast.show(context, '수정되었습니다');
  }

  Future<void> _confirmDeleteWorkout(_RecordEntryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('기록 삭제'),
        content: Text('${item.entry.exercise.name} 기록을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }

    try {
      await ref
          .read(workoutServiceProvider)
          .deleteWorkoutEntry(
            sessionId: item.sessionId,
            entryId: item.entry.entry.id,
          );
      if (!mounted) {
        return;
      }
      _changed = true;
      _loadInitialRecords();
      CenteredToast.show(context, '운동 기록을 삭제했습니다.');
    } catch (error) {
      if (!mounted) {
        return;
      }
      CenteredToast.show(context, '삭제에 실패했습니다: $error');
    }
  }

  void _close() {
    Navigator.of(context).pop(_changed);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _close();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('운동 기록'),
          leading: IconButton(
            onPressed: _close,
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: '뒤로가기',
          ),
        ),
        body: SafeArea(
          child: _isInitialRecordsLoading
              ? const Center(child: CircularProgressIndicator())
              : _recordsLoadError != null && _records.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('기록을 불러오지 못했습니다: $_recordsLoadError'),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _loadInitialRecords,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('다시 불러오기'),
                        ),
                      ],
                    ),
                  ),
                )
              : _records.isEmpty
              ? const _EmptyRecordsState()
              : FutureBuilder<double?>(
                  future: _bodyWeightKgFuture,
                  builder: (context, weightSnapshot) => _WorkoutRecordList(
                    records: _records,
                    scrollController: _recordsScrollController,
                    isLoadingMore: _isLoadingMoreRecords,
                    hasMoreRecords: _hasMoreRecords,
                    loadMoreError: _recordsLoadError,
                    onLoadMoreRetry: _loadMoreRecords,
                    bodyWeightKg: weightSnapshot.data ?? 70,
                    usesDefaultBodyWeight: weightSnapshot.data == null,
                    focusedDate: null,
                    focusRequestId: 0,
                    onRecordTap: _openEditWorkout,
                    onRecordDelete: _confirmDeleteWorkout,
                  ),
                ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _openAddWorkout,
          icon: const Icon(Icons.add),
          label: const Text('기록 추가'),
        ),
      ),
    );
  }
}

class _HomeSummary {
  const _HomeSummary({
    required this.weeklyRecords,
    required this.monthlyRecords,
    required this.totalSetCount,
  });

  final List<WorkoutRecord> weeklyRecords;
  final List<WorkoutRecord> monthlyRecords;
  final int totalSetCount;
}

class _HomeHero extends StatelessWidget {
  const _HomeHero({
    required this.records,
    required this.totalSetCount,
    required this.onRecordsTap,
    required this.onProfileTap,
    required this.onStatsTap,
  });

  final List<WorkoutRecord> records;
  final int totalSetCount;
  final VoidCallback onRecordsTap;
  final VoidCallback onProfileTap;
  final VoidCallback onStatsTap;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final weekStart = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: today.weekday - DateTime.monday));
    final weekEnd = weekStart.add(const Duration(days: 7));
    var weeklySessionCount = 0;
    var weeklyVolume = 0.0;

    for (final record in records) {
      final workoutDate = DateTime(
        record.session.workoutDate.year,
        record.session.workoutDate.month,
        record.session.workoutDate.day,
      );
      if (!workoutDate.isBefore(weekStart) && workoutDate.isBefore(weekEnd)) {
        weeklySessionCount += 1;
      }
      for (final entry in record.entries) {
        if (!workoutDate.isBefore(weekStart) && workoutDate.isBefore(weekEnd)) {
          weeklyVolume += entry.sets.fold<double>(
            0,
            (sum, set) => sum + set.weight * set.reps,
          );
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF111827), Color(0xFF1D4ED8)],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1D4ED8).withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.16),
                        ),
                      ),
                      child: const Text(
                        'Muscle Diary',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _HeroIconButton(
                  icon: Icons.event_note_rounded,
                  tooltip: '운동 기록 전체보기',
                  onTap: onRecordsTap,
                ),
                const SizedBox(width: 8),
                _HeroIconButton(
                  icon: Icons.bar_chart_rounded,
                  tooltip: '통계',
                  onTap: onStatsTap,
                ),
                const SizedBox(width: 8),
                _HeroIconButton(
                  icon: Icons.person_outline_rounded,
                  tooltip: '설정/프로필',
                  onTap: onProfileTap,
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              records.isEmpty ? '첫 성장을 기록해볼까요?' : '오늘도 성장 기록하기',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              records.isEmpty
                  ? '운동, 세트, 볼륨을 깔끔하게 쌓아가면 변화가 보입니다.'
                  : '이번 주 흐름을 확인하고 다음 운동을 이어가세요.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.74),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _HeroMetric(
                    label: '이번 주',
                    value: '$weeklySessionCount회',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeroMetric(
                    label: '주간 볼륨',
                    value: '${_formatVolume(weeklyVolume)}kg',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeroMetric(label: '총 세트', value: '$totalSetCount'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  const _HeroIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.12),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onTap,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        padding: EdgeInsets.zero,
        iconSize: 20,
        icon: Icon(icon, color: Colors.white),
        tooltip: tooltip,
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRecordsState extends StatelessWidget {
  const _EmptyRecordsState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE8EEF6)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.fitness_center_rounded,
                  color: colorScheme.primary,
                  size: 30,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '아직 운동 기록이 없어요',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '오른쪽 아래 기록 추가 버튼으로\n첫 운동을 남겨 보세요.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeeklyBodyPartSummary extends StatelessWidget {
  const _WeeklyBodyPartSummary({
    required this.records,
    required this.monthlyRecords,
    required this.onDateTap,
  });

  final List<WorkoutRecord> records;
  final List<WorkoutRecord> monthlyRecords;
  final ValueChanged<DateTime> onDateTap;

  Future<void> _showMonthlyBodyPartCalendar(BuildContext context) async {
    final selectedDate = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _MonthlyBodyPartCalendarSheet(records: monthlyRecords),
    );
    if (selectedDate != null) {
      onDateTap(selectedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final weekStart = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(Duration(days: today.weekday - DateTime.monday));
    final bodyPartsByDay = _bodyPartsByDay(records, weekStart);
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE8EEF6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '이번 주 운동 부위',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '운동한 날을 눌러 기록으로 이동하세요',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  key: const ValueKey('monthly-body-part-calendar-button'),
                  onPressed: () => _showMonthlyBodyPartCalendar(context),
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: const Text('월간'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: 7,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final date = weekStart.add(Duration(days: index));
                  final parts = bodyPartsByDay[_dateKey(date)] ?? const [];
                  final isToday = _isSameDay(date, today);
                  return _WeeklyBodyPartDayCard(
                    date: date,
                    bodyParts: parts,
                    isToday: isToday,
                    onTap: parts.isEmpty ? null : () => onDateTap(date),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyBodyPartDayCard extends StatelessWidget {
  const _WeeklyBodyPartDayCard({
    required this.date,
    required this.bodyParts,
    required this.isToday,
    required this.onTap,
  });

  final DateTime date;
  final List<String> bodyParts;
  final bool isToday;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasWorkout = bodyParts.isNotEmpty;
    final bodyText = bodyParts.isEmpty ? '휴식' : bodyParts.join('\n');
    final background = isToday
        ? colorScheme.primary
        : hasWorkout
        ? const Color(0xFFF1F7FF)
        : const Color(0xFFF8FAFC);
    final foreground = isToday ? Colors.white : colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('weekly-day-${_dateKey(date)}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          width: 82,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: background,
            border: Border.all(
              color: isToday
                  ? colorScheme.primary
                  : hasWorkout
                  ? const Color(0xFFCFE4FF)
                  : const Color(0xFFE8EEF6),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _weekdayLabel(date.weekday),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                DateFormat('M.d').format(date),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isToday
                      ? Colors.white.withValues(alpha: 0.72)
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                bodyText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isToday
                      ? Colors.white
                      : bodyParts.isEmpty
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.primary,
                  fontWeight: hasWorkout ? FontWeight.w800 : FontWeight.w500,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthlyBodyPartCalendarSheet extends StatefulWidget {
  const _MonthlyBodyPartCalendarSheet({required this.records});

  final List<WorkoutRecord> records;

  @override
  State<_MonthlyBodyPartCalendarSheet> createState() =>
      _MonthlyBodyPartCalendarSheetState();
}

class _MonthlyBodyPartCalendarSheetState
    extends State<_MonthlyBodyPartCalendarSheet> {
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  void _moveMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bodyPartsByDate = _bodyPartsByDate(widget.records);
    final firstDay = DateTime(_visibleMonth.year, _visibleMonth.month);
    final firstGridDay = firstDay.subtract(
      Duration(days: firstDay.weekday - DateTime.monday),
    );
    final today = DateTime.now();

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.9,
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('monthly-calendar-prev-month'),
                    onPressed: () => _moveMonth(-1),
                    icon: const Icon(Icons.chevron_left),
                    tooltip: '이전 달',
                  ),
                  Expanded(
                    child: Text(
                      DateFormat('yyyy년 M월').format(_visibleMonth),
                      key: const ValueKey('monthly-calendar-title'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('monthly-calendar-next-month'),
                    onPressed: () => _moveMonth(1),
                    icon: const Icon(Icons.chevron_right),
                    tooltip: '다음 달',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (final weekday in const [
                    '월',
                    '화',
                    '수',
                    '목',
                    '금',
                    '토',
                    '일',
                  ])
                    Expanded(
                      child: Text(
                        weekday,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: GridView.builder(
                  key: const ValueKey('monthly-body-part-calendar-grid'),
                  padding: EdgeInsets.zero,
                  itemCount: 42,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 6,
                    childAspectRatio: 0.82,
                  ),
                  itemBuilder: (context, index) {
                    final date = firstGridDay.add(Duration(days: index));
                    final dateKey = _dateKey(date);
                    final bodyParts =
                        bodyPartsByDate[dateKey] ?? const <String>[];
                    final isCurrentMonth = date.month == _visibleMonth.month;
                    final isToday = _isSameDay(date, today);
                    return _MonthlyBodyPartCalendarDayCell(
                      date: date,
                      bodyParts: bodyParts,
                      isCurrentMonth: isCurrentMonth,
                      isToday: isToday,
                      onTap: bodyParts.isEmpty
                          ? null
                          : () => Navigator.of(context).pop(date),
                      onLongPress: bodyParts.isEmpty
                          ? null
                          : () => _showBodyPartsForDate(
                              context,
                              date: date,
                              bodyParts: bodyParts,
                            ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '기록이 있는 날짜를 누르면 해당 기록으로 이동합니다.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showBodyPartsForDate(
    BuildContext context, {
    required DateTime date,
    required List<String> bodyParts,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${DateFormat('M월 d일').format(date)} 운동 부위'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('이날 기록된 전체 부위입니다.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final bodyPart in bodyParts) Chip(label: Text(bodyPart)),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }
}

class _MonthlyBodyPartCalendarDayCell extends StatelessWidget {
  const _MonthlyBodyPartCalendarDayCell({
    required this.date,
    required this.bodyParts,
    required this.isCurrentMonth,
    required this.isToday,
    required this.onTap,
    required this.onLongPress,
  });

  final DateTime date;
  final List<String> bodyParts;
  final bool isCurrentMonth;
  final bool isToday;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasRecords = bodyParts.isNotEmpty;
    final bodyPartLabel = hasRecords ? _compactBodyPartLabel(bodyParts) : null;
    final foregroundColor = !isCurrentMonth
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.45)
        : hasRecords
        ? colorScheme.onSurface
        : colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('monthly-calendar-day-${_dateKey(date)}'),
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isToday
                ? colorScheme.primaryContainer
                : hasRecords
                ? colorScheme.surfaceContainerHighest
                : colorScheme.surface,
            border: Border.all(
              color: isToday
                  ? colorScheme.primary
                  : hasRecords
                  ? colorScheme.outlineVariant
                  : colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${date.day}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foregroundColor,
                  fontWeight: isToday ? FontWeight.bold : null,
                ),
              ),
              const SizedBox(height: 2),
              if (hasRecords)
                Text(
                  bodyPartLabel!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: foregroundColor,
                    fontWeight: bodyParts.length > 1 ? FontWeight.w600 : null,
                  ),
                )
              else
                Text(
                  isCurrentMonth ? '휴식' : '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: foregroundColor),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WorkoutRecordList extends StatefulWidget {
  const _WorkoutRecordList({
    required this.records,
    required this.scrollController,
    required this.isLoadingMore,
    required this.hasMoreRecords,
    required this.loadMoreError,
    required this.onLoadMoreRetry,
    required this.bodyWeightKg,
    required this.usesDefaultBodyWeight,
    required this.focusedDate,
    required this.focusRequestId,
    required this.onRecordTap,
    required this.onRecordDelete,
  });

  final List<WorkoutRecord> records;
  final ScrollController scrollController;
  final bool isLoadingMore;
  final bool hasMoreRecords;
  final Object? loadMoreError;
  final VoidCallback onLoadMoreRetry;
  final double bodyWeightKg;
  final bool usesDefaultBodyWeight;
  final DateTime? focusedDate;
  final int focusRequestId;
  final ValueChanged<_RecordEntryItem> onRecordTap;
  final ValueChanged<_RecordEntryItem> onRecordDelete;

  @override
  State<_WorkoutRecordList> createState() => _WorkoutRecordListState();
}

class _WorkoutRecordListState extends State<_WorkoutRecordList> {
  final Map<String, GlobalKey> _dateHeaderKeys = {};

  @override
  void didUpdateWidget(covariant _WorkoutRecordList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focusedDate = widget.focusedDate;
    if (focusedDate == null ||
        widget.focusRequestId == oldWidget.focusRequestId) {
      return;
    }
    final focusedDateKey = _dateKey(focusedDate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _dateHeaderKeys[focusedDateKey]?.currentContext;
      if (context == null) {
        return;
      }
      final renderObject = context.findRenderObject();
      final viewport = renderObject == null
          ? null
          : RenderAbstractViewport.maybeOf(renderObject);
      if (viewport == null || !widget.scrollController.hasClients) {
        return;
      }
      final position = widget.scrollController.position;
      final offset = viewport.getOffsetToReveal(renderObject!, 0.02).offset;
      widget.scrollController.animateTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _flattenRecords(widget.records);
    return SingleChildScrollView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            switch (item) {
              _RecordDateHeader() => Padding(
                key: _dateHeaderKeys.putIfAbsent(
                  _dateKey(item.date),
                  () => GlobalKey(),
                ),
                padding: const EdgeInsets.only(top: 16, bottom: 10),
                child: Text(
                  DateFormat('yyyy.MM.dd').format(item.date),
                  key: ValueKey(
                    'record-date-header-label-${_dateKey(item.date)}',
                  ),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              _RecordDateSummaryItem() => _WorkoutDateSummaryCard(
                item: item,
                bodyWeightKg: widget.bodyWeightKg,
                usesDefaultBodyWeight: widget.usesDefaultBodyWeight,
              ),
              _RecordEntryItem() => _WorkoutRecordCard(
                item: item,
                bodyWeightKg: widget.bodyWeightKg,
                usesDefaultBodyWeight: widget.usesDefaultBodyWeight,
                onTap: () => widget.onRecordTap(item),
                onDelete: () => widget.onRecordDelete(item),
              ),
            },
          if (widget.isLoadingMore)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (widget.loadMoreError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: OutlinedButton.icon(
                onPressed: widget.onLoadMoreRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('기록 더 불러오기'),
              ),
            )
          else if (!widget.hasMoreRecords)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Text(
                '마지막 기록입니다',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _WorkoutDateSummaryCard extends StatelessWidget {
  const _WorkoutDateSummaryCard({
    required this.item,
    required this.bodyWeightKg,
    required this.usesDefaultBodyWeight,
  });

  final _RecordDateSummaryItem item;
  final double bodyWeightKg;
  final bool usesDefaultBodyWeight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bodyPartsText = item.bodyPartNames.join(' · ');
    final estimatedCalories = _estimateWorkoutCalories(
      entries: item.entries,
      bodyWeightKg: bodyWeightKg,
    );

    return Card(
      key: ValueKey('record-date-summary-${_dateKey(item.date)}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.bolt_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    bodyPartsText.isEmpty ? '운동 부위 없음' : bodyPartsText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MetricTile(
                    label: '총 볼륨',
                    value: '${_formatVolume(item.totalVolume)}kg',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MetricTile(
                    label: '구성',
                    value: '${item.entryCount}종목 · ${item.setCount}세트',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '예상 ${estimatedCalories.round()}kcal${usesDefaultBodyWeight ? ' · 70kg 기준' : ''}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutRecordCard extends StatelessWidget {
  const _WorkoutRecordCard({
    required this.item,
    required this.bodyWeightKg,
    required this.usesDefaultBodyWeight,
    required this.onTap,
    required this.onDelete,
  });

  final _RecordEntryItem item;
  final double bodyWeightKg;
  final bool usesDefaultBodyWeight;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final entry = item.entry;
    final dateText = DateFormat('yyyy.MM.dd').format(item.date);
    final setCount = entry.sets.length;
    final warmupSetCount = entry.sets.where((set) => set.isWarmup).length;
    final totalVolume = entry.sets.fold<double>(
      0,
      (sum, set) => sum + set.weight * set.reps,
    );
    final estimatedCalories = _estimateExerciseCalories(
      sets: entry.sets,
      bodyWeightKg: bodyWeightKg,
      exerciseTypeId: entry.exercise.type,
    );
    final memoSummary = _memoSummary(entry.entry.memo ?? item.sessionMemo);

    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F7FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.fitness_center_rounded,
                      color: colorScheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateText,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.exercise.name,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    tooltip: '기록 삭제',
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _MetricTile(
                      label: '볼륨',
                      value: '${_formatVolume(totalVolume)}kg',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricTile(label: '세트', value: '$setCount세트'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MetricTile(
                      label: '칼로리',
                      value: '${estimatedCalories.round()}kcal',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _RecordChip(label: entry.bodyPart.name),
                  if (warmupSetCount > 0)
                    _RecordChip(label: '워밍업 $warmupSetCount세트'),
                  if (usesDefaultBodyWeight)
                    const _RecordChip(label: '70kg 기준'),
                ],
              ),
              if (memoSummary != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    memoSummary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8EEF6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _RecordChip extends StatelessWidget {
  const _RecordChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(label),
      labelStyle: TextStyle(
        color: colorScheme.primary,
        fontWeight: FontWeight.w800,
      ),
      backgroundColor: colorScheme.primary.withValues(alpha: 0.08),
      side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.14)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

sealed class _RecordListItem {}

class _RecordDateHeader extends _RecordListItem {
  _RecordDateHeader(this.date);

  final DateTime date;
}

class _RecordDateSummaryItem extends _RecordListItem {
  _RecordDateSummaryItem({
    required this.date,
    required this.bodyPartNames,
    required this.totalVolume,
    required this.entryCount,
    required this.setCount,
    required this.entries,
  });

  final DateTime date;
  final List<String> bodyPartNames;
  final double totalVolume;
  final int entryCount;
  final int setCount;
  final List<WorkoutEntryRecord> entries;
}

class _RecordEntryItem extends _RecordListItem {
  _RecordEntryItem({
    required this.sessionId,
    required this.date,
    required this.sessionMemo,
    required this.entry,
  });

  final int sessionId;
  final DateTime date;
  final String? sessionMemo;
  final WorkoutEntryRecord entry;
}

List<_RecordListItem> _flattenRecords(List<WorkoutRecord> records) {
  final items = <_RecordListItem>[];
  var index = 0;

  while (index < records.length) {
    final recordsForDate = <WorkoutRecord>[];
    final date = records[index].session.workoutDate;
    final dateKey = DateFormat('yyyyMMdd').format(date);

    while (index < records.length &&
        DateFormat('yyyyMMdd').format(records[index].session.workoutDate) ==
            dateKey) {
      recordsForDate.add(records[index]);
      index += 1;
    }

    items.add(_RecordDateHeader(date));
    items.add(_buildDateSummaryItem(date: date, records: recordsForDate));

    for (final record in recordsForDate) {
      final recordDate = record.session.workoutDate;
      for (final entry in record.entries) {
        items.add(
          _RecordEntryItem(
            sessionId: record.session.id,
            date: recordDate,
            sessionMemo: record.session.memo,
            entry: entry,
          ),
        );
      }
    }
  }

  return items;
}

_RecordDateSummaryItem _buildDateSummaryItem({
  required DateTime date,
  required List<WorkoutRecord> records,
}) {
  final bodyPartNames = <String>[];
  final entries = <WorkoutEntryRecord>[];
  var totalVolume = 0.0;
  var entryCount = 0;

  for (final record in records) {
    for (final entry in record.entries) {
      entryCount += 1;
      final bodyPartName = entry.bodyPart.name;
      if (!bodyPartNames.contains(bodyPartName)) {
        bodyPartNames.add(bodyPartName);
      }
      entries.add(entry);
      totalVolume += entry.sets.fold<double>(
        0,
        (sum, set) => sum + set.weight * set.reps,
      );
    }
  }

  return _RecordDateSummaryItem(
    date: date,
    bodyPartNames: bodyPartNames,
    totalVolume: totalVolume,
    entryCount: entryCount,
    setCount: entries.fold<int>(0, (sum, entry) => sum + entry.sets.length),
    entries: entries,
  );
}

String _compactBodyPartLabel(List<String> bodyParts) {
  if (bodyParts.length <= 1) {
    return bodyParts.first;
  }
  return '${bodyParts.first} +${bodyParts.length - 1}';
}

Map<String, List<String>> _bodyPartsByDate(List<WorkoutRecord> records) {
  final result = <String, List<String>>{};

  for (final record in records) {
    final workoutDate = DateTime(
      record.session.workoutDate.year,
      record.session.workoutDate.month,
      record.session.workoutDate.day,
    );
    final key = _dateKey(workoutDate);
    final bodyParts = result.putIfAbsent(key, () => <String>[]);
    for (final entry in record.entries) {
      final bodyPartName = entry.bodyPart.name;
      if (!bodyParts.contains(bodyPartName)) {
        bodyParts.add(bodyPartName);
      }
    }
  }

  return result;
}

Map<String, List<String>> _bodyPartsByDay(
  List<WorkoutRecord> records,
  DateTime weekStart,
) {
  final weekEnd = weekStart.add(const Duration(days: 7));
  final result = <String, List<String>>{};

  for (final record in records) {
    final workoutDate = DateTime(
      record.session.workoutDate.year,
      record.session.workoutDate.month,
      record.session.workoutDate.day,
    );
    if (workoutDate.isBefore(weekStart) || !workoutDate.isBefore(weekEnd)) {
      continue;
    }

    final key = _dateKey(workoutDate);
    final bodyParts = result.putIfAbsent(key, () => <String>[]);
    for (final entry in record.entries) {
      final bodyPartName = entry.bodyPart.name;
      if (!bodyParts.contains(bodyPartName)) {
        bodyParts.add(bodyPartName);
      }
    }
  }

  return result;
}

String _dateKey(DateTime date) => DateFormat('yyyyMMdd').format(date);

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _weekdayLabel(int weekday) {
  return switch (weekday) {
    DateTime.monday => '월',
    DateTime.tuesday => '화',
    DateTime.wednesday => '수',
    DateTime.thursday => '목',
    DateTime.friday => '금',
    DateTime.saturday => '토',
    DateTime.sunday => '일',
    _ => '',
  };
}

String _formatVolume(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
}

double _estimateWorkoutCalories({
  required List<WorkoutEntryRecord> entries,
  required double bodyWeightKg,
}) {
  return entries.fold<double>(
    0,
    (sum, entry) =>
        sum +
        _estimateExerciseCalories(
          sets: entry.sets,
          bodyWeightKg: bodyWeightKg,
          exerciseTypeId: entry.exercise.type,
        ),
  );
}

double _estimateExerciseCalories({
  required List<WorkoutSet> sets,
  required double bodyWeightKg,
  required String? exerciseTypeId,
}) {
  const workingSetMinutes = 2.5;
  const warmupSetMinutes = 1.5;
  final estimatedMinutes = sets.fold<double>(
    0,
    (sum, set) => sum + (set.isWarmup ? warmupSetMinutes : workingSetMinutes),
  );
  return metForExerciseType(exerciseTypeId) *
      bodyWeightKg *
      (estimatedMinutes / 60);
}

String? _memoSummary(String? memo) {
  final trimmed = memo?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
