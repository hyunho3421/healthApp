import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/centered_toast.dart';
import '../providers/user_profile_providers.dart';

String _formatVolume(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(1);
}

class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() =>
      _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bodyWeightController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final bodyWeightKg = await ref
        .read(userProfileServiceProvider)
        .getBodyWeightKg();
    if (!mounted) {
      return;
    }
    _bodyWeightController.text = bodyWeightKg == null
        ? ''
        : _formatVolume(bodyWeightKg);
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _bodyWeightController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      final bodyWeightKg = double.parse(_bodyWeightController.text.trim());
      await ref.read(userProfileServiceProvider).saveBodyWeightKg(bodyWeightKg);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _isSaving = false);
      CenteredToast.show(context, '저장에 실패했습니다: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정/프로필')),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      '칼로리 계산에 사용할 체중을 입력해주세요.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _bodyWeightController,
                      decoration: const InputDecoration(
                        labelText: '체중(kg)',
                        hintText: '예: 70',
                        border: OutlineInputBorder(),
                        helperText: '키는 칼로리 예상 계산에 사용하지 않습니다.',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) {
                        final bodyWeightKg = double.tryParse(
                          value?.trim() ?? '',
                        );
                        if (bodyWeightKg == null) {
                          return '체중을 숫자로 입력해주세요.';
                        }
                        if (bodyWeightKg < 20 || bodyWeightKg > 300) {
                          return '20kg 이상 300kg 이하로 입력해주세요.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _isSaving ? null : _save,
                      child: Text(_isSaving ? '저장 중...' : '저장'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
