import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/seed/workout_seed_data.dart';
import '../../../core/models/exercise_type.dart';
import '../../../core/widgets/centered_toast.dart';
import '../../exercise/providers/exercise_providers.dart';
import '../models/workout_draft.dart';
import '../models/workout_record.dart';
import '../providers/workout_providers.dart';

class _AddedExerciseResult {
  const _AddedExerciseResult({
    required this.bodyPartId,
    required this.exerciseId,
  });

  final int bodyPartId;
  final int exerciseId;
}

class _AddExerciseDialog extends ConsumerStatefulWidget {
  const _AddExerciseDialog({this.exercise, this.referencedEntryCount = 0});

  final Exercise? exercise;
  final int referencedEntryCount;

  bool get isEditing => exercise != null;

  @override
  ConsumerState<_AddExerciseDialog> createState() => _AddExerciseDialogState();
}

class _AddExerciseDialogState extends ConsumerState<_AddExerciseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  late Future<List<BodyPart>> _bodyPartsFuture;
  int? _selectedBodyPartId;
  String _selectedExerciseTypeId = defaultExerciseTypeId;
  String? _selectedArmDetail;
  String? _errorText;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _bodyPartsFuture = ref.read(exerciseServiceProvider).getBodyParts();
    final exercise = widget.exercise;
    if (exercise != null) {
      _selectedBodyPartId = exercise.bodyPartId;
      _selectedExerciseTypeId = exercise.type;
      _selectedArmDetail = exercise.armDetail;
      _nameController.text = exercise.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _errorText = null);
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final bodyPartId = _selectedBodyPartId;
    if (bodyPartId == null) {
      setState(() => _errorText = '부위를 선택해 주세요.');
      return;
    }
    final isArm = await _isArmBodyPart(bodyPartId);
    if (isArm && _selectedArmDetail == null) {
      setState(() => _errorText = '팔 운동은 이두/삼두를 선택해 주세요.');
      return;
    }
    final armDetail = isArm ? _selectedArmDetail : null;

    setState(() => _isSaving = true);
    try {
      final exercise = widget.exercise;
      final int exerciseId;
      if (exercise == null) {
        exerciseId = await ref
            .read(exerciseServiceProvider)
            .addCustomExercise(
              bodyPartId: bodyPartId,
              name: _nameController.text,
              type: _selectedExerciseTypeId,
              armDetail: armDetail,
            );
      } else {
        await ref
            .read(exerciseServiceProvider)
            .updateCustomExercise(
              id: exercise.id,
              bodyPartId: bodyPartId,
              name: _nameController.text,
              type: _selectedExerciseTypeId,
              armDetail: armDetail,
            );
        exerciseId = exercise.id;
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(
        _AddedExerciseResult(bodyPartId: bodyPartId, exerciseId: exerciseId),
      );
    } on StateError catch (error) {
      if (mounted) {
        final message = error.message.toString();
        setState(
          () => _errorText = message.isEmpty ? '이미 등록된 운동입니다.' : message,
        );
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(
          () => _errorText = error.message?.toString() ?? '입력값을 확인해 주세요.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _errorText = widget.isEditing
              ? '운동 수정에 실패했습니다: $error'
              : '운동 등록에 실패했습니다: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<bool> _isArmBodyPart(int bodyPartId) async {
    final bodyParts = await _bodyPartsFuture;
    return bodyParts.any(
      (bodyPart) => bodyPart.id == bodyPartId && bodyPart.name == '팔',
    );
  }

  void _selectDialogBodyPart(int? bodyPartId, List<BodyPart> bodyParts) {
    final isArm = bodyParts.any(
      (bodyPart) => bodyPart.id == bodyPartId && bodyPart.name == '팔',
    );
    setState(() {
      _selectedBodyPartId = bodyPartId;
      if (!isArm) {
        _selectedArmDetail = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      title: Row(
        children: [
          Expanded(child: Text(widget.isEditing ? '운동 수정' : '운동 등록')),
          IconButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            tooltip: '닫기',
          ),
        ],
      ),
      scrollable: true,
      actionsAlignment: MainAxisAlignment.end,
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FutureBuilder<List<BodyPart>>(
              future: _bodyPartsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Text('부위를 불러오지 못했습니다: ${snapshot.error}');
                }
                final bodyParts = snapshot.data ?? const <BodyPart>[];
                final isArmSelected = bodyParts.any(
                  (bodyPart) =>
                      bodyPart.id == _selectedBodyPartId &&
                      bodyPart.name == '팔',
                );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _PickerField<int>(
                      label: '부위',
                      placeholder: '운동 부위 선택',
                      value: _selectedBodyPartId,
                      enabled: !_isSaving,
                      options: [
                        for (final bodyPart in bodyParts)
                          _PickerOption(
                            value: bodyPart.id,
                            label: _displayBodyPartName(bodyPart.name),
                          ),
                      ],
                      onChanged: (value) =>
                          _selectDialogBodyPart(value, bodyParts),
                      validator: (value) =>
                          value == null ? '부위를 선택해 주세요.' : null,
                    ),
                    if (isArmSelected) ...[
                      const SizedBox(height: 12),
                      _ArmDetailSelector(
                        value: _selectedArmDetail,
                        enabled: !_isSaving,
                        onChanged: (value) =>
                            setState(() => _selectedArmDetail = value),
                      ),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameController,
              enabled: !_isSaving,
              decoration: const InputDecoration(
                labelText: '운동명',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              onFieldSubmitted: (_) => _isSaving ? null : _save(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '운동명을 입력해 주세요.';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            Text('운동 유형', style: Theme.of(context).textTheme.labelLarge),
            if (widget.isEditing && widget.referencedEntryCount > 0) ...[
              const SizedBox(height: 4),
              Text(
                '기록 ${widget.referencedEntryCount}개에서 사용 중이라 운동 유형은 유지됩니다.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final exerciseType in exerciseTypes)
                  ChoiceChip(
                    label: Text(exerciseType.label),
                    selected: _selectedExerciseTypeId == exerciseType.id,
                    showCheckmark: false,
                    selectedColor: const Color(0xFFE8F2FF),
                    side: BorderSide(
                      color: _selectedExerciseTypeId == exerciseType.id
                          ? const Color(0xFF3182F6)
                          : const Color(0xFFE1E8F2),
                    ),
                    onSelected:
                        _isSaving ||
                            (widget.isEditing &&
                                widget.referencedEntryCount > 0)
                        ? null
                        : (selected) {
                            if (selected) {
                              setState(
                                () => _selectedExerciseTypeId = exerciseType.id,
                              );
                            }
                          },
                  ),
              ],
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.isEditing ? '수정' : '등록'),
        ),
      ],
    );
  }
}

class AddWorkoutScreen extends ConsumerStatefulWidget {
  const AddWorkoutScreen({super.key})
    : editSessionId = null,
      editingEntry = null,
      initialDate = null,
      initialMemo = null;

  const AddWorkoutScreen.editing({
    super.key,
    required this.editSessionId,
    required this.editingEntry,
    required this.initialDate,
    required this.initialMemo,
  });

  final int? editSessionId;
  final WorkoutEntryRecord? editingEntry;
  final DateTime? initialDate;
  final String? initialMemo;

  @override
  ConsumerState<AddWorkoutScreen> createState() => _AddWorkoutScreenState();
}

class _AddWorkoutScreenState extends ConsumerState<AddWorkoutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _memoController = TextEditingController();
  final List<_SetInput> _sets = [];

  late int? _editSessionId;
  late WorkoutEntryRecord? _editingEntry;
  late String? _initialMemo;

  bool get _isEditMode => _editSessionId != null && _editingEntry != null;

  late DateTime _selectedDate;
  late Future<List<BodyPart>> _bodyPartsFuture;
  Future<List<Exercise>>? _exercisesFuture;
  final Map<int, Exercise> _exercisesById = {};
  int? _selectedBodyPartId;
  int? _selectedExerciseId;
  bool _isSaving = false;
  int _existingWorkoutLookupToken = 0;
  bool _isExerciseSelectionLockedFromAddFlow = false;

  bool get _isExerciseSelectionLocked => _isExerciseSelectionLockedFromAddFlow;

  bool get _isSelectedExerciseBodyweight {
    final selectedExerciseId = _selectedExerciseId;
    if (selectedExerciseId == null) {
      return false;
    }
    final selectedExercise = _exercisesById[selectedExerciseId];
    if (selectedExercise != null) {
      return selectedExercise.type == 'bodyweight';
    }
    final editingEntry = _editingEntry;
    return editingEntry?.exercise.id == selectedExerciseId &&
        editingEntry?.exercise.type == 'bodyweight';
  }

  @override
  void initState() {
    super.initState();
    _editSessionId = widget.editSessionId;
    _editingEntry = widget.editingEntry;
    _initialMemo = widget.initialMemo;
    final editingEntry = _editingEntry;
    _selectedDate = widget.initialDate ?? DateTime.now();
    _bodyPartsFuture = ref.read(exerciseServiceProvider).getBodyParts();

    if (editingEntry == null) {
      _sets.add(_SetInput());
      return;
    }

    _selectedBodyPartId = editingEntry.bodyPart.id;
    _selectedExerciseId = editingEntry.exercise.id;
    _exercisesById[editingEntry.exercise.id] = editingEntry.exercise;
    _exercisesFuture = ref
        .read(exerciseServiceProvider)
        .getExercises(bodyPartId: _selectedBodyPartId);
    _memoController.text = editingEntry.entry.memo ?? _initialMemo ?? '';
    _sets.addAll(
      editingEntry.sets.map(
        (set) => _SetInput(
          weight: _formatInputNumber(set.weight),
          reps: set.reps.toString(),
          isWarmup: set.isWarmup,
        ),
      ),
    );
    if (_sets.isEmpty) {
      _sets.add(_SetInput());
    }
  }

  @override
  void dispose() {
    _memoController.dispose();
    for (final set in _sets) {
      set.dispose();
    }
    super.dispose();
  }

  void _selectBodyPart(int? bodyPartId) {
    if (_isExerciseSelectionLocked) {
      return;
    }
    _existingWorkoutLookupToken++;
    setState(() {
      _selectedBodyPartId = bodyPartId;
      _selectedExerciseId = null;
      _exercisesById.clear();
      _exercisesFuture = bodyPartId == null
          ? null
          : ref
                .read(exerciseServiceProvider)
                .getExercises(bodyPartId: bodyPartId);
    });
  }

  Future<void> _selectExercise(int? exerciseId) async {
    if (_isExerciseSelectionLocked) {
      return;
    }
    final lookupToken = ++_existingWorkoutLookupToken;
    final shouldLockExerciseSelectionIfExistingRecordLoads = !_isEditMode;
    setState(() => _selectedExerciseId = exerciseId);
    if (exerciseId != null) {
      await _openExistingWorkoutEntryIfPresent(
        exerciseId: exerciseId,
        date: _selectedDate,
        lookupToken: lookupToken,
        lockExerciseSelectionAfterLoad:
            shouldLockExerciseSelectionIfExistingRecordLoads,
      );
    }
  }

  Future<void> _openExistingWorkoutEntryIfPresent({
    required int exerciseId,
    required DateTime date,
    required int lookupToken,
    required bool lockExerciseSelectionAfterLoad,
  }) async {
    try {
      final existingRecord = await ref
          .read(workoutServiceProvider)
          .findWorkoutRecordForDateAndExercise(
            date: date,
            exerciseId: exerciseId,
          );
      if (!mounted ||
          lookupToken != _existingWorkoutLookupToken ||
          _selectedExerciseId != exerciseId ||
          !_isSameCalendarDay(_selectedDate, date)) {
        return;
      }
      if (existingRecord == null || existingRecord.entries.isEmpty) {
        if (_isEditMode) {
          _resetEntryInputsForSelectedExercise();
        }
        return;
      }
      final existingEntry = existingRecord.entries.firstWhere(
        (entry) => entry.exercise.id == exerciseId,
        orElse: () => existingRecord.entries.first,
      );
      _loadExistingEntryForEditing(
        sessionId: existingRecord.session.id,
        entry: existingEntry,
        date: existingRecord.session.workoutDate,
        sessionMemo: existingRecord.session.memo,
        lockExerciseSelection: lockExerciseSelectionAfterLoad,
      );
      CenteredToast.show(context, '이미 등록한 기록을 불러왔습니다.');
    } catch (error) {
      if (mounted &&
          !_isEditMode &&
          lookupToken == _existingWorkoutLookupToken &&
          _selectedExerciseId == exerciseId &&
          _isSameCalendarDay(_selectedDate, date)) {
        CenteredToast.show(context, '기존 기록 확인에 실패했습니다: $error');
      }
    }
  }

  void _resetEntryInputsForSelectedExercise() {
    for (final set in _sets) {
      set.dispose();
    }
    setState(() {
      _isExerciseSelectionLockedFromAddFlow = false;
      _initialMemo = null;
      _memoController.clear();
      _sets
        ..clear()
        ..add(_SetInput());
    });
  }

  void _loadExistingEntryForEditing({
    required int sessionId,
    required WorkoutEntryRecord entry,
    required DateTime date,
    required String? sessionMemo,
    required bool lockExerciseSelection,
  }) {
    _existingWorkoutLookupToken++;
    for (final set in _sets) {
      set.dispose();
    }
    final loadedSets = entry.sets
        .map(
          (set) => _SetInput(
            weight: _formatInputNumber(set.weight),
            reps: set.reps.toString(),
            isWarmup: set.isWarmup,
          ),
        )
        .toList();
    if (loadedSets.isEmpty) {
      loadedSets.add(_SetInput());
    }

    setState(() {
      _editSessionId = sessionId;
      _editingEntry = entry;
      _isExerciseSelectionLockedFromAddFlow = lockExerciseSelection;
      _initialMemo = sessionMemo;
      _selectedDate = date;
      _selectedBodyPartId = entry.bodyPart.id;
      _selectedExerciseId = entry.exercise.id;
      _exercisesById
        ..clear()
        ..[entry.exercise.id] = entry.exercise;
      _exercisesFuture = ref
          .read(exerciseServiceProvider)
          .getExercises(bodyPartId: entry.bodyPart.id);
      _memoController.text = entry.entry.memo ?? sessionMemo ?? '';
      _sets
        ..clear()
        ..addAll(loadedSets);
    });
  }

  Future<void> _openAddExercise() async {
    final result = await showDialog<_AddedExerciseResult>(
      context: context,
      builder: (_) => const _AddExerciseDialog(),
    );
    if (result == null || !mounted) {
      return;
    }

    _existingWorkoutLookupToken++;
    setState(() {
      _selectedBodyPartId = result.bodyPartId;
      _selectedExerciseId = result.exerciseId;
      _exercisesFuture = ref
          .read(exerciseServiceProvider)
          .getExercises(bodyPartId: result.bodyPartId);
    });
    CenteredToast.show(context, '운동을 등록했습니다.');
  }

  Future<void> _openEditExercise(Exercise exercise) async {
    final referencedEntryCount = await ref
        .read(exerciseServiceProvider)
        .countWorkoutEntriesForExercise(exercise.id);
    if (!mounted) {
      return;
    }
    final result = await showDialog<_AddedExerciseResult>(
      context: context,
      builder: (_) => _AddExerciseDialog(
        exercise: exercise,
        referencedEntryCount: referencedEntryCount,
      ),
    );
    if (result == null || !mounted) {
      return;
    }

    _existingWorkoutLookupToken++;
    setState(() {
      _selectedBodyPartId = result.bodyPartId;
      _selectedExerciseId = result.exerciseId;
      _exercisesFuture = ref
          .read(exerciseServiceProvider)
          .getExercises(bodyPartId: result.bodyPartId);
    });
    CenteredToast.show(context, '운동을 수정했습니다.');
  }

  Future<void> _deleteExercise(Exercise exercise) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Expanded(child: Text('운동 삭제')),
            IconButton(
              onPressed: () => Navigator.of(context).pop(false),
              icon: const Icon(Icons.close_rounded),
              tooltip: '닫기',
            ),
          ],
        ),
        content: Text(
          '내 운동 `${exercise.name}`을 삭제할까요?\n기록에서 사용 중이면 삭제할 수 없습니다.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await ref.read(exerciseServiceProvider).deleteCustomExercise(exercise.id);
      if (!mounted) {
        return;
      }
      _existingWorkoutLookupToken++;
      setState(() {
        if (_selectedExerciseId == exercise.id) {
          _selectedExerciseId = null;
        }
        _exercisesFuture = ref
            .read(exerciseServiceProvider)
            .getExercises(bodyPartId: _selectedBodyPartId);
      });
      CenteredToast.show(context, '운동을 삭제했습니다.');
    } on StateError catch (error) {
      if (mounted) {
        CenteredToast.show(context, error.message.toString());
      }
    } catch (error) {
      if (mounted) {
        CenteredToast.show(context, '운동 삭제에 실패했습니다: $error');
      }
    }
  }

  Future<void> _pickDate() async {
    if (_isEditMode) {
      return;
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('ko', 'KR'),
    );
    if (picked == null || !mounted) {
      return;
    }
    final lookupToken = ++_existingWorkoutLookupToken;
    setState(() => _selectedDate = picked);
    final selectedExerciseId = _selectedExerciseId;
    if (selectedExerciseId != null) {
      await _openExistingWorkoutEntryIfPresent(
        exerciseId: selectedExerciseId,
        date: picked,
        lookupToken: lookupToken,
        lockExerciseSelectionAfterLoad: !_isEditMode,
      );
    }
  }

  void _addSet() {
    setState(() => _sets.add(_SetInput()));
  }

  void _removeSet(int index) {
    if (_sets.length == 1) {
      CenteredToast.show(context, '세트는 1개 이상 필요합니다.');
      return;
    }

    final removed = _sets.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _saveWorkout() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final exerciseId = _isExerciseSelectionLocked
        ? _editingEntry?.exercise.id
        : _selectedExerciseId;
    if (exerciseId == null) {
      CenteredToast.show(context, '운동을 선택해 주세요.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final draft = WorkoutDraft(
        workoutDate: DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        ),
        memo: _trimmedOrNull(_memoController.text),
        entries: [
          WorkoutEntryDraft(
            exerciseId: exerciseId,
            sets: [
              for (final set in _sets)
                WorkoutSetDraft(
                  weight: _isSelectedExerciseBodyweight
                      ? 0
                      : double.parse(set.weightController.text),
                  reps: int.parse(set.repsController.text),
                  isWarmup: set.isWarmup,
                ),
            ],
          ),
        ],
      );
      final editSessionId = _editSessionId;
      final editingEntry = _editingEntry;
      if (editSessionId == null || editingEntry == null) {
        await ref.read(workoutServiceProvider).saveWorkout(draft);
      } else {
        await ref
            .read(workoutServiceProvider)
            .updateWorkoutEntry(
              sessionId: editSessionId,
              entryId: editingEntry.entry.id,
              draft: draft,
            );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      CenteredToast.show(context, '저장에 실패했습니다: $error');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat('yyyy.MM.dd').format(_selectedDate);
    final colorScheme = Theme.of(context).colorScheme;
    final isBodyweightExercise = _isSelectedExerciseBodyweight;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditMode ? '운동 기록 수정' : '운동 기록 추가')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _WorkoutFormHero(
                title: _isEditMode ? '기록을 다듬어볼까요?' : '오늘의 운동을 남겨볼까요?',
                subtitle: _isEditMode
                    ? '날짜는 유지하고 세트와 메모만 다듬을 수 있어요.'
                    : '부위와 운동을 고르고 세트만 입력하면 끝입니다.',
                dateText: dateText,
                onPickDate: _isEditMode || _isSaving ? null : _pickDate,
                isDateLocked: _isEditMode,
              ),
              const SizedBox(height: 14),
              _FormSectionCard(
                title: '운동 선택',
                subtitle: '드롭다운 대신 큰 선택 시트로 빠르게 고를 수 있어요.',
                child: Column(
                  children: [
                    FutureBuilder<List<BodyPart>>(
                      future: _bodyPartsFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Text('부위를 불러오지 못했습니다: ${snapshot.error}');
                        }
                        final bodyParts = snapshot.data ?? const [];
                        return _PickerField<int>(
                          label: '부위',
                          placeholder: '운동 부위 선택',
                          value: _selectedBodyPartId,
                          enabled: !_isSaving && !_isExerciseSelectionLocked,
                          options: [
                            for (final bodyPart in bodyParts)
                              _PickerOption(
                                value: bodyPart.id,
                                label: _displayBodyPartName(bodyPart.name),
                              ),
                          ],
                          onChanged: _selectBodyPart,
                          validator: (value) =>
                              value == null ? '부위를 선택해 주세요.' : null,
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    _ExerciseDropdown(
                      future: _exercisesFuture,
                      selectedExerciseId: _selectedExerciseId,
                      enabled:
                          !_isSaving &&
                          !_isExerciseSelectionLocked &&
                          _selectedBodyPartId != null,
                      onChanged: _selectExercise,
                      onLoaded: (exercises) {
                        _exercisesById
                          ..clear()
                          ..addEntries(
                            exercises.map(
                              (exercise) => MapEntry(exercise.id, exercise),
                            ),
                          );
                      },
                      onEdit: _isSaving || _isExerciseSelectionLocked
                          ? null
                          : _openEditExercise,
                      onDelete: _isSaving || _isExerciseSelectionLocked
                          ? null
                          : _deleteExercise,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _isSaving || _isExerciseSelectionLocked
                            ? null
                            : _openAddExercise,
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        label: const Text('새 운동 등록'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _FormSectionCard(
                title: '세트',
                subtitle: '${_sets.length}개 세트 입력 중',
                trailing: TextButton.icon(
                  onPressed: _isSaving ? null : _addSet,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('추가'),
                ),
                child: Column(
                  children: [
                    for (var index = 0; index < _sets.length; index++)
                      _SetInputRow(
                        key: ValueKey(_sets[index]),
                        setNumber: index + 1,
                        input: _sets[index],
                        enabled: !_isSaving,
                        isBodyweightExercise: isBodyweightExercise,
                        onWarmupChanged: (value) => setState(
                          () => _sets[index].isWarmup = value ?? false,
                        ),
                        onRemove: () => _removeSet(index),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _FormSectionCard(
                title: '메모',
                subtitle: '컨디션이나 자세 느낌을 짧게 남겨두세요.',
                child: TextFormField(
                  controller: _memoController,
                  enabled: !_isSaving,
                  onTapOutside: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  decoration: const InputDecoration(
                    labelText: '메모',
                    hintText: '예: 마지막 세트 힘들었음',
                  ),
                  maxLines: 3,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isSaving ? null : _saveWorkout,
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                ),
                child: _isSaving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isEditMode ? '수정 저장' : '저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExerciseDropdown extends StatelessWidget {
  const _ExerciseDropdown({
    required this.future,
    required this.selectedExerciseId,
    required this.enabled,
    required this.onChanged,
    required this.onLoaded,
    required this.onEdit,
    required this.onDelete,
  });

  final Future<List<Exercise>>? future;
  final int? selectedExerciseId;
  final bool enabled;
  final ValueChanged<int?> onChanged;
  final ValueChanged<List<Exercise>> onLoaded;
  final ValueChanged<Exercise>? onEdit;
  final ValueChanged<Exercise>? onDelete;

  @override
  Widget build(BuildContext context) {
    final future = this.future;
    if (future == null) {
      return _PickerField<int>(
        label: '운동',
        placeholder: '먼저 부위를 선택해 주세요',
        value: null,
        enabled: false,
        options: const [],
        onChanged: (_) {},
        validator: (_) => '운동을 선택해 주세요.',
      );
    }

    return FutureBuilder<List<Exercise>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Text('운동을 불러오지 못했습니다: ${snapshot.error}');
        }
        final exercises = snapshot.data ?? const [];
        onLoaded(exercises);
        final effectiveExerciseId =
            exercises.any((exercise) => exercise.id == selectedExerciseId)
            ? selectedExerciseId
            : null;
        return _ExercisePickerField(
          placeholder: exercises.isEmpty ? '등록된 운동이 없습니다' : '운동 선택',
          exercises: exercises,
          selectedExerciseId: effectiveExerciseId,
          enabled: enabled && exercises.isNotEmpty,
          onChanged: onChanged,
          onEdit: onEdit,
          onDelete: onDelete,
          validator: (value) => value == null ? '운동을 선택해 주세요.' : null,
        );
      },
    );
  }
}

class _ExercisePickerField extends FormField<int> {
  _ExercisePickerField({
    required String placeholder,
    required List<Exercise> exercises,
    required int? selectedExerciseId,
    required bool enabled,
    required ValueChanged<int?> onChanged,
    required ValueChanged<Exercise>? onEdit,
    required ValueChanged<Exercise>? onDelete,
    super.validator,
  }) : super(
         key: ValueKey<Object?>('운동-$selectedExerciseId'),
         initialValue: selectedExerciseId,
         builder: (state) {
           Exercise? selected;
           for (final exercise in exercises) {
             if (exercise.id == state.value) {
               selected = exercise;
               break;
             }
           }
           return _ExercisePickerFieldBody(
             placeholder: placeholder,
             selected: selected,
             exercises: exercises,
             enabled: enabled,
             errorText: state.errorText,
             onChanged: (nextValue) {
               state.didChange(nextValue);
               onChanged(nextValue);
             },
             onEdit: onEdit,
             onDelete: onDelete,
           );
         },
       );
}

class _ExercisePickerFieldBody extends StatelessWidget {
  const _ExercisePickerFieldBody({
    required this.placeholder,
    required this.selected,
    required this.exercises,
    required this.enabled,
    required this.errorText,
    required this.onChanged,
    required this.onEdit,
    required this.onDelete,
  });

  final String placeholder;
  final Exercise? selected;
  final List<Exercise> exercises;
  final bool enabled;
  final String? errorText;
  final ValueChanged<int?> onChanged;
  final ValueChanged<Exercise>? onEdit;
  final ValueChanged<Exercise>? onDelete;

  Future<void> _openPicker(BuildContext context) async {
    if (!enabled) {
      return;
    }
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _ExercisePickerSheet(
        exercises: exercises,
        selectedExerciseId: selected?.id,
        onEdit: onEdit,
        onDelete: onDelete,
      ),
    );
    if (picked != null) {
      onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _openPicker(context),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: enabled ? Colors.white : const Color(0xFFF3F6FA),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: errorText == null
                    ? const Color(0xFFE1E8F2)
                    : colorScheme.error,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F2FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.tune_rounded, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '운동',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: const Color(0xFF6B7280)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selected == null
                            ? placeholder
                            : _exerciseDisplayName(selected!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: enabled
                              ? const Color(0xFF111827)
                              : const Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: enabled
                      ? const Color(0xFF4B5563)
                      : const Color(0xFF9CA3AF),
                ),
              ],
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              errorText!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
            ),
          ),
        ],
      ],
    );
  }
}

class _ExercisePickerSheet extends StatelessWidget {
  const _ExercisePickerSheet({
    required this.exercises,
    required this.selectedExerciseId,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Exercise> exercises;
  final int? selectedExerciseId;
  final ValueChanged<Exercise>? onEdit;
  final ValueChanged<Exercise>? onDelete;

  Future<void> _openActions(BuildContext context, Exercise exercise) async {
    final action = await showModalBottomSheet<_ExerciseAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                exercise.name,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('운동 수정'),
                onTap: () => Navigator.of(context).pop(_ExerciseAction.edit),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  '운동 삭제',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () => Navigator.of(context).pop(_ExerciseAction.delete),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) {
      return;
    }
    Navigator.of(context).pop();
    switch (action) {
      case _ExerciseAction.edit:
        onEdit?.call(exercise);
      case _ExerciseAction.delete:
        onDelete?.call(exercise);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.36,
      maxChildSize: 0.9,
      builder: (context, scrollController) => ListView.separated(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: exercises.length + 1,
        separatorBuilder: (_, index) =>
            index == 0 ? const SizedBox(height: 12) : const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Text(
              '운동 선택',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            );
          }
          final exercise = exercises[index - 1];
          final selected = exercise.id == selectedExerciseId;
          return Material(
            color: selected ? const Color(0xFFE8F2FF) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(exercise.id),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected
                        ? colorScheme.primary
                        : const Color(0xFFE8EEF6),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            _exerciseDisplayName(exercise),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if (exercise.isCustom)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE8F2FF),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '내 운동',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_circle_rounded,
                        color: colorScheme.primary,
                      ),
                    if (exercise.isCustom)
                      IconButton(
                        onPressed: onEdit == null && onDelete == null
                            ? null
                            : () => _openActions(context, exercise),
                        icon: const Icon(Icons.more_vert_rounded),
                        tooltip: '내 운동 관리',
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ArmDetailSelector extends StatelessWidget {
  const _ArmDetailSelector({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String? value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('팔 세부 부위', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in const [
              (id: armDetailBiceps, label: '이두'),
              (id: armDetailTriceps, label: '삼두'),
            ])
              ChoiceChip(
                label: Text(option.label),
                selected: value == option.id,
                showCheckmark: false,
                selectedColor: const Color(0xFFE8F2FF),
                side: BorderSide(
                  color: value == option.id
                      ? const Color(0xFF3182F6)
                      : const Color(0xFFE1E8F2),
                ),
                onSelected: enabled
                    ? (selected) {
                        if (selected) {
                          onChanged(option.id);
                        }
                      }
                    : null,
              ),
          ],
        ),
      ],
    );
  }
}

enum _ExerciseAction { edit, delete }

class _WorkoutFormHero extends StatelessWidget {
  const _WorkoutFormHero({
    required this.title,
    required this.subtitle,
    required this.dateText,
    required this.onPickDate,
    required this.isDateLocked,
  });

  final String title;
  final String subtitle;
  final String dateText;
  final VoidCallback? onPickDate;
  final bool isDateLocked;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 18),
          InkWell(
            onTap: onPickDate,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: Row(
                children: [
                  Icon(
                    isDateLocked
                        ? Icons.lock_outline_rounded
                        : Icons.calendar_today_rounded,
                    color: isDateLocked ? Colors.white70 : colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isDateLocked ? '날짜 · 수정 불가' : '날짜',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: Colors.white70),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dateText,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (!isDateLocked)
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Colors.white70,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormSectionCard extends StatelessWidget {
  const _FormSectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
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
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _PickerOption<T> {
  const _PickerOption({
    required this.value,
    required this.label,
    this.subtitle,
  });

  final T value;
  final String label;
  final String? subtitle;
}

class _PickerField<T> extends FormField<T> {
  _PickerField({
    required String label,
    required String placeholder,
    required List<_PickerOption<T>> options,
    required ValueChanged<T?> onChanged,
    required bool enabled,
    required T? value,
    super.validator,
  }) : super(
         key: ValueKey<Object?>('$label-$value'),
         initialValue: value,
         builder: (state) {
           _PickerOption<T>? selected;
           for (final option in options) {
             if (option.value == state.value) {
               selected = option;
               break;
             }
           }
           return _PickerFieldBody<T>(
             label: label,
             placeholder: placeholder,
             selected: selected,
             options: options,
             enabled: enabled,
             errorText: state.errorText,
             onChanged: (nextValue) {
               state.didChange(nextValue);
               onChanged(nextValue);
             },
           );
         },
       );
}

class _PickerFieldBody<T> extends StatelessWidget {
  const _PickerFieldBody({
    required this.label,
    required this.placeholder,
    required this.selected,
    required this.options,
    required this.enabled,
    required this.errorText,
    required this.onChanged,
  });

  final String label;
  final String placeholder;
  final _PickerOption<T>? selected;
  final List<_PickerOption<T>> options;
  final bool enabled;
  final String? errorText;
  final ValueChanged<T?> onChanged;

  Future<void> _openPicker(BuildContext context) async {
    if (!enabled) {
      return;
    }
    final picked = await showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => _PickerSheet<T>(
        title: label,
        options: options,
        selectedValue: selected?.value,
      ),
    );
    if (picked != null) {
      onChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _openPicker(context),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: enabled ? Colors.white : const Color(0xFFF3F6FA),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: errorText == null
                    ? const Color(0xFFE1E8F2)
                    : colorScheme.error,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F2FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.tune_rounded, color: colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: const Color(0xFF6B7280)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        selected?.label ?? placeholder,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: enabled
                              ? const Color(0xFF111827)
                              : const Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: enabled
                      ? const Color(0xFF4B5563)
                      : const Color(0xFF9CA3AF),
                ),
              ],
            ),
          ),
        ),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              errorText!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
            ),
          ),
        ],
      ],
    );
  }
}

class _PickerSheet<T> extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.selectedValue,
  });

  final String title;
  final List<_PickerOption<T>> options;
  final T? selectedValue;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.36,
      maxChildSize: 0.9,
      builder: (context, scrollController) => ListView.separated(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: options.length + 1,
        separatorBuilder: (_, index) =>
            index == 0 ? const SizedBox(height: 12) : const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Text(
              '$title 선택',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            );
          }
          final option = options[index - 1];
          final selected = option.value == selectedValue;
          return Material(
            color: selected ? const Color(0xFFE8F2FF) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: () => Navigator.of(context).pop(option.value),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected
                        ? colorScheme.primary
                        : const Color(0xFFE8EEF6),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            option.label,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if (option.subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(option.subtitle!),
                          ],
                        ],
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_circle_rounded,
                        color: colorScheme.primary,
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SetInputRow extends StatelessWidget {
  const _SetInputRow({
    super.key,
    required this.setNumber,
    required this.input,
    required this.enabled,
    required this.isBodyweightExercise,
    required this.onWarmupChanged,
    required this.onRemove,
  });

  final int setNumber;
  final _SetInput input;
  final bool enabled;
  final bool isBodyweightExercise;
  final ValueChanged<bool?> onWarmupChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text('$setNumber세트'),
            ),
          ),
          if (!isBodyweightExercise) ...[
            Expanded(
              child: TextFormField(
                controller: input.weightController,
                enabled: enabled,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                decoration: const InputDecoration(
                  labelText: '무게(kg)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: _validateWeight,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: TextFormField(
              controller: input.repsController,
              enabled: enabled,
              onTapOutside: (_) =>
                  FocusManager.instance.primaryFocus?.unfocus(),
              decoration: const InputDecoration(
                labelText: '횟수',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              validator: _validateReps,
            ),
          ),
          SizedBox(
            width: 56,
            child: Column(
              children: [
                Text('워밍업', style: Theme.of(context).textTheme.labelSmall),
                Checkbox(
                  value: input.isWarmup,
                  onChanged: enabled ? onWarmupChanged : null,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: enabled ? onRemove : null,
            icon: const Icon(Icons.delete_outline),
            tooltip: '세트 삭제',
          ),
        ],
      ),
    );
  }
}

class _SetInput {
  _SetInput({String? weight, String? reps, this.isWarmup = false})
    : weightController = TextEditingController(text: weight),
      repsController = TextEditingController(text: reps);

  final TextEditingController weightController;
  final TextEditingController repsController;
  bool isWarmup;

  void dispose() {
    weightController.dispose();
    repsController.dispose();
  }
}

String _formatInputNumber(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toString();
}

String? _validateWeight(String? value) {
  final weight = double.tryParse(value ?? '');
  if (weight == null) {
    return '입력';
  }
  if (weight < 0) {
    return '0 이상';
  }
  return null;
}

String? _validateReps(String? value) {
  final reps = int.tryParse(value ?? '');
  if (reps == null) {
    return '입력';
  }
  if (reps < 1) {
    return '1 이상';
  }
  return null;
}

String? _trimmedOrNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _isSameCalendarDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _exerciseDisplayName(Exercise exercise) {
  final label = _armDetailLabel(exercise.armDetail);
  return label == null ? exercise.name : '${exercise.name} · $label';
}

String? _armDetailLabel(String? armDetail) {
  return switch (armDetail) {
    armDetailBiceps => '이두',
    armDetailTriceps => '삼두',
    _ => null,
  };
}

String _displayBodyPartName(String name) => name == '코어' ? '복근' : name;
