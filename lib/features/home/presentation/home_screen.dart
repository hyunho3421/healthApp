import 'package:flutter/material.dart';
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
  late Future<List<WorkoutRecord>> _recordsFuture;
  late Future<double?> _bodyWeightKgFuture;
  DateTime? _focusedWorkoutDate;
  int _focusRequestId = 0;

  @override
  void initState() {
    super.initState();
    _recordsFuture = _loadRecords();
    _bodyWeightKgFuture = ref
        .read(userProfileServiceProvider)
        .getBodyWeightKg();
  }

  Future<List<WorkoutRecord>> _loadRecords() {
    return ref.read(workoutServiceProvider).getWorkoutRecords();
  }

  void _refreshRecords() {
    if (!mounted) {
      return;
    }
    setState(() {
      _recordsFuture = _loadRecords();
    });
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
    setState(() {
      _focusedWorkoutDate = DateTime(date.year, date.month, date.day);
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
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('근육 성장 일기'),
        actions: [
          IconButton(
            onPressed: _openProfileSettings,
            icon: const Icon(Icons.person_outline),
            tooltip: '설정/프로필',
          ),
          IconButton(
            onPressed: _openStats,
            icon: const Icon(Icons.bar_chart),
            tooltip: '통계',
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<List<WorkoutRecord>>(
          future: _recordsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('기록을 불러오지 못했습니다: ${snapshot.error}'),
                ),
              );
            }
            final records = snapshot.data ?? const [];
            return Column(
              children: [
                _WeeklyBodyPartSummary(
                  records: records,
                  onDateTap: _focusWorkoutDate,
                ),
                Expanded(
                  child: records.isEmpty
                      ? const _EmptyRecordsState()
                      : FutureBuilder<double?>(
                          future: _bodyWeightKgFuture,
                          builder: (context, weightSnapshot) =>
                              _WorkoutRecordList(
                                records: records,
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
            );
          },
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

class _EmptyRecordsState extends StatelessWidget {
  const _EmptyRecordsState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '아직 운동 기록이 없습니다.\n기록 추가 버튼으로 첫 운동을 남겨 보세요.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _WeeklyBodyPartSummary extends StatelessWidget {
  const _WeeklyBodyPartSummary({
    required this.records,
    required this.onDateTap,
  });

  final List<WorkoutRecord> records;
  final ValueChanged<DateTime> onDateTap;

  Future<void> _showMonthlyBodyPartCalendar(BuildContext context) async {
    final selectedDate = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MonthlyBodyPartCalendarSheet(records: records),
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

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '이번 주 운동 부위',
                  style: Theme.of(context).textTheme.titleLarge,
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
          const SizedBox(height: 12),
          SizedBox(
            height: 104,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 7,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
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
    final bodyText = bodyParts.isEmpty ? '휴식' : bodyParts.join('\n');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('weekly-day-${_dateKey(date)}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 76,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isToday ? colorScheme.primaryContainer : colorScheme.surface,
            border: Border.all(
              color: isToday ? colorScheme.primary : colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _weekdayLabel(date.weekday),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(
                DateFormat('M.d').format(date),
                style: Theme.of(context).textTheme.labelSmall,
              ),
              const Spacer(),
              Text(
                bodyText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: bodyParts.isEmpty
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onSurface,
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
    required this.bodyWeightKg,
    required this.usesDefaultBodyWeight,
    required this.focusedDate,
    required this.focusRequestId,
    required this.onRecordTap,
    required this.onRecordDelete,
  });

  final List<WorkoutRecord> records;
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
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.02,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _flattenRecords(widget.records);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final item in items)
            switch (item) {
              _RecordDateHeader() => Padding(
                key: _dateHeaderKeys.putIfAbsent(
                  _dateKey(item.date),
                  () => GlobalObjectKey(
                    'record-date-header-${_dateKey(item.date)}',
                  ),
                ),
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text(
                  DateFormat('yyyy.MM.dd').format(item.date),
                  key: ValueKey(
                    'record-date-header-label-${_dateKey(item.date)}',
                  ),
                  style: Theme.of(context).textTheme.titleMedium,
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
      margin: const EdgeInsets.only(bottom: 8),
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              bodyPartsText.isEmpty ? '운동 부위 없음' : bodyPartsText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(color: colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              '총 볼륨 ${_formatVolume(item.totalVolume)}kg',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              '${item.entryCount}종목 · ${item.setCount}세트 · 예상 ${estimatedCalories.round()}kcal${usesDefaultBodyWeight ? ' · 70kg 기준' : ''}',
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateText,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.exercise.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '기록 삭제',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _RecordChip(label: entry.bodyPart.name),
                  _RecordChip(label: '$setCount세트'),
                  if (warmupSetCount > 0)
                    _RecordChip(label: '워밍업 $warmupSetCount세트'),
                  _RecordChip(label: '총 볼륨 ${_formatVolume(totalVolume)}kg'),
                  _RecordChip(
                    label:
                        '예상 ${estimatedCalories.round()}kcal${usesDefaultBodyWeight ? ' · 70kg 기준' : ''}',
                  ),
                ],
              ),
              if (memoSummary != null) ...[
                const SizedBox(height: 8),
                Text(memoSummary, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordChip extends StatelessWidget {
  const _RecordChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
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
