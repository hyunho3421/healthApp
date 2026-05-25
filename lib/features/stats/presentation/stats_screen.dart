import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/formatters/metric_number_formatter.dart';
import '../../exercise/providers/exercise_providers.dart';
import '../models/exercise_stats_period.dart';
import '../models/favorite_exercise_stats.dart';
import '../models/monthly_exercise_stats.dart';
import '../models/stats_chart_axis.dart';
import '../providers/stats_providers.dart';

const _maxWeightGraphColor = Color(0xFFEF4444);
const _maxWeightTooltipColor = Color(0xFFFCA5A5);

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  late Future<List<BodyPart>> _bodyPartsFuture;
  Future<List<ExercisePeriodStats>> _statsFuture = Future.value(
    const <ExercisePeriodStats>[],
  );
  late Future<List<FavoriteExerciseSummary>> _favoriteStatsFuture;
  StatsPeriodUnit _selectedPeriodUnit = StatsPeriodUnit.weekly;
  FavoriteExerciseSummary? _selectedFavoriteExercise;

  @override
  void initState() {
    super.initState();
    _bodyPartsFuture = ref.read(exerciseServiceProvider).getBodyParts();
    _favoriteStatsFuture = _loadFavoriteStatsAndSelectDefault();
  }

  Future<List<FavoriteExerciseSummary>> _loadFavoriteStats() {
    return ref
        .read(statsServiceProvider)
        .getFavoriteExerciseSummaries(periodUnit: _selectedPeriodUnit);
  }

  Future<List<FavoriteExerciseSummary>>
  _loadFavoriteStatsAndSelectDefault() async {
    final favorites = await _loadFavoriteStats();
    if (!mounted || favorites.isEmpty) {
      return favorites;
    }

    final selected = _selectedFavoriteExercise;
    final selectedStillExists =
        selected != null &&
        favorites.any((summary) => summary.exercise.id == selected.exercise.id);
    if (selectedStillExists) {
      return favorites;
    }

    final firstFavorite = favorites.first;
    setState(() {
      _selectedFavoriteExercise = firstFavorite;
      _refreshSelectedStatsFuture();
    });
    return favorites;
  }

  void _refreshFavoriteStatsFuture() {
    _favoriteStatsFuture = _loadFavoriteStatsAndSelectDefault();
  }

  void _refreshSelectedStatsFuture() {
    final selected = _selectedFavoriteExercise;
    _statsFuture = selected == null
        ? Future.value(const <ExercisePeriodStats>[])
        : ref
              .read(statsServiceProvider)
              .getExerciseStats(
                exerciseId: selected.exercise.id,
                periodUnit: _selectedPeriodUnit,
                recentCount: switch (_selectedPeriodUnit) {
                  StatsPeriodUnit.daily => dailyRecentSevenPeriodCount,
                  StatsPeriodUnit.weekly => weeklyRecentFivePeriodCount,
                  StatsPeriodUnit.monthly => monthlyMaximumPeriodCount,
                },
              );
  }

  void _selectPeriodUnit(StatsPeriodUnit periodUnit) {
    setState(() {
      _selectedPeriodUnit = periodUnit;
      _refreshSelectedStatsFuture();
      _refreshFavoriteStatsFuture();
    });
  }

  Future<void> _showAddFavoriteExerciseSheet() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _AddFavoriteExerciseSheet(
        exercisesFuture: ref.read(exerciseServiceProvider).getExercises(),
        bodyPartsFuture: _bodyPartsFuture,
        favoriteStatsFuture: _favoriteStatsFuture,
        onAdd: ref.read(statsServiceProvider).addFavoriteExercise,
      ),
    );
    if (!mounted || added != true) {
      return;
    }
    setState(_refreshFavoriteStatsFuture);
  }

  Future<void> _removeFavoriteExercise(int exerciseId) async {
    await ref.read(statsServiceProvider).removeFavoriteExercise(exerciseId);
    if (!mounted) {
      return;
    }
    setState(() {
      if (_selectedFavoriteExercise?.exercise.id == exerciseId) {
        _selectedFavoriteExercise = null;
        _refreshSelectedStatsFuture();
      }
      _refreshFavoriteStatsFuture();
    });
  }

  void _selectFavoriteExercise(FavoriteExerciseSummary summary) {
    setState(() {
      _selectedFavoriteExercise = summary;
      _refreshSelectedStatsFuture();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('운동 통계')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _StatsHero(),
            const SizedBox(height: 14),
            _FavoriteExercisesSection(
              future: _favoriteStatsFuture,
              periodUnit: _selectedPeriodUnit,
              onAdd: _showAddFavoriteExerciseSheet,
              selectedExerciseId: _selectedFavoriteExercise?.exercise.id,
              onSelect: _selectFavoriteExercise,
              onRemove: _removeFavoriteExercise,
            ),
            if (_selectedFavoriteExercise != null) ...[
              const SizedBox(height: 20),
              _StatsPeriodSelector(
                selectedPeriodUnit: _selectedPeriodUnit,
                onChanged: _selectPeriodUnit,
              ),
              const SizedBox(height: 16),
              _StatsContent(
                future: _statsFuture,
                periodUnit: _selectedPeriodUnit,
                title: '${_selectedFavoriteExercise!.exercise.name} 통계',
                description:
                    '${_selectedPeriodUnit.emptyRangeLabel} 기준 ${_selectedFavoriteExercise!.bodyPart.name} · ${_selectedFavoriteExercise!.exercise.name} 기록입니다.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FavoriteExercisesSection extends StatelessWidget {
  const _FavoriteExercisesSection({
    required this.future,
    required this.periodUnit,
    required this.onAdd,
    required this.selectedExerciseId,
    required this.onSelect,
    required this.onRemove,
  });

  final Future<List<FavoriteExerciseSummary>> future;
  final StatsPeriodUnit periodUnit;
  final int? selectedExerciseId;
  final VoidCallback onAdd;
  final ValueChanged<FavoriteExerciseSummary> onSelect;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FavoriteExerciseSummary>>(
      future: future,
      builder: (context, snapshot) {
        final favorites = snapshot.data ?? const <FavoriteExerciseSummary>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '관심 운동',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('운동 추가'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (snapshot.connectionState != ConnectionState.done)
              const SizedBox(
                height: 128,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snapshot.hasError)
              Text('관심 운동을 불러오지 못했습니다: ${snapshot.error}')
            else if (favorites.isEmpty)
              _FavoriteExerciseEmptyCard(onAdd: onAdd)
            else
              SizedBox(
                height: 184,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: favorites.length + 1,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    if (index == favorites.length) {
                      return _AddFavoriteExerciseCard(onAdd: onAdd);
                    }
                    final favorite = favorites[index];
                    return _FavoriteExerciseCard(
                      summary: favorite,
                      periodUnit: periodUnit,
                      isSelected: selectedExerciseId == favorite.exercise.id,
                      onSelect: () => onSelect(favorite),
                      onRemove: () => onRemove(favorite.exercise.id),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StatsHero extends StatelessWidget {
  const _StatsHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '기간별 운동 통계',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '관심 운동을 고정하고 성장 추이를 한눈에 확인하세요.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.bar_chart_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _FavoriteExerciseEmptyCard extends StatelessWidget {
  const _FavoriteExerciseEmptyCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Text('통계로 볼 운동을 추가해 보세요'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('관심운동 추가'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddFavoriteExerciseCard extends StatelessWidget {
  const _AddFavoriteExerciseCard({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: OutlinedButton(
        onPressed: onAdd,
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          side: const BorderSide(color: Color(0xFFE1E8F2)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded),
            SizedBox(height: 8),
            Text('관심운동\n추가', textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _FavoriteExerciseCard extends StatelessWidget {
  const _FavoriteExerciseCard({
    required this.summary,
    required this.periodUnit,
    required this.isSelected,
    required this.onSelect,
    required this.onRemove,
  });

  final FavoriteExerciseSummary summary;
  final StatsPeriodUnit periodUnit;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final stats = summary.stats;
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      key: ValueKey('favorite-exercise-card-${summary.exercise.id}'),
      width: 236,
      child: Card(
        elevation: 0,
        color: isSelected ? const Color(0xFFE8F2FF) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onSelect,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        summary.exercise.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (isSelected)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Icon(
                          Icons.check_circle_rounded,
                          color: colorScheme.primary,
                          size: 20,
                        ),
                      ),
                    IconButton(
                      tooltip: '관심 운동 삭제',
                      visualDensity: VisualDensity.compact,
                      onPressed: onRemove,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Text(
                  '${summary.bodyPart.name} · ${periodUnit.emptyRangeLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                if (!stats.hasRecords)
                  const Text('기록 없음')
                else ...[
                  Text(
                    '최고 ${formatMetricNumber(stats.maxWeight)}kg × ${stats.maxWeightReps}회',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text('총 볼륨 ${formatMetricNumber(stats.totalVolume)}kg'),
                  Text('운동일 ${stats.workoutDayCount}일'),
                  Text(
                    '최근 ${DateFormat('M/d').format(stats.lastWorkoutDate!)}',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddFavoriteExerciseSheet extends StatefulWidget {
  const _AddFavoriteExerciseSheet({
    required this.exercisesFuture,
    required this.bodyPartsFuture,
    required this.favoriteStatsFuture,
    required this.onAdd,
  });

  final Future<List<Exercise>> exercisesFuture;
  final Future<List<BodyPart>> bodyPartsFuture;
  final Future<List<FavoriteExerciseSummary>> favoriteStatsFuture;
  final Future<int> Function(int exerciseId) onAdd;

  @override
  State<_AddFavoriteExerciseSheet> createState() =>
      _AddFavoriteExerciseSheetState();
}

class _AddFavoriteExerciseSheetState extends State<_AddFavoriteExerciseSheet> {
  late final Future<List<Object>> _sheetDataFuture;
  String _query = '';
  int? _addingExerciseId;

  @override
  void initState() {
    super.initState();
    _sheetDataFuture = Future.wait([
      widget.exercisesFuture,
      widget.bodyPartsFuture,
      widget.favoriteStatsFuture,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.78,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        builder: (context, scrollController) {
          return FutureBuilder<List<Object>>(
            future: _sheetDataFuture,
            builder: (context, snapshot) {
              final loaded = snapshot.data;
              final exercises = loaded == null
                  ? const <Exercise>[]
                  : loaded[0] as List<Exercise>;
              final bodyParts = loaded == null
                  ? const <BodyPart>[]
                  : loaded[1] as List<BodyPart>;
              final favorites = loaded == null
                  ? const <FavoriteExerciseSummary>[]
                  : loaded[2] as List<FavoriteExerciseSummary>;
              final bodyPartById = {
                for (final bodyPart in bodyParts) bodyPart.id: bodyPart,
              };
              final favoriteExerciseIds = {
                for (final favorite in favorites) favorite.exercise.id,
              };
              final normalizedQuery = _query.trim().toLowerCase();
              final filteredExercises = normalizedQuery.isEmpty
                  ? exercises
                  : exercises.where((exercise) {
                      final bodyPartName = bodyPartById[exercise.bodyPartId]
                          ?.name
                          .toLowerCase();
                      return exercise.name.toLowerCase().contains(
                            normalizedQuery,
                          ) ||
                          (bodyPartName?.contains(normalizedQuery) ?? false);
                    }).toList();

              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '관심 운동 추가',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '검색해서 통계 카드에 고정할 운동을 선택하세요.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.72),
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: const InputDecoration(
                      hintText: '운동 또는 부위 검색',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                  const SizedBox(height: 12),
                  if (snapshot.connectionState != ConnectionState.done)
                    const Padding(
                      padding: EdgeInsets.only(top: 32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (snapshot.hasError)
                    Text('운동 목록을 불러오지 못했습니다: ${snapshot.error}')
                  else if (filteredExercises.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 32),
                      child: Center(child: Text('검색 결과가 없습니다.')),
                    )
                  else
                    for (final exercise in filteredExercises)
                      _AddFavoriteExerciseTile(
                        exercise: exercise,
                        bodyPartName:
                            bodyPartById[exercise.bodyPartId]?.name ?? '부위 없음',
                        isFavorite: favoriteExerciseIds.contains(exercise.id),
                        isAdding: _addingExerciseId == exercise.id,
                        onAdd: () => _addExercise(exercise.id),
                      ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _addExercise(int exerciseId) async {
    setState(() => _addingExerciseId = exerciseId);
    try {
      await widget.onAdd(exerciseId);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() => _addingExerciseId = null);
      }
    }
  }
}

class _AddFavoriteExerciseTile extends StatelessWidget {
  const _AddFavoriteExerciseTile({
    required this.exercise,
    required this.bodyPartName,
    required this.isFavorite,
    required this.isAdding,
    required this.onAdd,
  });

  final Exercise exercise;
  final String bodyPartName;
  final bool isFavorite;
  final bool isAdding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8EEF6)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F2FF),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.fitness_center_rounded),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(bodyPartName),
                  ],
                ),
              ),
              if (isFavorite)
                const Chip(label: Text('추가됨'))
              else
                SizedBox(
                  width: 74,
                  child: FilledButton(
                    onPressed: isAdding ? null : onAdd,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: EdgeInsets.zero,
                    ),
                    child: isAdding
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('추가'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsPeriodSelector extends StatelessWidget {
  const _StatsPeriodSelector({
    required this.selectedPeriodUnit,
    required this.onChanged,
  });

  final StatsPeriodUnit selectedPeriodUnit;
  final ValueChanged<StatsPeriodUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<StatsPeriodUnit>(
      segments: [
        for (final unit in StatsPeriodUnit.values)
          ButtonSegment<StatsPeriodUnit>(value: unit, label: Text(unit.label)),
      ],
      selected: {selectedPeriodUnit},
      onSelectionChanged: (selection) => onChanged(selection.single),
    );
  }
}

class _StatsContent extends StatelessWidget {
  const _StatsContent({
    required this.future,
    required this.periodUnit,
    required this.title,
    required this.description,
  });

  final Future<List<ExercisePeriodStats>> future;
  final StatsPeriodUnit periodUnit;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ExercisePeriodStats>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text('통계를 불러오지 못했습니다: ${snapshot.error}'),
          );
        }
        final stats = snapshot.data ?? const <ExercisePeriodStats>[];
        if (stats.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(description),
              _StatsEmptyState(
                message:
                    '아직 운동 기록이 없습니다.\n운동 기록을 추가하면 ${periodUnit.emptyRangeLabel} 통계가 표시됩니다.',
              ),
            ],
          );
        }

        final latest = stats.last;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(description),
            const SizedBox(height: 8),
            Text(
              '${_formatPeriodTitle(latest)} 기준',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            _StatsSummaryGrid(latest: latest, periodUnit: periodUnit),
            const SizedBox(height: 24),
            _WeightTrendSection(stats: stats, periodUnit: periodUnit),
          ],
        );
      },
    );
  }
}

class _StatsSummaryGrid extends StatelessWidget {
  const _StatsSummaryGrid({required this.latest, required this.periodUnit});

  final ExercisePeriodStats latest;
  final StatsPeriodUnit periodUnit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final secondaryCards = [
          _SecondaryMetricCard(
            icon: Icons.monitor_weight_outlined,
            label: '${periodUnit.metricPrefix} 평균 중량',
            value: '${formatMetricNumber(latest.averageWeight)}kg',
            accentColor: Theme.of(context).colorScheme.secondary,
          ),
          _SecondaryMetricCard(
            icon: Icons.inventory_2_outlined,
            label: '${periodUnit.metricPrefix} 총 볼륨',
            value: '${formatMetricNumber(latest.totalVolume)}kg',
            accentColor: Theme.of(context).colorScheme.tertiary,
          ),
          _SecondaryMetricCard(
            icon: _trendIcon(latest.previousTotalVolumeDiff),
            label: '${periodUnit.previousLabel} 대비 총 볼륨',
            value: _formatDiff(latest.previousTotalVolumeDiff),
            caption: _formatTrendCaption(latest.previousTotalVolumeRate),
            accentColor: _trendColor(context, latest.previousTotalVolumeDiff),
          ),
        ];

        if (constraints.maxWidth < 340) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeroMetricCard(latest: latest, periodUnit: periodUnit),
              const SizedBox(height: 10),
              for (final card in secondaryCards) ...[
                card,
                const SizedBox(height: 8),
              ],
            ],
          );
        }

        final halfWidth = (constraints.maxWidth - 10) / 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeroMetricCard(latest: latest, periodUnit: periodUnit),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(width: halfWidth, child: secondaryCards[0]),
                SizedBox(width: halfWidth, child: secondaryCards[1]),
                SizedBox(width: constraints.maxWidth, child: secondaryCards[2]),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _HeroMetricCard extends StatelessWidget {
  const _HeroMetricCard({required this.latest, required this.periodUnit});

  final ExercisePeriodStats latest;
  final StatsPeriodUnit periodUnit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final maxDiffText = _formatTrendSummary(
      diff: latest.previousMaxWeightDiff,
      rate: latest.previousMaxWeightRate,
      previousLabel: periodUnit.previousLabel,
    );

    return Card(
      elevation: 0,
      color: colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.primaryContainer,
              colorScheme.secondaryContainer,
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.emoji_events_outlined,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${periodUnit.metricPrefix} 최고 중량',
                        style: textTheme.titleMedium?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '가장 중요한 성장 지표',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: formatMetricNumber(latest.maxWeight)),
                    TextSpan(
                      text: 'kg',
                      style: textTheme.titleLarge?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                style: textTheme.displaySmall?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(height: 12),
            _MetricPill(
              icon: _trendIcon(latest.previousMaxWeightDiff),
              text: maxDiffText,
              color: _trendColor(context, latest.previousMaxWeightDiff),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecondaryMetricCard extends StatelessWidget {
  const _SecondaryMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
    this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: accentColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleLarge?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 2),
              Text(
                caption!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: accentColor),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeightTrendSection extends StatelessWidget {
  const _WeightTrendSection({required this.stats, required this.periodUnit});

  final List<ExercisePeriodStats> stats;
  final StatsPeriodUnit periodUnit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${periodUnit.emptyRangeLabel} 중량 그래프',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '최고중량과 평균중량을 함께 비교하세요',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _ChartLegendItem(color: _maxWeightGraphColor, label: '최고중량'),
                _ChartLegendItem(color: colorScheme.secondary, label: '평균중량'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 260,
              child: _PeriodWeightLineChart(
                stats: stats,
                periodUnit: periodUnit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartLegendItem extends StatelessWidget {
  const _ChartLegendItem({required this.color, required this.label});

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
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PeriodWeightLineChart extends StatelessWidget {
  const _PeriodWeightLineChart({required this.stats, required this.periodUnit});

  final List<ExercisePeriodStats> stats;
  final StatsPeriodUnit periodUnit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxY = stats.fold<double>(0, (max, stat) {
      final periodMax = math.max(stat.maxWeight, stat.averageWeight);
      return periodMax > max ? periodMax : max;
    });
    final safeMaxY = maxY <= 0 ? 1.0 : maxY * 1.2;
    final chartWindow = buildWeightTrendAxisWindow(
      periodUnit: periodUnit,
      stats: stats,
      today: DateTime.now(),
    );
    final chartOrigin = chartWindow.origin;
    final maxWeightSpots = <FlSpot>[
      for (var index = 0; index < stats.length; index++)
        if (_isStatInChartDomain(
          periodOffsetFrom(chartOrigin, stats[index].periodStart, periodUnit),
          chartWindow,
        ))
          FlSpot(
            periodOffsetFrom(chartOrigin, stats[index].periodStart, periodUnit),
            stats[index].maxWeight,
          ),
    ];
    final averageWeightSpots = <FlSpot>[
      for (var index = 0; index < stats.length; index++)
        if (_isStatInChartDomain(
          periodOffsetFrom(chartOrigin, stats[index].periodStart, periodUnit),
          chartWindow,
        ))
          FlSpot(
            periodOffsetFrom(chartOrigin, stats[index].periodStart, periodUnit),
            stats[index].averageWeight,
          ),
    ];

    return LineChart(
      LineChartData(
        minX: chartWindow.paddedMinX,
        maxX: chartWindow.paddedMaxX,
        minY: 0,
        maxY: safeMaxY,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => colorScheme.inverseSurface,
            tooltipBorderRadius: BorderRadius.circular(12),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            tooltipMargin: 10,
            tooltipBorder: BorderSide(
              color: colorScheme.outline.withValues(alpha: 0.28),
            ),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            maxContentWidth: 170,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  '${spot.barIndex == 0 ? '최고' : '평균'} ${formatMetricNumber(spot.y)}kg',
                  TextStyle(
                    color: spot.barIndex == 0
                        ? _maxWeightTooltipColor
                        : colorScheme.secondaryContainer,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (value, meta) => Text(
                formatMetricNumber(value),
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 32,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final tickDate = axisTickDateAt(chartWindow, value);
                if (tickDate == null) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _formatChartDateLabel(tickDate, periodUnit),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          _weightLine(
            spots: maxWeightSpots,
            color: _maxWeightGraphColor,
            showArea: true,
          ),
          _weightLine(spots: averageWeightSpots, color: colorScheme.secondary),
        ],
      ),
    );
  }

  bool _isStatInChartDomain(double offset, WeightTrendAxisWindow chartWindow) {
    return chartWindow.containsOffset(offset);
  }

  LineChartBarData _weightLine({
    required List<FlSpot> spots,
    required Color color,
    bool showArea = false,
  }) {
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      preventCurveOverShooting: true,
      barWidth: 3,
      color: color,
      isStrokeCapRound: true,
      isStrokeJoinRound: true,
      dotData: FlDotData(show: stats.length <= 12),
      belowBarData: BarAreaData(
        show: showArea,
        color: color.withValues(alpha: 0.10),
      ),
    );
  }
}

class _StatsEmptyState extends StatelessWidget {
  const _StatsEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: Center(child: Text(message, textAlign: TextAlign.center)),
    );
  }
}

String _formatPeriodTitle(ExercisePeriodStats stat) {
  return switch (stat.periodUnit) {
    StatsPeriodUnit.daily => DateFormat('yyyy년 M월 d일').format(stat.periodStart),
    StatsPeriodUnit.weekly =>
      '${DateFormat('yyyy년 M월 d일').format(stat.periodStart)} 주',
    StatsPeriodUnit.monthly => DateFormat('yyyy년 M월').format(stat.periodStart),
  };
}

String _formatChartDateLabel(DateTime periodStart, StatsPeriodUnit periodUnit) {
  return switch (periodUnit) {
    StatsPeriodUnit.daily => DateFormat('M/d').format(periodStart),
    StatsPeriodUnit.weekly => '${periodStart.month}/${periodStart.day}',
    StatsPeriodUnit.monthly => DateFormat('M월').format(periodStart),
  };
}

IconData _trendIcon(double? value) {
  if (value == null || value == 0) {
    return Icons.remove_rounded;
  }
  return value > 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded;
}

Color _trendColor(BuildContext context, double? value) {
  final colorScheme = Theme.of(context).colorScheme;
  if (value == null || value == 0) {
    return colorScheme.onSurfaceVariant;
  }
  return value > 0 ? colorScheme.primary : colorScheme.error;
}

String _formatTrendSummary({
  required double? diff,
  required double? rate,
  required String previousLabel,
}) {
  if (diff == null) {
    return '$previousLabel 기록이 없어요';
  }
  final direction = diff > 0
      ? '증가'
      : diff < 0
      ? '감소'
      : '변화 없음';
  final rateText = rate == null ? '' : ' (${_formatRate(rate)})';
  return '$previousLabel 대비 ${_formatDiff(diff)} $direction$rateText';
}

String? _formatTrendCaption(double? value) {
  if (value == null) {
    return null;
  }
  final direction = value > 0
      ? '증가'
      : value < 0
      ? '감소'
      : '변화 없음';
  return '${_formatRate(value)} $direction';
}

String _formatDiff(double? value) {
  if (value == null) {
    return '비교 없음';
  }
  final sign = value > 0 ? '+' : '';
  return '$sign${formatMetricNumber(value)}kg';
}

String? _formatRate(double? value) {
  if (value == null) {
    return null;
  }
  final sign = value > 0 ? '+' : '';
  return '$sign${formatMetricNumber(value)}%';
}
