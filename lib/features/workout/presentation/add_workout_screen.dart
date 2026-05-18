import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/db/app_database.dart';
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
  const _AddExerciseDialog();

  @override
  ConsumerState<_AddExerciseDialog> createState() => _AddExerciseDialogState();
}

class _AddExerciseDialogState extends ConsumerState<_AddExerciseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  late Future<List<BodyPart>> _bodyPartsFuture;
  int? _selectedBodyPartId;
  String _selectedExerciseTypeId = defaultExerciseTypeId;
  String? _errorText;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _bodyPartsFuture = ref.read(exerciseServiceProvider).getBodyParts();
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

    setState(() => _isSaving = true);
    try {
      final exerciseId = await ref
          .read(exerciseServiceProvider)
          .addCustomExercise(
            bodyPartId: bodyPartId,
            name: _nameController.text,
            type: _selectedExerciseTypeId,
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(
        _AddedExerciseResult(bodyPartId: bodyPartId, exerciseId: exerciseId),
      );
    } on StateError {
      if (mounted) {
        setState(() => _errorText = '이미 등록된 운동입니다.');
      }
    } on ArgumentError catch (error) {
      if (mounted) {
        setState(
          () => _errorText = error.message?.toString() ?? '입력값을 확인해 주세요.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorText = '운동 등록에 실패했습니다: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('운동 등록'),
      scrollable: true,
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
                return DropdownButtonFormField<int>(
                  initialValue: _selectedBodyPartId,
                  decoration: const InputDecoration(
                    labelText: '부위',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final bodyPart in bodyParts)
                      DropdownMenuItem<int>(
                        value: bodyPart.id,
                        child: Text(bodyPart.name),
                      ),
                  ],
                  onChanged: _isSaving
                      ? null
                      : (value) => setState(() => _selectedBodyPartId = value),
                  validator: (value) => value == null ? '부위를 선택해 주세요.' : null,
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
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final exerciseType in exerciseTypes)
                  ChoiceChip(
                    label: Text(exerciseType.label),
                    selected: _selectedExerciseTypeId == exerciseType.id,
                    onSelected: _isSaving
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
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('등록'),
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

  bool get _isEditMode =>
      widget.editSessionId != null && widget.editingEntry != null;

  late DateTime _selectedDate;
  late Future<List<BodyPart>> _bodyPartsFuture;
  Future<List<Exercise>>? _exercisesFuture;
  int? _selectedBodyPartId;
  int? _selectedExerciseId;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final editingEntry = widget.editingEntry;
    _selectedDate = widget.initialDate ?? DateTime.now();
    _bodyPartsFuture = ref.read(exerciseServiceProvider).getBodyParts();

    if (editingEntry == null) {
      _sets.add(_SetInput());
      return;
    }

    _selectedBodyPartId = editingEntry.bodyPart.id;
    _selectedExerciseId = editingEntry.exercise.id;
    _exercisesFuture = ref
        .read(exerciseServiceProvider)
        .getExercises(bodyPartId: _selectedBodyPartId);
    _memoController.text = editingEntry.entry.memo ?? widget.initialMemo ?? '';
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
    setState(() {
      _selectedBodyPartId = bodyPartId;
      _selectedExerciseId = null;
      _exercisesFuture = bodyPartId == null
          ? null
          : ref
                .read(exerciseServiceProvider)
                .getExercises(bodyPartId: bodyPartId);
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

    setState(() {
      _selectedBodyPartId = result.bodyPartId;
      _selectedExerciseId = result.exerciseId;
      _exercisesFuture = ref
          .read(exerciseServiceProvider)
          .getExercises(bodyPartId: result.bodyPartId);
    });
    CenteredToast.show(context, '운동을 등록했습니다.');
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _selectedDate = picked);
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
    final exerciseId = _selectedExerciseId;
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
                  weight: double.parse(set.weightController.text),
                  reps: int.parse(set.repsController.text),
                  isWarmup: set.isWarmup,
                ),
            ],
          ),
        ],
      );
      final editSessionId = widget.editSessionId;
      final editingEntry = widget.editingEntry;
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

    return Scaffold(
      appBar: AppBar(title: Text(_isEditMode ? '운동 기록 수정' : '운동 기록 추가')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('날짜'),
                subtitle: Text(dateText),
                trailing: const Icon(Icons.calendar_today),
                onTap: _pickDate,
              ),
              const SizedBox(height: 16),
              FutureBuilder<List<BodyPart>>(
                future: _bodyPartsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Text('부위를 불러오지 못했습니다: ${snapshot.error}');
                  }
                  final bodyParts = snapshot.data ?? const [];
                  return DropdownButtonFormField<int>(
                    initialValue: _selectedBodyPartId,
                    decoration: const InputDecoration(
                      labelText: '부위',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final bodyPart in bodyParts)
                        DropdownMenuItem<int>(
                          value: bodyPart.id,
                          child: Text(bodyPart.name),
                        ),
                    ],
                    onChanged: _isSaving ? null : _selectBodyPart,
                    validator: (value) => value == null ? '부위를 선택해 주세요.' : null,
                  );
                },
              ),
              const SizedBox(height: 16),
              _ExerciseDropdown(
                future: _exercisesFuture,
                selectedExerciseId: _selectedExerciseId,
                enabled: !_isSaving && _selectedBodyPartId != null,
                onChanged: (value) =>
                    setState(() => _selectedExerciseId = value),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _isSaving ? null : _openAddExercise,
                  icon: const Icon(Icons.fitness_center),
                  label: const Text('운동 등록'),
                ),
              ),
              const SizedBox(height: 24),
              Text('세트', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (var index = 0; index < _sets.length; index++)
                _SetInputRow(
                  key: ValueKey(_sets[index]),
                  setNumber: index + 1,
                  input: _sets[index],
                  enabled: !_isSaving,
                  onWarmupChanged: (value) =>
                      setState(() => _sets[index].isWarmup = value ?? false),
                  onRemove: () => _removeSet(index),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _isSaving ? null : _addSet,
                  icon: const Icon(Icons.add),
                  label: const Text('세트 추가'),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _memoController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: '메모',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isSaving ? null : _saveWorkout,
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
  });

  final Future<List<Exercise>>? future;
  final int? selectedExerciseId;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final future = this.future;
    if (future == null) {
      return DropdownButtonFormField<int>(
        initialValue: null,
        decoration: const InputDecoration(
          labelText: '운동',
          border: OutlineInputBorder(),
        ),
        items: const [],
        onChanged: null,
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
        final effectiveExerciseId =
            exercises.any((exercise) => exercise.id == selectedExerciseId)
            ? selectedExerciseId
            : null;
        return DropdownButtonFormField<int>(
          initialValue: effectiveExerciseId,
          decoration: const InputDecoration(
            labelText: '운동',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final exercise in exercises)
              DropdownMenuItem<int>(
                value: exercise.id,
                child: Text(exercise.name),
              ),
          ],
          onChanged: enabled ? onChanged : null,
          validator: (value) => value == null ? '운동을 선택해 주세요.' : null,
        );
      },
    );
  }
}

class _SetInputRow extends StatelessWidget {
  const _SetInputRow({
    super.key,
    required this.setNumber,
    required this.input,
    required this.enabled,
    required this.onWarmupChanged,
    required this.onRemove,
  });

  final int setNumber;
  final _SetInput input;
  final bool enabled;
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
          Expanded(
            child: TextFormField(
              controller: input.weightController,
              enabled: enabled,
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
          Expanded(
            child: TextFormField(
              controller: input.repsController,
              enabled: enabled,
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
