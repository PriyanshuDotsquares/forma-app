import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';

/// Shows the rest-timer bottom sheet: a big circular countdown, -15/SKIP
/// REST/+15 controls, an "UP NEXT" preview of the next set, and an optional
/// coaching-note banner. Auto-dismisses when the countdown reaches zero or
/// when SKIP REST is tapped.
Future<void> showRestTimerSheet(
  BuildContext context, {
  required int initialSeconds,
  required String nextSetLabel,
  String? coachingNote,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (context) => RestTimerSheet(initialSeconds: initialSeconds, nextSetLabel: nextSetLabel, coachingNote: coachingNote),
  );
}

class RestTimerSheet extends StatefulWidget {
  const RestTimerSheet({super.key, required this.initialSeconds, required this.nextSetLabel, this.coachingNote});

  final int initialSeconds;
  final String nextSetLabel;
  final String? coachingNote;

  @override
  State<RestTimerSheet> createState() => _RestTimerSheetState();
}

class _RestTimerSheetState extends State<RestTimerSheet> {
  late int _remaining = widget.initialSeconds;
  late int _total = widget.initialSeconds <= 0 ? 1 : widget.initialSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTicking();
  }

  void _startTicking() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining <= 1) {
        _timer?.cancel();
        setState(() => _remaining = 0);
        // Let the zero state paint for a frame before popping.
        Future.microtask(() {
          if (mounted) Navigator.of(context).pop();
        });
        return;
      }
      setState(() => _remaining -= 1);
    });
  }

  void _adjust(int deltaSeconds) {
    setState(() {
      _remaining = (_remaining + deltaSeconds).clamp(0, 15 * 60);
      if (_remaining > _total) _total = _remaining;
    });
    if (_remaining > 0 && (_timer == null || !_timer!.isActive)) {
      _startTicking();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (1 - (_remaining / _total)).clamp(0.0, 1.0);
    final minutes = (_remaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (_remaining % 60).toString().padLeft(2, '0');

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'REST',
              style: AppTypography.body(size: 12, weight: FontWeight.w700, color: AppColors.textMuted).copyWith(letterSpacing: 1.5),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: 200,
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 8,
                      backgroundColor: AppColors.surfaceHighest,
                      color: AppColors.accentBlue,
                    ),
                  ),
                  Text('$minutes:$seconds', style: AppTypography.mono(size: 44, weight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(onPressed: () => _adjust(-15), child: const Text('-15')),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('SKIP REST')),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton(onPressed: () => _adjust(15), child: const Text('+15')),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (widget.coachingNote != null) ...[
              InfoBanner(
                title: 'FROM YOUR LAST SET',
                body: widget.coachingNote,
                accent: AppColors.accentAmber,
                icon: Icons.info_outline,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceBase,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionLabel('UP NEXT'),
                  const SizedBox(height: AppSpacing.xs),
                  Text(widget.nextSetLabel, style: AppTypography.body(size: 14, weight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
