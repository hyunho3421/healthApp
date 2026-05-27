import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/seed/workout_seed_data.dart';
import '../../../core/formatters/metric_number_formatter.dart';
import '../../../core/models/exercise_type.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/centered_toast.dart';
import '../../profile/providers/user_profile_providers.dart';
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
  late Future<_HomeSummary> _homeSummaryFuture;

  @override
  void initState() {
    super.initState();
    _homeSummaryFuture = _loadHomeSummary();
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

  void _refreshHome() {
    if (!mounted) {
      return;
    }
    setState(() {
      _homeSummaryFuture = _loadHomeSummary();
    });
  }

  Future<void> _openAddWorkout() async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const AddWorkoutScreen()));
    if (!mounted || saved != true) {
      return;
    }
    _refreshHome();
    CenteredToast.show(context, '운동 기록을 저장했습니다.');
  }

  void _openStats() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const StatsScreen()));
  }

  Future<void> _openWorkoutRecords({DateTime? focusedDate}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _WorkoutRecordListScreen(
          initialFocusedDate: focusedDate == null
              ? null
              : DateTime(focusedDate.year, focusedDate.month, focusedDate.day),
        ),
      ),
    );
    if (!mounted || changed != true) {
      return;
    }
    _refreshHome();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: FutureBuilder<_HomeSummary>(
          future: _homeSummaryFuture,
          builder: (context, summarySnapshot) {
            if (summarySnapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (summarySnapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('홈 정보를 불러오지 못했습니다: ${summarySnapshot.error}'),
                ),
              );
            }

            final summary = summarySnapshot.data;
            final weeklyRecords =
                summary?.weeklyRecords ?? const <WorkoutRecord>[];
            final monthlyRecords =
                summary?.monthlyRecords ?? const <WorkoutRecord>[];

            return RefreshIndicator(
              onRefresh: () async {
                setState(() {
                  _homeSummaryFuture = _loadHomeSummary();
                });
                await _homeSummaryFuture;
              },
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  _WeeklyBodyStatusCard(
                    records: weeklyRecords,
                    totalSetCount: summary?.totalSetCount ?? 0,
                    onRecordsTap: _openWorkoutRecords,
                    onStatsTap: _openStats,
                  ),
                  _WeeklyBodyPartSummary(
                    records: weeklyRecords,
                    monthlyRecords: monthlyRecords,
                    onDateTap: (date) => _openWorkoutRecords(focusedDate: date),
                  ),
                ],
              ),
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

class _WorkoutRecordListScreen extends ConsumerStatefulWidget {
  const _WorkoutRecordListScreen({this.initialFocusedDate});

  final DateTime? initialFocusedDate;

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
  DateTime? _focusedDate;
  int _focusRequestId = 0;

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
      await _focusInitialDateIfNeeded();
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

  Future<void> _loadMoreRecords() => _loadMoreRecordsPage();

  Future<bool> _loadMoreRecordsPage() async {
    if (_isInitialRecordsLoading ||
        _isLoadingMoreRecords ||
        !_hasMoreRecords ||
        _records.isEmpty) {
      return false;
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
        return false;
      }
      setState(() {
        _records.addAll(page.take(_recordsPageSize));
        _hasMoreRecords = page.length > _recordsPageSize;
        _isLoadingMoreRecords = false;
      });
      return page.isNotEmpty;
    } catch (error) {
      if (!mounted) {
        return false;
      }
      setState(() {
        _recordsLoadError = error;
        _isLoadingMoreRecords = false;
      });
      return false;
    }
  }

  Future<void> _focusInitialDateIfNeeded() async {
    final targetDate = widget.initialFocusedDate;
    if (targetDate == null) {
      return;
    }

    while (mounted &&
        !_recordsContainDate(targetDate) &&
        _hasMoreRecords &&
        !_isLoadingMoreRecords) {
      final loaded = await _loadMoreRecordsPage();
      if (!loaded) {
        break;
      }
    }

    if (!mounted || !_recordsContainDate(targetDate)) {
      return;
    }
    setState(() {
      _focusedDate = targetDate;
      _focusRequestId += 1;
    });
  }

  bool _recordsContainDate(DateTime date) {
    return _records.any(
      (record) => _isSameDay(record.session.workoutDate, date),
    );
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
        title: Row(
          children: [
            const Expanded(child: Text('기록 삭제')),
            IconButton(
              onPressed: () => Navigator.of(context).pop(false),
              icon: const Icon(Icons.close_rounded),
              tooltip: '닫기',
            ),
          ],
        ),
        content: Text('${item.entry.exercise.name} 기록을 삭제할까요?'),
        actions: [
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
                    focusedDate: _focusedDate,
                    focusRequestId: _focusRequestId,
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

const _trackedBodyParts = <String>['가슴', '등', '어깨', '팔', '하체', '복근'];

String _normalizeBodyPartName(String name) {
  return name == '코어' ? '복근' : name;
}

Color _bodyPartStatusColor(int count) {
  if (count >= 3) {
    return const Color(0xFFEF4444);
  }
  if (count == 2) {
    return const Color(0xFF3B82F6);
  }
  if (count == 1) {
    return const Color(0xFFFACC15);
  }
  return const Color(0xFFE5E7EB);
}

Map<String, int> _weeklyBodyPartCounts(
  List<WorkoutRecord> records, {
  required DateTime weekStart,
}) {
  final weekEnd = weekStart.add(const Duration(days: 7));
  final counts = {for (final part in _trackedBodyParts) part: 0};
  final bodyPartDates = <String, Set<String>>{
    for (final part in _trackedBodyParts) part: <String>{},
  };
  final armDetailDates = <String, Set<String>>{
    _bodyPartCountArmBicepsKey: <String>{},
    _bodyPartCountArmTricepsKey: <String>{},
  };

  for (final record in records) {
    final workoutDate = DateTime(
      record.session.workoutDate.year,
      record.session.workoutDate.month,
      record.session.workoutDate.day,
    );
    if (workoutDate.isBefore(weekStart) || !workoutDate.isBefore(weekEnd)) {
      continue;
    }
    final dateKey = _dateKey(workoutDate);

    for (final entry in record.entries) {
      final bodyPartName = _normalizeBodyPartName(entry.bodyPart.name);
      if (_trackedBodyParts.contains(bodyPartName)) {
        bodyPartDates[bodyPartName]?.add(dateKey);
      }
      if (bodyPartName == '팔') {
        switch (entry.exercise.armDetail) {
          case armDetailBiceps:
            armDetailDates[_bodyPartCountArmBicepsKey]?.add(dateKey);
          case armDetailTriceps:
            armDetailDates[_bodyPartCountArmTricepsKey]?.add(dateKey);
          default:
            armDetailDates[_bodyPartCountArmBicepsKey]?.add(dateKey);
            armDetailDates[_bodyPartCountArmTricepsKey]?.add(dateKey);
        }
      }
    }
  }

  for (final entry in bodyPartDates.entries) {
    counts[entry.key] = entry.value.length;
  }
  for (final entry in armDetailDates.entries) {
    counts[entry.key] = entry.value.length;
  }

  return counts;
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

class _WeeklyBodyStatusCard extends StatelessWidget {
  const _WeeklyBodyStatusCard({
    required this.records,
    required this.totalSetCount,
    required this.onRecordsTap,
    required this.onStatsTap,
  });

  final List<WorkoutRecord> records;
  final int totalSetCount;
  final VoidCallback onRecordsTap;
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
    final counts = _weeklyBodyPartCounts(records, weekStart: weekStart);
    final trainedPartCount = counts.values.where((count) => count > 0).length;
    final overtrainedPartCount = counts.values
        .where((count) => count >= 3)
        .length;
    final weekLabel =
        '${DateFormat('M.d').format(weekStart)} - ${DateFormat('M.d').format(weekEnd.subtract(const Duration(days: 1)))}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppTheme.heroGradient,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryDark.withValues(alpha: 0.18),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.accessibility_new_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '이번 주 부위별 운동',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        weekLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onStatsTap,
                  icon: const Icon(
                    Icons.bar_chart_rounded,
                    color: Colors.white,
                  ),
                  tooltip: '운동 통계',
                ),
              ],
            ),
            const SizedBox(height: 16),
            _BodyMapFigure(counts: counts),
            const SizedBox(height: 12),
            _BodyPartStatusGrid(counts: counts),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _BodyPartLegendDot(color: Color(0xFFE5E7EB), label: '휴식'),
                _BodyPartLegendDot(color: Color(0xFFFACC15), label: '1회'),
                _BodyPartLegendDot(color: Color(0xFF3B82F6), label: '2회'),
                _BodyPartLegendDot(color: Color(0xFFEF4444), label: '3회+ 과훈련'),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    overtrainedPartCount > 0
                        ? '$overtrainedPartCount개 부위는 과훈련 주의가 필요해요.'
                        : trainedPartCount == 0
                        ? '아직 이번 주 운동 기록이 없어요.'
                        : '$trainedPartCount개 부위를 이번 주에 자극했어요.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.86),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: onRecordsTap,
                  icon: const Icon(Icons.event_note_rounded, size: 18),
                  label: const Text('기록 보기'),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                ),
              ],
            ),
            Text(
              '누적 세트 $totalSetCount개',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.60),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _bodyMapReferenceAsset = 'assets/body_map/front_back_human_reference.png';
const _bodyMapReferenceSize = Size(1536, 1024);
const _bodyMapFigureVerticalLabelPadding = 64.0;
const _bodyPartCountArmBicepsKey = '_arm:biceps';
const _bodyPartCountArmTricepsKey = '_arm:triceps';

class _BodyMapFigure extends StatefulWidget {
  const _BodyMapFigure({required this.counts});

  final Map<String, int> counts;

  @override
  State<_BodyMapFigure> createState() => _BodyMapFigureState();
}

class _BodyMapFigureState extends State<_BodyMapFigure> {
  late final Future<ui.Image> _silhouetteMaskImageFuture = _loadUiImage(
    _bodyMapReferenceAsset,
  );

  Future<ui.Image> _loadUiImage(String assetName) async {
    final data = await rootBundle.load(assetName);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      completer.complete,
    );
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      // Keep the source PNG width while giving the bottom captions enough
      // vertical room outside the reference image bounds to avoid clipping.
      aspectRatio:
          _bodyMapReferenceSize.width /
          (_bodyMapReferenceSize.height + _bodyMapFigureVerticalLabelPadding),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE8EEF6)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                _bodyMapReferenceAsset,
                fit: BoxFit.contain,
                color: const Color(0xFFD1D8E3),
                colorBlendMode: BlendMode.srcIn,
                filterQuality: FilterQuality.high,
              ),
              FutureBuilder<ui.Image>(
                future: _silhouetteMaskImageFuture,
                builder: (context, snapshot) {
                  final silhouetteMaskImage = snapshot.data;
                  if (silhouetteMaskImage == null) {
                    return const SizedBox.shrink();
                  }
                  return CustomPaint(
                    painter: _BodyMapPainter(
                      widget.counts,
                      silhouetteMaskImage: silhouetteMaskImage,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _BodyRegion {
  chest,
  back,
  shoulders,
  biceps,
  triceps,
  abs,
  frontThighs,
  glutes,
  hamstrings,
  calves,
}

const Map<String, List<_BodyRegion>> _bodyPartRegionMap = {
  '가슴': [_BodyRegion.chest],
  '등': [_BodyRegion.back],
  '어깨': [_BodyRegion.shoulders],
  '팔': [_BodyRegion.biceps, _BodyRegion.triceps],
  _bodyPartCountArmBicepsKey: [_BodyRegion.biceps],
  _bodyPartCountArmTricepsKey: [_BodyRegion.triceps],
  '복근': [_BodyRegion.abs],
  // Keep the current six-part aggregation while separating the paint layer into
  // extensible leg regions: front quadriceps, rear hamstrings, and rear calves.
  '하체': [
    _BodyRegion.frontThighs,
    _BodyRegion.glutes,
    _BodyRegion.hamstrings,
    _BodyRegion.calves,
  ],
};

class _BodyMapPainter extends CustomPainter {
  const _BodyMapPainter(this.counts, {required this.silhouetteMaskImage});

  final Map<String, int> counts;
  final ui.Image silhouetteMaskImage;

  @override
  void paint(Canvas canvas, Size size) {
    final imageRect = _containedRect(_bodyMapReferenceSize, size);
    final regionCounts = _regionCounts(counts);

    Offset ip(double x, double y) => Offset(
      imageRect.left + imageRect.width * (x / _bodyMapReferenceSize.width),
      imageRect.top + imageRect.height * (y / _bodyMapReferenceSize.height),
    );

    double highlightAlphaFor(int count) {
      if (count >= 3) {
        return 0.74;
      }
      if (count == 2) {
        return 0.64;
      }
      if (count == 1) {
        return 0.54;
      }
      return 0;
    }

    Paint fillFor(int count) => Paint()
      ..color = _bodyPartStatusColor(
        count,
      ).withValues(alpha: highlightAlphaFor(count))
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    void drawRegion(
      _BodyRegion region,
      List<Path> shapes, {
      required Path clip,
    }) {
      final count = regionCounts[region] ?? 0;
      if (count == 0) {
        return;
      }

      final fill = fillFor(count);
      canvas.save();
      canvas.clipPath(clip, doAntiAlias: true);
      for (final path in shapes) {
        canvas.drawPath(path, fill);
      }
      canvas.restore();
    }

    void drawAbsDetails({required Path clip}) {
      final count = regionCounts[_BodyRegion.abs] ?? 0;
      if (count == 0) {
        return;
      }

      final line = Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = imageRect.width * 0.0042
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;

      canvas.save();
      canvas.clipPath(clip, doAntiAlias: true);
      for (final path in _frontAbsDetailPaths(ip)) {
        canvas.drawPath(path, line);
      }
      canvas.restore();
    }

    // Source measurements are taken against the 1536x1024 reference PNG:
    // front bbox ~= x 281-590 y 56-971, back bbox ~= x 944-1254 y 56-971.
    // Region paths remain anatomical masks. The approximate vector silhouettes
    // are only a local guard; the overlay layer is finally intersected with the
    // real reference PNG alpha via dstIn, so colored fills cannot render outside
    // the asset silhouette even when vector control points differ by pixels.
    final sourceRect = Rect.fromLTWH(
      0,
      0,
      silhouetteMaskImage.width.toDouble(),
      silhouetteMaskImage.height.toDouble(),
    );
    final frontClip = _frontSilhouetteMask(ip);
    final backClip = _backSilhouetteMask(ip);

    canvas.saveLayer(imageRect, Paint());
    drawRegion(_BodyRegion.back, [_backLatPath(ip)], clip: backClip);
    drawRegion(_BodyRegion.shoulders, _frontDeltoidPaths(ip), clip: frontClip);
    drawRegion(_BodyRegion.shoulders, _backDeltoidPaths(ip), clip: backClip);
    drawRegion(_BodyRegion.biceps, _frontBicepsPaths(ip), clip: frontClip);
    drawRegion(_BodyRegion.triceps, _backTricepsPaths(ip), clip: backClip);
    drawRegion(_BodyRegion.chest, _frontPectoralPaths(ip), clip: frontClip);
    drawRegion(_BodyRegion.abs, [_frontAbsPath(ip)], clip: frontClip);
    drawAbsDetails(clip: frontClip);
    drawRegion(_BodyRegion.frontThighs, _frontThighPaths(ip), clip: frontClip);
    drawRegion(_BodyRegion.glutes, _backGlutePaths(ip), clip: backClip);
    drawRegion(_BodyRegion.hamstrings, _backHamstringPaths(ip), clip: backClip);
    drawRegion(_BodyRegion.calves, _backCalfPaths(ip), clip: backClip);
    canvas.drawImageRect(
      silhouetteMaskImage,
      sourceRect,
      imageRect,
      Paint()
        ..blendMode = BlendMode.dstIn
        ..filterQuality = FilterQuality.high,
    );
    canvas.restore();

    void drawCaption(String label, Offset center) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.2,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: ui.TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(center.dx - painter.width / 2, center.dy));
    }

    drawCaption('전면', ip(436, 982));
    drawCaption('후면', ip(1099, 982));
  }

  Path _frontSilhouetteMask(Offset Function(double x, double y) ip) =>
      _smoothClosedPath([
        ip(433, 70),
        ip(382, 100),
        ip(366, 178),
        ip(300, 238),
        ip(260, 356),
        ip(286, 514),
        ip(300, 690),
        ip(334, 724),
        ip(348, 892),
        ip(373, 956),
        ip(418, 958),
        ip(433, 840),
        ip(448, 958),
        ip(493, 956),
        ip(518, 892),
        ip(532, 724),
        ip(566, 690),
        ip(580, 514),
        ip(606, 356),
        ip(566, 238),
        ip(500, 178),
        ip(484, 100),
      ]);

  Path _backSilhouetteMask(Offset Function(double x, double y) ip) =>
      _smoothClosedPath([
        ip(1099, 70),
        ip(1048, 100),
        ip(1032, 178),
        ip(966, 238),
        ip(926, 356),
        ip(952, 514),
        ip(966, 690),
        ip(1000, 724),
        ip(1014, 892),
        ip(1039, 956),
        ip(1084, 958),
        ip(1099, 840),
        ip(1114, 958),
        ip(1159, 956),
        ip(1184, 892),
        ip(1198, 724),
        ip(1232, 690),
        ip(1246, 514),
        ip(1272, 356),
        ip(1232, 238),
        ip(1166, 178),
        ip(1150, 100),
      ]);

  List<Path> _frontPectoralPaths(Offset Function(double x, double y) ip) => [
    // Traced from the user-provided red chest mask reference. Image-space red
    // components were thresholded and mapped onto the front figure with the
    // sternum centered at x ~= 433. The left/right masks are nudged
    // closer together so the visible gap is about 20% narrower.
    _closedPolygonPath([
      ip(344, 295),
      ip(353, 256),
      ip(361, 245),
      ip(409, 241),
      ip(422, 244),
      ip(426, 255),
      ip(426, 278),
      ip(422, 324),
      ip(417, 329),
      ip(405, 332),
      ip(382, 329),
      ip(374, 324),
    ]),
    _closedPolygonPath([
      ip(440, 256),
      ip(444, 244),
      ip(449, 241),
      ip(496, 243),
      ip(505, 245),
      ip(513, 255),
      ip(522, 298),
      ip(484, 329),
      ip(461, 332),
      ip(449, 329),
      ip(444, 324),
    ]),
  ];

  Path _frontAbsPath(Offset Function(double x, double y) ip) =>
      _smoothClosedPath([
        // Traced from the user-provided red abdominal mask reference. The
        // source red component bbox was x=516..684, y=530..804 in the
        // 1080x1457 PNG, mapped from that image silhouette bbox
        // x=366..832, y=36..1433 onto the app front bbox x=281..590,
        // y=56..971.
        ip(408, 356),
        ip(383, 372),
        ip(386, 388),
        ip(387, 405),
        ip(386, 421),
        ip(383, 437),
        ip(380, 454),
        ip(380, 470),
        ip(383, 487),
        ip(394, 503),
        ip(408, 519),
        ip(464, 519),
        ip(478, 503),
        ip(489, 487),
        ip(492, 470),
        ip(492, 454),
        ip(489, 437),
        ip(486, 421),
        ip(485, 405),
        ip(487, 388),
        ip(489, 372),
        ip(469, 356),
      ]);

  List<Path> _frontAbsDetailPaths(Offset Function(double x, double y) ip) =>
      const <Path>[];

  Path _backLatPath(
    Offset Function(double x, double y) ip,
  ) => _smoothClosedPath([
    // Extracted from the user-provided red back mask:
    // PNG red threshold bbox (490,298)-(701,672), single connected component.
    // Mapped from source body bbox (365,38)-(829,1425) into the back figure
    // reference bbox (944,56)-(1254,971).
    ip(1058, 228),
    ip(1138, 228),
    ip(1150, 236),
    ip(1168, 307),
    ip(1155, 386),
    ip(1160, 461),
    ip(1152, 468),
    ip(1114, 474),
    ip(1084, 474),
    ip(1051, 470),
    ip(1036, 461),
    ip(1041, 388),
    ip(1028, 308),
    ip(1045, 237),
  ]);

  List<Path> _frontDeltoidPaths(Offset Function(double x, double y) ip) => [
    // Extracted from the user-provided red shoulder mask and transformed from
    // screenshot body coordinates into the 1536x1024 reference asset space.
    // The mask is intentionally full around the anterior deltoid cap so the
    // shoulder fill reaches the clavicle side, outer shoulder edge, and natural
    // lower insertion before the PNG alpha clip trims it to the silhouette.
    // Latest adjustment: screen-right anterior deltoid body-side edge was
    // expanded back by about 5% while preserving the outer shoulder boundary.
    _closedPolygonPath([
      ip(350, 176),
      ip(338, 184),
      ip(306, 204),
      ip(278, 236),
      ip(254, 282),
      ip(248, 315),
      ip(264, 315),
      ip(296, 316),
      ip(324, 306),
      ip(336, 294),
      ip(344, 282),
      ip(350, 258),
      ip(352, 224),
      ip(352, 194),
    ]),
    _closedPolygonPath([
      ip(527, 176),
      ip(533, 184),
      ip(560, 204),
      ip(588, 236),
      ip(612, 282),
      ip(618, 315),
      ip(602, 308),
      ip(570, 308),
      ip(547, 301),
      ip(535, 290),
      ip(527, 282),
      ip(521, 258),
      ip(519, 224),
      ip(519, 194),
    ]),
  ];

  List<Path> _backDeltoidPaths(Offset Function(double x, double y) ip) => [
    // Same shoulder masks as the front figure, translated to the back figure
    // center so front/back shoulder highlights stay visually consistent.
    // Lower rear-deltoid coverage is trimmed upward by ~20%. Latest adjustment:
    // both rear deltoids are expanded about 15% toward the body center, with
    // the body-side lower corners softened so they do not end in sharp points.
    _closedPolygonPath([
      ip(1020, 176),
      ip(1010, 184),
      ip(972, 204),
      ip(944, 236),
      ip(920, 286),
      ip(914, 304),
      ip(930, 312),
      ip(962, 314),
      ip(994, 310),
      ip(1005, 303),
      ip(1012, 293),
      ip(1018, 282),
      ip(1022, 260),
      ip(1022, 224),
      ip(1022, 194),
    ]),
    _closedPolygonPath([
      ip(1184, 176),
      ip(1188, 184),
      ip(1226, 204),
      ip(1254, 236),
      ip(1278, 286),
      ip(1284, 304),
      ip(1268, 304),
      ip(1236, 304),
      ip(1204, 302),
      ip(1193, 296),
      ip(1189, 288),
      ip(1186, 282),
      ip(1182, 260),
      ip(1182, 224),
      ip(1182, 194),
    ]),
  ];

  List<Path> _frontBicepsPaths(Offset Function(double x, double y) ip) => [
    // Extracted from the user-provided red front-biceps mask. Biceps are
    // intentionally front-only; rear arm/triceps masks are unchanged.
    // Latest adjustment trims the top by ~20% and bottom by ~10%.
    _closedPolygonPath([
      ip(308, 310),
      ip(302, 310),
      ip(302, 310),
      ip(302, 310),
      ip(302, 316),
      ip(301, 323),
      ip(300, 329),
      ip(300, 336),
      ip(298, 342),
      ip(298, 349),
      ip(298, 356),
      ip(298, 362),
      ip(297, 369),
      ip(296, 376),
      ip(296, 383),
      ip(305, 385),
      ip(324, 385),
      ip(333, 385),
      ip(335, 385),
      ip(337, 383),
      ip(339, 376),
      ip(341, 369),
      ip(343, 362),
      ip(343, 356),
      ip(343, 349),
      ip(342, 342),
      ip(341, 336),
      ip(339, 329),
      ip(338, 323),
      ip(335, 316),
      ip(333, 310),
      ip(329, 310),
      ip(324, 310),
      ip(316, 310),
    ]),
    _closedPolygonPath([
      ip(559, 310),
      ip(565, 310),
      ip(565, 310),
      ip(565, 310),
      ip(565, 316),
      ip(567, 323),
      ip(567, 329),
      ip(569, 336),
      ip(569, 342),
      ip(569, 349),
      ip(570, 356),
      ip(570, 362),
      ip(571, 369),
      ip(572, 376),
      ip(571, 383),
      ip(562, 385),
      ip(544, 385),
      ip(535, 385),
      ip(532, 385),
      ip(530, 383),
      ip(528, 376),
      ip(526, 369),
      ip(524, 362),
      ip(524, 356),
      ip(524, 349),
      ip(525, 342),
      ip(526, 336),
      ip(528, 329),
      ip(530, 323),
      ip(532, 316),
      ip(534, 310),
      ip(538, 310),
      ip(544, 310),
      ip(550, 310),
    ]),
  ];

  List<Path> _backTricepsPaths(Offset Function(double x, double y) ip) => [
    // User-provided red triceps reference remapped from the marked 1080px
    // body image onto the app's rear silhouette bbox. The upper tips are
    // curved inward toward the torso for a more natural rear-triceps insertion.
    _smoothClosedPath([
      ip(991, 299),
      ip(1001, 302),
      ip(1008, 311),
      ip(1012, 324),
      ip(1015, 338),
      ip(1013, 355),
      ip(1009, 376),
      ip(1002, 397),
      ip(993, 416),
      ip(982, 421),
      ip(973, 418),
      ip(970, 407),
      ip(971, 390),
      ip(974, 372),
      ip(976, 352),
      ip(978, 333),
      ip(982, 315),
      ip(986, 300),
    ]),
    _smoothClosedPath([
      ip(1212, 299),
      ip(1202, 302),
      ip(1195, 311),
      ip(1191, 324),
      ip(1188, 338),
      ip(1190, 355),
      ip(1194, 376),
      ip(1200, 397),
      ip(1210, 416),
      ip(1221, 421),
      ip(1230, 418),
      ip(1233, 407),
      ip(1232, 390),
      ip(1228, 372),
      ip(1227, 352),
      ip(1225, 333),
      ip(1220, 315),
      ip(1216, 300),
    ]),
  ];

  List<Path> _frontThighPaths(Offset Function(double x, double y) ip) => [
    // User-provided red front-leg reference updated 2026-05-22: anterior
    // thigh / quadriceps only. Red mask bbox from the 1080x1456 marked image
    // was left=(454,745)-(574,1056), right=(612,745)-(726,1056), mapped from
    // the source body bbox (365,38)-(829,1425) onto the app front silhouette.
    // Latest adjustment: screen-left quadriceps moved about 3% outward;
    // screen-right quadriceps rotated about 3 degrees counter-clockwise around
    // its local center, using the user's front-view screen direction.
    _smoothClosedPath([
      ip(353, 522),
      ip(350, 539),
      ip(348, 555),
      ip(347, 572),
      ip(346, 588),
      ip(347, 605),
      ip(349, 621),
      ip(351, 638),
      ip(354, 654),
      ip(358, 671),
      ip(363, 687),
      ip(367, 704),
      ip(370, 720),
      ip(386, 728),
      ip(398, 728),
      ip(413, 720),
      ip(420, 704),
      ip(423, 687),
      ip(423, 671),
      ip(424, 654),
      ip(424, 638),
      ip(426, 621),
      ip(426, 605),
      ip(424, 588),
      ip(415, 572),
      ip(394, 555),
      ip(373, 539),
      ip(356, 522),
    ]),
    _smoothClosedPath([
      ip(506, 521),
      ip(490, 539),
      ip(471, 556),
      ip(454, 574),
      ip(446, 590),
      ip(444, 607),
      ip(445, 623),
      ip(446, 640),
      ip(446, 656),
      ip(447, 673),
      ip(448, 689),
      ip(451, 706),
      ip(460, 721),
      ip(476, 729),
      ip(487, 728),
      ip(503, 719),
      ip(505, 703),
      ip(508, 686),
      ip(512, 670),
      ip(514, 653),
      ip(517, 636),
      ip(519, 619),
      ip(520, 603),
      ip(519, 586),
      ip(518, 570),
      ip(517, 553),
      ip(514, 537),
      ip(509, 521),
    ]),
  ];

  List<Path> _backGlutePaths(Offset Function(double x, double y) ip) => [
    // Extracted from the user-provided rear glute red mask. Source PNG red
    // components: left bbox (468,668)-(593,848), right bbox (603,668)-(727,848)
    // in the 1080x1456 marked image; mapped from source body bbox
    // (365,38)-(829,1425) onto the app back silhouette bbox (944,56)-(1254,971).
    // Latest adjustment: moved the glute region down by about 15% of its
    // current height.
    _smoothClosedPath([
      ip(1013, 491),
      ip(1031, 485),
      ip(1062, 485),
      ip(1086, 496),
      ip(1098, 520),
      ip(1096, 555),
      ip(1084, 590),
      ip(1063, 609),
      ip(1032, 605),
      ip(1014, 579),
      ip(1007, 542),
      ip(1008, 512),
    ]),
    _smoothClosedPath([
      ip(1101, 520),
      ip(1113, 496),
      ip(1137, 485),
      ip(1168, 485),
      ip(1186, 491),
      ip(1191, 512),
      ip(1192, 542),
      ip(1185, 579),
      ip(1167, 605),
      ip(1136, 609),
      ip(1115, 590),
      ip(1103, 555),
    ]),
  ];

  List<Path> _backHamstringPaths(Offset Function(double x, double y) ip) => [
    // Hamstring vertical range reduced by 15% from the top and 15% from the
    // bottom, preserving each side's horizontal outline. Latest adjustment:
    // moved the reduced hamstring region up by about 10% of its current height.
    _smoothClosedPath([
      ip(1020, 637),
      ip(1088, 630),
      ip(1086, 718),
      ip(1070, 752),
      ip(1022, 752),
      ip(1000, 692),
    ]),
    _smoothClosedPath([
      ip(1110, 630),
      ip(1178, 637),
      ip(1196, 692),
      ip(1174, 752),
      ip(1126, 752),
      ip(1110, 718),
    ]),
  ];

  List<Path> _backCalfPaths(Offset Function(double x, double y) ip) => [
    // Calf lower edge reduced by 15%, keeping the top anchor aligned with the
    // hamstring/knee boundary and preserving each side's horizontal outline.
    // Latest adjustment: screen-right calf rotated 10 degrees clockwise around
    // its local center using the user's screen direction.
    _smoothClosedPath([
      ip(1022, 790),
      ip(1070, 790),
      ip(1074, 877),
      ip(1058, 900),
      ip(1020, 897),
      ip(1004, 838),
    ]),
    _smoothClosedPath([
      ip(1121, 790),
      ip(1168, 791),
      ip(1186, 838),
      ip(1169, 897),
      ip(1131, 900),
      ip(1117, 877),
    ]),
  ];

  Map<_BodyRegion, int> _regionCounts(Map<String, int> bodyPartCounts) {
    final regionCounts = <_BodyRegion, int>{};
    final hasArmDetailCounts =
        (bodyPartCounts[_bodyPartCountArmBicepsKey] ?? 0) > 0 ||
        (bodyPartCounts[_bodyPartCountArmTricepsKey] ?? 0) > 0;
    for (final entry in bodyPartCounts.entries) {
      final normalizedKey = _normalizeBodyPartName(entry.key);
      if (normalizedKey == '팔' && hasArmDetailCounts) {
        continue;
      }
      final regions = _bodyPartRegionMap[normalizedKey];
      if (regions == null || entry.value <= 0) {
        continue;
      }
      for (final region in regions) {
        regionCounts[region] = math.max(regionCounts[region] ?? 0, entry.value);
      }
    }
    return regionCounts;
  }

  Rect _containedRect(Size source, Size destination) {
    final fitted = applyBoxFit(BoxFit.contain, source, destination);
    return Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & destination,
    );
  }

  Path _closedPolygonPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    return path..close();
  }

  Path _smoothClosedPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length; i += 1) {
      final current = points[i];
      final next = points[(i + 1) % points.length];
      final mid = Offset(
        (current.dx + next.dx) / 2,
        (current.dy + next.dy) / 2,
      );
      path.quadraticBezierTo(current.dx, current.dy, mid.dx, mid.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(covariant _BodyMapPainter oldDelegate) =>
      oldDelegate.counts != counts ||
      oldDelegate.silhouetteMaskImage != silhouetteMaskImage;
}

class _BodyPartStatusGrid extends StatelessWidget {
  const _BodyPartStatusGrid({required this.counts});

  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final childAspectRatio = constraints.maxWidth < 300
            ? 1.55
            : constraints.maxWidth < 360
            ? 1.8
            : 2.15;

        return GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: childAspectRatio,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final part in _trackedBodyParts)
              _BodyPartStatusChip(part: part, count: counts[part] ?? 0),
          ],
        );
      },
    );
  }
}

class _BodyPartStatusChip extends StatelessWidget {
  const _BodyPartStatusChip({required this.part, required this.count});

  final String part;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = _bodyPartStatusColor(count);
    final foreground = count == 1 ? const Color(0xFF713F12) : Colors.white;
    final isRest = count == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isRest ? const Color(0xFFD1D5DB) : color),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            part,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: isRest ? const Color(0xFF6B7280) : foreground,
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            count >= 3 ? '3회+ 주의' : '$count회',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: isRest
                  ? const Color(0xFF9CA3AF)
                  : foreground.withValues(alpha: 0.90),
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _BodyPartLegendDot extends StatelessWidget {
  const _BodyPartLegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFD1D5DB)),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.78),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
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

class _MonthlyBodyPartCalendarSheet extends StatelessWidget {
  const _MonthlyBodyPartCalendarSheet({required this.records});

  final List<WorkoutRecord> records;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bodyPartsByDate = _bodyPartsByDate(records);
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final firstDay = currentMonth;
    final firstGridDay = firstDay.subtract(
      Duration(days: firstDay.weekday - DateTime.monday),
    );
    final today = now;

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.9,
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                DateFormat('yyyy년 M월').format(currentMonth),
                key: const ValueKey('monthly-calendar-title'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
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
                    final isCurrentMonth =
                        date.year == currentMonth.year &&
                        date.month == currentMonth.month;
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
  void initState() {
    super.initState();
    _scheduleFocusedDateScroll();
  }

  @override
  void didUpdateWidget(covariant _WorkoutRecordList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusRequestId != oldWidget.focusRequestId ||
        widget.focusedDate != oldWidget.focusedDate) {
      _scheduleFocusedDateScroll();
    }
  }

  void _scheduleFocusedDateScroll() {
    final focusedDate = widget.focusedDate;
    if (focusedDate == null) {
      return;
    }
    final focusedDateKey = _dateKey(focusedDate);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
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
              ),
              _RecordEntryItem() => _WorkoutRecordCard(
                item: item,
                bodyWeightKg: widget.bodyWeightKg,
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
  });

  final _RecordDateSummaryItem item;
  final double bodyWeightKg;

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
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFFEFF6FF),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primary.withValues(alpha: 0.10),
              const Color(0xFFF8FBFF),
            ],
          ),
        ),
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
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.bolt_rounded,
                    color: colorScheme.onPrimary,
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
                      color: colorScheme.primary,
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
                    value: '${formatMetricNumber(item.totalVolume)}kg',
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
              '예상 ${estimatedCalories.round()}kcal',
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
    required this.onTap,
    required this.onDelete,
  });

  final _RecordEntryItem item;
  final double bodyWeightKg;
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
                      value: '${formatMetricNumber(totalVolume)}kg',
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
                  _RecordChip(
                    label: _normalizeBodyPartName(entry.bodyPart.name),
                  ),
                  if (warmupSetCount > 0)
                    _RecordChip(label: '워밍업 $warmupSetCount세트'),
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
      final bodyPartName = _normalizeBodyPartName(entry.bodyPart.name);
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
      final bodyPartName = _normalizeBodyPartName(entry.bodyPart.name);
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
      final bodyPartName = _normalizeBodyPartName(entry.bodyPart.name);
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
