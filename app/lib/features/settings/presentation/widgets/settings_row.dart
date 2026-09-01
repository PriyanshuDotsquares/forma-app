import 'package:flutter/material.dart';

import '../../../../core/design_system/design_system.dart';

/// One row in a settings section: optional leading icon, label, trailing
/// value text/widget, and a chevron (unless [showChevron] is false — e.g.
/// destructive rows that open a confirmation dialog rather than drilling
/// into another screen).
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.icon,
    this.subtitle,
    this.valueText,
    this.trailing,
    this.showChevron = true,
    this.destructive = false,
    this.enabled = true,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final String? subtitle;
  final String? valueText;
  final Widget? trailing;
  final bool showChevron;
  final bool destructive;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final labelColor = destructive ? AppColors.error : (enabled ? AppColors.textPrimary : AppColors.textMuted);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: destructive ? AppColors.error : AppColors.textSecondary),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label, style: AppTypography.body(size: 15, weight: FontWeight.w600, color: labelColor)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: AppTypography.body(size: 13, color: AppColors.textSecondary)),
                    ],
                  ],
                ),
              ),
              if (valueText != null) ...[
                Flexible(
                  child: Text(
                    valueText!,
                    style: AppTypography.body(size: 13, color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              if (trailing != null) ...[trailing!, const SizedBox(width: AppSpacing.sm)],
              if (showChevron) const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled, bordered card grouping a set of [SettingsRow]s with 1px
/// dividers between them — "TRAINING", "COACH & CAMERA", "APP", "ACCOUNT".
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(title),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surfaceBase,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.outlineVariant),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i != rows.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
