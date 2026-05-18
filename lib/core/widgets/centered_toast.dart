import 'dart:async';

import 'package:flutter/material.dart';

/// 화면 중앙에 사용자 피드백 문구를 짧게 표시하는 공통 토스트.
///
/// 새 문구가 표시될 때 기존 토스트를 먼저 제거해 연속 호출 시 중복 누적을
/// 방지한다.
class CenteredToast {
  CenteredToast._();

  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 1500),
  }) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return;
    }

    _removeCurrent();

    final entry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: IgnorePointer(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 14,
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _dismissTimer = Timer(duration, () {
      if (!identical(_currentEntry, entry)) {
        return;
      }
      _removeCurrent(cancelTimer: false);
    });
  }

  static void _removeCurrent({bool cancelTimer = true}) {
    if (cancelTimer) {
      _dismissTimer?.cancel();
    }
    _dismissTimer = null;

    final entry = _currentEntry;
    _currentEntry = null;
    entry?.remove();
  }
}
