import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/misc.dart';
import '../../core/widgets/common.dart';
import '../race/engine/race_models.dart';
import '../race/race_builder.dart';
import '../race/race_outcome.dart';
import '../race/ui/race_screen.dart';

/// Shared plumbing for game modes: launch a race, post-process the outcome, show the result.
class ModeFlow {
  static ProviderContainer container(BuildContext c) => ProviderScope.containerOf(c);

  static RaceBuilder builder(ProviderContainer c) => RaceBuilder(c.read(contentProvider), c.read(profileProvider), c.read(settingsProvider));

  static Future<T?> push<T>(BuildContext context, Widget w) => Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => w));

  /// A compact reward line used in result screens (mode bonuses).
  static Widget rewardPanel(String title, {int coins = 0, int xp = 0, int gems = 0, List<String> lines = const []}) => Panel(
        border: C.gold.withValues(alpha: 0.5),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: C.gold)),
          const SizedBox(height: 6),
          Wrap(spacing: 14, runSpacing: 4, children: [
            if (coins > 0) Text('🪙 +${fmtInt(coins)}', style: const TextStyle(fontWeight: FontWeight.w800)),
            if (xp > 0) Text('⚡ +${fmtInt(xp)} خبرة', style: const TextStyle(fontWeight: FontWeight.w800)),
            if (gems > 0) Text('💎 +$gems', style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
          for (final l in lines) Padding(padding: const EdgeInsets.only(top: 4), child: Text(l, style: const TextStyle(color: C.textDim, fontSize: 12))),
        ]),
      );

  /// Runs [config] in a race screen; [finish] builds the screen to show afterwards (defaults to the plain result).
  static Future<void> race(
    BuildContext context, {
    required RaceConfig Function() config,
    bool again = true,
    Widget Function(BuildContext context, RaceResult result, RaceOutcome outcome, RaceConfig Function()? rebuild)? finish,
  }) async {
    final cfg = config();
    await push<void>(
      context,
      RaceScreen(
        config: cfg,
        rebuild: again ? config : null,
        onFinished: finish == null ? null : (ctx, result, outcome) async => finish(ctx, result, outcome, again ? config : null),
      ),
    );
  }
}
