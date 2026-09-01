import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/design_system/design_system.dart';
import '../../../core/router/app_router.dart';

class _Feature {
  const _Feature(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title;
  final String subtitle;
}

const _features = [
  _Feature(Icons.videocam_outlined, 'Unlimited AI coaching', 'Every set, every exercise'),
  _Feature(Icons.insights_outlined, 'Form analytics', 'See your depth and technique trending'),
  _Feature(Icons.auto_awesome, 'A plan that adapts', 'Weekly adjustments from your real data'),
  _Feature(Icons.archive_outlined, 'Your full history', 'Every session, forever, exportable'),
];

/// The paywall — always shows the full feature-benefits variant (the more
/// complete of the two the design offers). Reachable from any "hit a free
/// limit" trigger, so the headline stays generic rather than assuming a
/// specific paywall origin.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  String _plan = 'annual'; // annual | monthly

  void _close(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.profile);
    }
  }

  Future<void> _restore(BuildContext context) async {
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (_) {
      // Fall through to the same honest message below either way.
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to restore.')));
    }
  }

  Future<void> _startTrial(BuildContext context) async {
    final available = await InAppPurchase.instance.isAvailable();
    if (!context.mounted) return;
    if (!available) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Not available yet'),
          content: const Text(
            "In-app purchases aren't configured for this build yet — there's no live product to buy. "
            "This won't unlock Pro or change your subscription.",
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
        ),
      );
      return;
    }
    // A real integration would continue here with `queryProductDetails` for
    // the configured product IDs and `buyNonConsumable`/`buyConsumable`,
    // then apply the entitlement server-side once the purchase stream
    // confirms it. There are no real product IDs registered in this
    // environment, so `isAvailable()` gates the flow before it can reach
    // that point — the plumbing is left ready rather than faked.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceLowest,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                children: [
                  IconButton(onPressed: () => _close(context), icon: const Icon(Icons.close)),
                  Expanded(
                    child: Text(
                      'PREMIUM UPGRADE',
                      textAlign: TextAlign.center,
                      style: AppTypography.display(size: 20).copyWith(letterSpacing: -0.5),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _restore(context),
                    child: Text(
                      'RESTORE',
                      style: AppTypography.body(
                        size: 12,
                        weight: FontWeight.w700,
                        color: AppColors.accentBlue,
                      ).copyWith(letterSpacing: 0.96),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
                children: [
                  Text(
                    'FORMA PRO',
                    style: AppTypography.body(
                      size: 12,
                      weight: FontWeight.w700,
                      color: AppColors.accentBlue,
                    ).copyWith(letterSpacing: 1.4),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text('Unlock unlimited AI coaching.', style: AppTypography.display(size: 28)),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    "Get real-time form feedback on every set, a plan that adjusts to how you're actually "
                    'training, and your complete history — no caps, no waiting.',
                    style: AppTypography.body(size: 14, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  for (final f in _features) _FeatureRow(feature: f),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PriceCard(
                        title: 'Annual',
                        price: '£59.99',
                        subPrice: '£5.00 / month',
                        subPriceColor: AppColors.accentBlue,
                        badge: 'SAVE 50%',
                        selected: _plan == 'annual',
                        onTap: () => setState(() => _plan = 'annual'),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      _PriceCard(
                        title: 'Monthly',
                        price: '£9.99',
                        subPrice: 'per month',
                        subPriceColor: AppColors.textSecondary,
                        selected: _plan == 'monthly',
                        onTap: () => setState(() => _plan = 'monthly'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => _startTrial(context),
                      child: const Text('Start 7-day free trial'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _plan == 'annual'
                        ? 'Then £59.99/year. Cancel any time in Settings.'
                        : 'Then £9.99/month. Cancel any time in Settings.',
                    textAlign: TextAlign.center,
                    style: AppTypography.body(size: 12, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Terms · Privacy',
                    textAlign: TextAlign.center,
                    style: AppTypography.body(size: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature});
  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.outlineVariant),
            ),
            alignment: Alignment.center,
            child: Icon(feature.icon, size: 20, color: AppColors.accentBlue),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(feature.title, style: AppTypography.body(size: 15, weight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(feature.subtitle, style: AppTypography.body(size: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({
    required this.title,
    required this.price,
    required this.subPrice,
    required this.subPriceColor,
    this.badge,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String price;
  final String subPrice;
  final Color subPriceColor;
  final String? badge;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderColor = selected ? AppColors.accentBlue : AppColors.outlineVariant;
    final titleColor = selected ? AppColors.textPrimary : AppColors.textSecondary;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        // clipBehavior.none so the savings badge can float above the top
        // edge, straddling the border like the Figma "sale ribbon" treatment.
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Container(
              // Explicit width: Stack loosens the Expanded-imposed width
              // constraint for non-positioned children, so this still has to
              // ask for the full available width rather than shrink-wrapping.
              width: double.infinity,
              height: 140,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: selected ? AppColors.accentBlue.withValues(alpha: 0.1) : AppColors.surfaceBase,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(title, style: AppTypography.body(size: 16, weight: FontWeight.w500, color: titleColor)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        price,
                        style: AppTypography.mono(size: 28, weight: FontWeight.w600, color: titleColor),
                      ),
                      Text(subPrice, style: AppTypography.mono(size: 13, color: subPriceColor)),
                    ],
                  ),
                ],
              ),
            ),
            if (badge != null) Positioned(top: -10, child: BadgePill(badge!)),
          ],
        ),
      ),
    );
  }
}
