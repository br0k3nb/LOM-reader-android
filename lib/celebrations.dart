import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'habit_store.dart';
import 'motion.dart';

/// Reward dialogs currently on screen. Other celebrations wait until this
/// returns to zero so they never cover a chest being opened.
final ValueNotifier<int> rewardDialogsOpen = ValueNotifier(0);

Future<T?> showRewardDialog<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool barrierDismissible = true,
}) async {
  rewardDialogsOpen.value++;
  try {
    return await showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: builder,
    );
  } finally {
    rewardDialogsOpen.value--;
  }
}

/// Shared frame for full-screen moments: a dialog with confetti behind it.
class CelebrationFrame extends StatelessWidget {
  const CelebrationFrame({
    super.key,
    required this.accent,
    required this.children,
    this.confetti = true,
    this.action = 'Keep reading',
  });
  final Color accent;
  final List<Widget> children;
  final bool confetti;
  final String action;

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    children: [
      if (confetti) const Positioned.fill(child: ConfettiBurst()),
      Dialog(
        backgroundColor: panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(color: accent.withValues(alpha: .4)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...children,
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(action),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// Pops [child] in with an elastic overshoot.
class _Bounce extends StatelessWidget {
  const _Bounce({required this.child, this.from = .3});
  final Widget child;
  final double from;
  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: reduce ? 1 : from, end: 1),
      duration: reduce ? Duration.zero : const Duration(milliseconds: 1100),
      curve: Curves.elasticOut,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}

class LevelUpDialog extends StatelessWidget {
  const LevelUpDialog({super.key, required this.level, this.sequence});
  final int level;

  /// Set when this level also advanced the Beyonder Sequence.
  final int? sequence;

  @override
  Widget build(BuildContext context) {
    final ascended = sequence != null;
    final rank = ascended ? sequenceNames[9 - sequence!] : null;
    final accent = ascended ? const Color(0xffb28dff) : gold;
    return CelebrationFrame(
      accent: accent,
      children: [
        LightRays(
          color: accent,
          size: 180,
          child: _Bounce(
            child: Container(
              width: 92,
              height: 92,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [accent, Color.lerp(accent, ink, .55)!],
                ),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: .45),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: Text(
                '$level',
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
          ),
        ),
        Text(
          ascended ? 'SEQUENCE $sequence REACHED' : 'LEVEL UP',
          style: TextStyle(
            color: accent,
            fontSize: 12,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          ascended ? rank! : 'Level $level · ${levelTitle(level)}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Text(
          ascended
              ? 'The potion is digested. You advanced along the pathway to Sequence $sequence: $rank.'
              : 'Every page brings you closer to the next Sequence. ${levelCost(level)} XP to Level ${level + 1}.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 13, height: 1.5),
        ),
      ],
    );
  }
}

class AchievementsDialog extends StatelessWidget {
  const AchievementsDialog({super.key, required this.unlocked});
  final List<Achievement> unlocked;

  @override
  Widget build(BuildContext context) => CelebrationFrame(
    accent: gold,
    children: [
      Text(
        unlocked.length == 1
            ? 'ACHIEVEMENT UNLOCKED'
            : '${unlocked.length} ACHIEVEMENTS UNLOCKED',
        style: const TextStyle(
          color: gold,
          fontSize: 12,
          letterSpacing: 2,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 18),
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: SingleChildScrollView(
          child: Column(
            children: [
              for (var i = 0; i < unlocked.length; i++)
                PopIn(
                  delay: 120 + i * 140,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Shine(
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  gold.withValues(alpha: .34),
                                  gold.withValues(alpha: .08),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(17),
                              border: Border.all(
                                color: gold.withValues(alpha: .6),
                              ),
                            ),
                            child: Icon(
                              unlocked[i].icon,
                              color: gold,
                              size: 26,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                unlocked[i].title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                unlocked[i].description,
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}

/// The daily mystery chest: it wobbles until tapped, then bursts open over
/// rotating light and reveals the reward.
class ChestDialog extends StatefulWidget {
  const ChestDialog({super.key, required this.open});

  /// Opens the chest in the store; the dialog animates the result.
  final Future<ChestReward?> Function() open;
  @override
  State<ChestDialog> createState() => _ChestDialogState();
}

class _ChestDialogState extends State<ChestDialog>
    with TickerProviderStateMixin {
  late final AnimationController _wobble = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  ChestReward? reward;
  bool opening = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ambientMotion(context) && reward == null && !_wobble.isAnimating) {
      _wobble.repeat();
    }
  }

  @override
  void dispose() {
    _wobble.dispose();
    _burst.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    if (opening || reward != null) return;
    setState(() => opening = true);
    unawaited(HapticFeedback.mediumImpact());
    final result = await widget.open();
    if (!mounted) return;
    _wobble.stop();
    if (result == null) {
      Navigator.pop(context);
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _burst.value = 1;
    } else {
      await _burst.forward();
    }
    if (!mounted) return;
    unawaited(HapticFeedback.heavyImpact());
    setState(() => reward = result);
  }

  @override
  Widget build(BuildContext context) {
    final r = reward;
    final color = r == null ? gold : rarityColors[r.rarity]!;
    return Stack(
      alignment: Alignment.center,
      children: [
        if (r != null)
          Positioned.fill(
            child: ConfettiBurst(
              colors: [color, gold, Colors.white, color.withValues(alpha: .7)],
              count: r.rarity == 'legendary' ? 120 : 70,
            ),
          ),
        Dialog(
          backgroundColor: panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: color.withValues(alpha: .45)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  r == null
                      ? 'MYSTERY CHEST'
                      : '${r.rarity.toUpperCase()} CHEST',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _open,
                  child: LightRays(
                    color: color,
                    size: 210,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_wobble, _burst]),
                      builder: (context, _) {
                        // Wobble in bursts: shake for the first 40% of a cycle.
                        final w = _wobble.value < .4
                            ? math.sin(_wobble.value / .4 * math.pi * 6) *
                                  (1 - _wobble.value / .4) *
                                  .12
                            : 0.0;
                        final b = Curves.easeIn.transform(_burst.value);
                        if (r != null) return _RewardReveal(reward: r);
                        return Transform.rotate(
                          angle: w,
                          child: Transform.scale(
                            scale: 1 + .35 * b,
                            child: Opacity(
                              opacity: (1 - b).clamp(0, 1),
                              child: Icon(
                                Icons.inventory_2_rounded,
                                size: 96,
                                color: Color.lerp(gold, Colors.white, b * .6),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    r == null
                        ? 'You met your daily goal. Tap the chest to open it.'
                        : r.freeze
                        ? '+${r.xp} XP and a streak freeze'
                        : '+${r.xp} XP',
                    key: ValueKey(r == null),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: r == null ? muted : Colors.white,
                      fontSize: r == null ? 13 : 18,
                      fontWeight: r == null ? FontWeight.w400 : FontWeight.w600,
                    ),
                  ),
                ),
                if (r != null) ...[
                  const SizedBox(height: 6),
                  const Text(
                    'A new chest appears every day you meet your goal.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: r == null
                      ? FilledButton.icon(
                          onPressed: opening ? null : _open,
                          icon: const Icon(Icons.lock_open_rounded, size: 18),
                          label: const Text('Open chest'),
                        )
                      : FilledButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Collect'),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RewardReveal extends StatelessWidget {
  const _RewardReveal({required this.reward});
  final ChestReward reward;
  @override
  Widget build(BuildContext context) {
    final color = rarityColors[reward.rarity]!;
    return _Bounce(
      from: .2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt_rounded, size: 46, color: color),
              CountUp(
                reward.xp,
                format: (n) => '+$n',
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w700,
                  color: color,
                  shadows: [
                    Shadow(color: color.withValues(alpha: .6), blurRadius: 18),
                  ],
                ),
              ),
            ],
          ),
          if (reward.freeze)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.ac_unit, color: Color(0xff9fc2dd), size: 22),
                  SizedBox(width: 6),
                  Text(
                    '+1 freeze',
                    style: TextStyle(
                      color: Color(0xff9fc2dd),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class WeeklyRewardDialog extends StatelessWidget {
  const WeeklyRewardDialog({super.key, required this.tier});
  final WeeklyTier tier;
  @override
  Widget build(BuildContext context) => CelebrationFrame(
    accent: tier.color,
    action: 'Collect',
    children: [
      LightRays(
        color: tier.color,
        size: 180,
        child: _Bounce(
          child: Icon(Icons.emoji_events_rounded, size: 88, color: tier.color),
        ),
      ),
      Text(
        '${tier.name.toUpperCase()} WEEK',
        style: TextStyle(
          color: tier.color,
          fontSize: 12,
          letterSpacing: 2,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      CountUp(
        tier.rewardXp,
        format: (n) => '+$n XP',
        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w600),
      ),
      if (tier.freeze)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            '+1 streak freeze',
            style: TextStyle(
              color: Color(0xff9fc2dd),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      const SizedBox(height: 10),
      Text(
        'You earned ${tier.multiplier}× your daily goal this week.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: muted, fontSize: 13),
      ),
    ],
  );
}
