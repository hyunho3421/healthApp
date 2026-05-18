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
  const ProfileSettingsScreen({
    super.key,
    this.isRootTab = false,
    this.onSaved,
  });

  final bool isRootTab;
  final VoidCallback? onSaved;

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
      notifyUserProfileChanged(ref);
      if (!mounted) {
        return;
      }
      widget.onSaved?.call();
      if (widget.isRootTab) {
        setState(() => _isSaving = false);
        CenteredToast.show(context, '프로필을 저장했습니다.');
      } else {
        Navigator.of(context).pop(true);
      }
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Container(
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
                                  '프로필 설정',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '칼로리 계산 기준으로 사용할 체중만 관리합니다.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.72,
                                        ),
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
                            child: const Icon(
                              Icons.person_outline_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '신체 정보',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '입력한 체중은 운동 칼로리 추정에만 사용됩니다.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: const Color(0xFF6B7280)),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _bodyWeightController,
                              onTapOutside: (_) =>
                                  FocusManager.instance.primaryFocus?.unfocus(),
                              decoration: const InputDecoration(
                                labelText: '체중(kg)',
                                hintText: '예: 70',
                                helperText: '키는 칼로리 예상 계산에 사용하지 않습니다.',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
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
                          ],
                        ),
                      ),
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
