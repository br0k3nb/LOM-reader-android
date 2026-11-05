import 'dart:async';
import 'package:flutter/material.dart';
import 'design.dart';
import 'habit_store.dart';
import 'motion.dart';

/// A small, non-interactive overlay in the reader: each XP award floats up
/// as "+N XP" beside a goal ring, then the whole thing fades away so it
/// never sits over the text for long.
class ReaderXpHud extends StatefulWidget {
  const ReaderXpHud({super.key, required this.habits});
  final HabitStore habits;
  @override
  State<ReaderXpHud> createState() => _ReaderXpHudState();
}

class _ReaderXpHudState extends State<ReaderXpHud>
    with SingleTickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  Timer? _hide;
  bool visible = false;
  XpGain? gain;
  bool goalBurst = false;
  int _burstKey = 0;

  @override
  void initState() {
    super.initState();
    widget.habits.gains.addListener(_onGain);
  }

  @override
  void dispose() {
    widget.habits.gains.removeListener(_onGain);
    _hide?.cancel();
    _float.dispose();
    super.dispose();
  }

  void _onGain() {
    final next = widget.habits.gains.value;
    if (next == null || !mounted || !widget.habits.readerHud) return;
    final crossed =
        widget.habits.goalMetToday &&
        widget.habits.todayXp - next.xp < widget.habits.goalTargetXp;
    setState(() {
      gain = next;
      visible = true;
      if (crossed) {
        goalBurst = true;
        _burstKey++;
      }
    });
    if (MediaQuery.disableAnimationsOf(context)) {
      _float.value = 1;
    } else {
      _float.forward(from: 0);
    }
    _hide?.cancel();
    _hide = Timer(Duration(milliseconds: crossed ? 4200 : 2800), () {
      if (mounted) setState(() => visible = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = gain;
    final habits = widget.habits;
    final session = habits.session();
    final met = habits.goalMetToday;
    final tier = streakTier(habits.currentStreak());
    final reduce = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: reduce ? Duration.zero : const Duration(milliseconds: 420),
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, .3),
          duration: reduce ? Duration.zero : const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomRight,
            children: [
              if (goalBurst)
                Positioned(
                  right: -60,
                  bottom: -40,
                  width: 260,
                  height: 260,
                  child: ConfettiBurst(key: ValueKey(_burstKey), count: 40),
                ),
              Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
                decoration: BoxDecoration(
                  color: panel.withValues(alpha: .94),
                  borderRadius: BorderRadius.circular(50),
                  border: Border.all(
                    color: (met ? const Color(0xff80bea4) : gold).withValues(
                      alpha: .35,
                    ),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GlowRing(
                      value: habits.todayGoalProgress,
                      size: 38,
                      stroke: 4,
                      colors: met
                          ? const [Color(0xff4f8f74), Color(0xff9fe0c4)]
                          : const [Color(0xffb89a5c), Color(0xffffe2a3)],
                      child: Icon(
                        met ? Icons.check_rounded : Icons.local_fire_department,
                        size: 18,
                        color: met ? const Color(0xff80bea4) : tier.color,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedBuilder(
                          animation: _float,
                          builder: (context, _) {
                            final t = Curves.easeOutBack.transform(
                              _float.value.clamp(0, 1),
                            );
                            return Transform.translate(
                              offset: Offset(0, 8 * (1 - t)),
                              child: Opacity(
                                opacity: _float.value.clamp(0, 1),
                                child: Text(
                                  g == null
                                      ? ''
                                      : g.chapter
                                      ? '+${g.xp} XP · chapter done'
                                      : '+${g.xp} XP',
                                  style: const TextStyle(
                                    color: gold,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 2),
                        Text(
                          met
                              ? 'Goal complete · ${habits.todayXp} XP'
                              : '${habits.todayXp}/${habits.goalTargetXp} XP today',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                    if (g != null && g.bonusPct > 0) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (session?.focus == true
                                      ? const Color(0xffb28dff)
                                      : tier.color)
                                  .withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Text(
                          '${session?.focus == true ? 'FOCUS ' : ''}×${(1 + g.bonusPct / 100).toStringAsFixed(2)}',
                          style: TextStyle(
                            color: session?.focus == true
                                ? const Color(0xffb28dff)
                                : tier.color,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
