import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'celebrations.dart';
import 'design.dart';
import 'habit_store.dart';
import 'models.dart';
import 'motion.dart';

const frost = Color(0xff9fc2dd);
const sage = Color(0xff80bea4);
const ember = Color(0xffe8a54b);
const mystic = Color(0xffb28dff);
const _cellEmpty = Color(0xff1a252d);
const _cellBorder = Color(0xff26343f);
const _dim = Color(0xff4b5a66);

const _goldBar = [Color(0xffb89a5c), Color(0xffffe2a3)];
const _sageBar = [Color(0xff4f8f74), Color(0xff9fe0c4)];
const _mysticBar = [Color(0xff7a5cc4), Color(0xffd2bcff)];

const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _shortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

String _thousands(int n) {
  final s = '$n';
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

/// "1h 05m", "42m" or "0m".
String formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m';
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}

/// Opens today's mystery chest with its reveal animation.
Future<void> showChest(BuildContext context, HabitStore habits) =>
    showRewardDialog<void>(
      context,
      (_) => ChestDialog(open: habits.openChest),
      barrierDismissible: false,
    );

/// The Duolingo-style motivation home: streak, rewards, daily goal and
/// quests, Sequence rank, the journey through each novel, insights,
/// records, weekly activity, heatmap and calendar, and achievements.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({
    super.key,
    required this.habits,
    this.onOpenSettings,
    this.editions = const [],
  });
  final HabitStore habits;
  final VoidCallback? onOpenSettings;

  /// The catalog, for journey progress through each novel.
  final List<Edition> editions;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: habits,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) {
    final rescue = habits.streakRescue();
    final quests = habits.todayQuests;
    final questsDone = quests.where((q) => q.done).length;
    final unlocked = habits.unlockedAchievements.toSet();
    final next = habits.nextAchievements();
    final waiting = habits.rewardsWaiting();

    return ListView(
      key: const PageStorageKey('progress'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        MotionEntry(child: StreakHero(habits: habits)),
        if (rescue != null)
          MotionEntry(delay: 40, child: _RescueCard(rescue: rescue)),
        SectionLabel(
          'Rewards',
          trailing: waiting > 0
              ? Text(
                  '$waiting ready',
                  style: const TextStyle(
                    color: gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                )
              : null,
        ),
        MotionEntry(delay: 60, child: _ChestCard(habits: habits)),
        MotionEntry(delay: 80, child: _WeeklyCard(habits: habits)),
        const SectionLabel('Today'),
        MotionEntry(delay: 100, child: _goalCard()),
        SectionLabel(
          'Daily quests',
          trailing: Text(
            '$questsDone/${quests.length}',
            style: TextStyle(
              color: questsDone == quests.length ? sage : muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        MotionEntry(
          delay: 120,
          child: _QuestsCard(
            quests: quests,
            claimed: habits.questBonusClaimedToday,
          ),
        ),
        const SectionLabel('Level'),
        MotionEntry(delay: 140, child: _levelCard()),
        if (editions.isNotEmpty) ...[
          const SectionLabel('Your journey'),
          MotionEntry(
            delay: 150,
            child: _JourneyCard(habits: habits, editions: editions),
          ),
        ],
        const SectionLabel('Insights'),
        MotionEntry(delay: 160, child: _InsightsCard(habits: habits)),
        const SectionLabel('Records'),
        MotionEntry(delay: 170, child: _recordsCard()),
        const SectionLabel('This week'),
        MotionEntry(delay: 180, child: _weekCard(context)),
        const SectionLabel('Reading heatmap'),
        MotionEntry(
          delay: 190,
          child: ReaderPanel(child: _Heatmap(habits: habits)),
        ),
        const SectionLabel('Streak calendar'),
        MotionEntry(
          delay: 200,
          child: ReaderPanel(child: _StreakGrid(days: habits.calendarWeeks(5))),
        ),
        if (next.isNotEmpty) ...[
          const SectionLabel('Almost there'),
          MotionEntry(
            delay: 220,
            child: ReaderPanel(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Column(
                children: [
                  for (final a in next)
                    _NextAchievementTile(
                      achievement: a,
                      current: habits.achievementProgress(a),
                      onTap: () => _showAchievement(context, a, false),
                    ),
                ],
              ),
            ),
          ),
        ],
        SectionLabel(
          'Achievements · ${unlocked.length}/${achievements.length}',
        ),
        MotionEntry(
          delay: 240,
          child: ReaderPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GlowBar(
                  value: unlocked.length / achievements.length,
                  colors: _goldBar,
                  shimmer: true,
                ),
                for (final category in AchievementCategory.values) ...[
                  const SizedBox(height: 18),
                  _categoryHeader(category, unlocked),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 6.0;
                      final columns =
                          ((constraints.maxWidth + gap) / (72 + gap))
                              .floor()
                              .clamp(3, 8);
                      final width =
                          (constraints.maxWidth - gap * (columns - 1)) /
                          columns;
                      final inCategory = [
                        for (final a in achievements)
                          if (a.category == category) a,
                      ];
                      return Wrap(
                        spacing: gap,
                        runSpacing: 16,
                        children: [
                          for (var i = 0; i < inCategory.length; i++)
                            PopIn(
                              delay: 260 + (i * 35).clamp(0, 300),
                              child: _AchievementBadge(
                                achievement: inCategory[i],
                                width: width,
                                unlocked: unlocked.contains(inCategory[i].id),
                                progress:
                                    habits.achievementProgress(inCategory[i]) /
                                    inCategory[i].target,
                                onTap: () => _showAchievement(
                                  context,
                                  inCategory[i],
                                  unlocked.contains(inCategory[i].id),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Text(
            'Pages earn 2 XP · chapters earn 25 XP · finishing all daily quests earns a $questBonusXp XP bonus. '
            'Your flame tier multiplies XP (Flame +10%, Blaze +20%, Inferno +35%, Eternal +50%), and reading '
            '$focusMinutes minutes in one sitting enters focus for another +$focusBonusPct%. '
            'Meet your goal to unlock a daily mystery chest; reach 3×, 5× and 7× your goal in a week for bronze, silver and gold. '
            'A banked streak freeze bridges a missed day automatically. Missed more than you could cover? '
            'Earn $rescueGoalMultiplier× your goal on the day you come back to rescue the streak.',
            style: TextStyle(color: muted, fontSize: 11, height: 1.6),
          ),
        ),
      ],
    );
  }

  Widget _categoryHeader(AchievementCategory category, Set<String> unlocked) {
    final inCategory = achievements.where((a) => a.category == category);
    final count = inCategory.where((a) => unlocked.contains(a.id)).length;
    return Row(
      children: [
        Expanded(
          child: Text(
            achievementCategoryLabels[category]!,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
        Text(
          '$count/${inCategory.length}',
          style: TextStyle(
            color: count == inCategory.length ? gold : muted,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  void _showAchievement(BuildContext context, Achievement a, bool unlocked) {
    final current = habits.achievementProgress(a);
    final on = habits.achievementUnlockedOn(a.id);
    final timeMetric =
        a.metric == 'totalSeconds' || a.metric == 'longestSession';
    String fmt(int n) => timeMetric ? formatDuration(n) : _thousands(n);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: panel,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopIn(
                child: Shine(
                  active: unlocked,
                  child: _BadgeIcon(
                    achievement: a,
                    unlocked: unlocked,
                    size: 84,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                a.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                a.description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, fontSize: 13),
              ),
              const SizedBox(height: 18),
              if (unlocked)
                StatusPill(
                  on == null ? 'Unlocked' : 'Unlocked ${_shortDate(on)}',
                  icon: Icons.verified,
                  ready: true,
                )
              else ...[
                GlowBar(value: current / a.target, height: 8, colors: _goldBar),
                const SizedBox(height: 8),
                Text(
                  '${fmt(current)} / ${fmt(a.target)}',
                  style: const TextStyle(color: muted, fontSize: 12),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                achievementCategoryLabels[a.category]!,
                style: const TextStyle(color: _dim, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _goalCard() {
    final stats = habits.dayStats(habits.todayKey);
    final goal = dailyGoals[habits.goal]!;
    final goalMet = habits.goalMetToday;
    final remaining = goal.xp - habits.todayXp;
    final goalStreak = habits.currentGoalStreak();
    final session = habits.session();
    final bonus = habits.currentBonusPct();
    return ReaderPanel(
      accent: goalMet,
      child: Column(
        children: [
          Row(
            children: [
              GlowRing(
                value: habits.todayGoalProgress,
                size: 92,
                colors: goalMet ? _sageBar : _goldBar,
                child: goalMet
                    ? const PopIn(
                        child: Icon(Icons.check_rounded, color: sage, size: 38),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CountUp(
                            stats['xp'] as int,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '/ ${goal.xp} XP',
                            style: const TextStyle(color: muted, fontSize: 10),
                          ),
                        ],
                      ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Today's goal",
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${goal.label} · ${goal.xp} XP · ${stats['pages']} ${stats['pages'] == 1 ? 'page' : 'pages'} · ${stats['chapters']} ${stats['chapters'] == 1 ? 'chapter' : 'chapters'}',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      goalMet
                          ? 'Goal complete with ${habits.todayXp} XP. Come back tomorrow to keep it going.'
                          : '$remaining XP to go — about ${(remaining / (xpPerPage * (100 + bonus) / 100)).ceil()} pages.',
                      style: const TextStyle(fontSize: 12, height: 1.5),
                    ),
                    if (goalStreak > 1) ...[
                      const SizedBox(height: 8),
                      StatusPill(
                        '$goalStreak days in a row on goal',
                        icon: Icons.event_available,
                        ready: true,
                      ),
                    ],
                    if (onOpenSettings != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: onOpenSettings,
                          child: const Text('Change goal in Settings'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _cellEmpty,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _cellBorder),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      session?.focus == true
                          ? Icons.center_focus_strong
                          : Icons.timer_outlined,
                      size: 18,
                      color: session?.focus == true ? mystic : gold,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        session == null
                            ? '${formatDuration(stats['seconds'] as int)} read today'
                            : session.focus
                            ? 'In focus · +$focusBonusPct% XP this session'
                            : 'Session ${formatDuration(session.seconds)} · focus in ${(focusMinutes - session.seconds ~/ 60).clamp(1, focusMinutes)}m',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (bonus > 0)
                      Text(
                        '×${(1 + bonus / 100).toStringAsFixed(2)} XP',
                        style: const TextStyle(
                          color: gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                  ],
                ),
                if (session != null) ...[
                  const SizedBox(height: 8),
                  GlowBar(
                    value: session.focusProgress,
                    height: 5,
                    colors: _mysticBar,
                    shimmer: session.focus,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _levelCard() {
    final level = habits.level;
    final rank = habits.sequence;
    final xpToNext = level.xpForNextLevel - level.xpIntoLevel;
    return ReaderPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      gold.withValues(alpha: .28),
                      gold.withValues(alpha: .06),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: gold.withValues(alpha: .35)),
                ),
                child: CountUp(
                  level.level,
                  style: const TextStyle(
                    color: gold,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Level ${level.level} · ${level.title}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    CountUp(
                      habits.totalXp,
                      format: (n) => '${_thousands(n)} XP in total',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GlowBar(value: level.progress, colors: _goldBar),
          const SizedBox(height: 8),
          Text(
            '$xpToNext XP to Level ${level.level + 1} · ${levelTitle(level.level + 1)}',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  mystic.withValues(alpha: .14),
                  mystic.withValues(alpha: .03),
                ],
              ),
              border: Border.all(color: mystic.withValues(alpha: .28)),
            ),
            child: Row(
              children: [
                LivingFlame(
                  color: mystic,
                  size: 54,
                  intensity: .3,
                  icon: Icons.science_outlined,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SEQUENCE ${rank.sequence}',
                        style: const TextStyle(
                          color: mystic,
                          fontSize: 10,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        rank.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      GlowBar(
                        value: rank.progress,
                        height: 5,
                        colors: _mysticBar,
                        shimmer: rank.progress > .8,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        rank.nextName == null
                            ? 'The pinnacle of the pathway.'
                            : 'Digesting the potion · Sequence ${rank.sequence - 1}: ${rank.nextName}',
                        style: const TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordsCard() {
    final records = [
      (
        Icons.local_fire_department,
        ember,
        habits.longestStreak,
        'Longest streak',
        false,
      ),
      (
        Icons.event_available,
        sage,
        habits.longestGoalStreak,
        'Best goal run',
        false,
      ),
      (Icons.flag_outlined, gold, habits.goalDays, 'Goal days', false),
      (Icons.bolt, gold, habits.bestDayXp, 'Best day XP', false),
      (
        Icons.auto_stories_outlined,
        gold,
        habits.totalPages,
        'Pages read',
        false,
      ),
      (Icons.done_all, gold, habits.totalChapters, 'Chapters', false),
      (Icons.hourglass_bottom, mystic, habits.totalSeconds, 'Time read', true),
      (
        Icons.self_improvement,
        mystic,
        habits.longestSession,
        'Longest sitting',
        true,
      ),
      (Icons.task_alt, sage, habits.questDays, 'Quest days', false),
      (
        Icons.inventory_2_outlined,
        gold,
        habits.chestsOpened,
        'Chests opened',
        false,
      ),
      (Icons.whatshot_outlined, ember, habits.bonusXp, 'Bonus XP', false),
      (Icons.ac_unit, frost, habits.freezesUsed, 'Freezes used', false),
    ];
    return ReaderPanel(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 480 ? 4 : 2;
          final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (icon, color, value, label, time) in records)
                Container(
                  width: width,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _cellEmpty,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _cellBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 20, color: color),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CountUp(
                              value,
                              format: time ? formatDuration : _thousands,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _weekCard(BuildContext context) {
    final week = habits.weekly;
    final target = habits.goalTargetXp;
    final maxXp = week.fold<int>(0, (m, d) => d.xp > m ? d.xp : m);
    final ceiling = (maxXp > target ? maxXp : target).toDouble();
    final reduce = MediaQuery.disableAnimationsOf(context);
    return ReaderPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, color: gold, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'XP earned',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              CountUp(
                week.fold<int>(0, (sum, d) => sum + d.xp),
                format: (n) => '$n XP',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 64 + MediaQuery.textScalerOf(context).scale(46),
            child: Stack(
              children: [
                // Dashed goal line across the bars.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom:
                      8 +
                      MediaQuery.textScalerOf(context).scale(18) +
                      target / ceiling * 64,
                  child: Row(
                    children: [
                      for (var i = 0; i < 40; i++)
                        Expanded(
                          child: Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            color: i.isEven
                                ? sage.withValues(alpha: .45)
                                : Colors.transparent,
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < week.length; i++)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              week[i].xp == 0 ? '' : '${week[i].xp}',
                              style: TextStyle(
                                fontSize: 10,
                                color: week[i].today ? gold : muted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: reduce ? 1 : 0, end: 1),
                              duration: reduce
                                  ? Duration.zero
                                  : Duration(milliseconds: 600 + i * 90),
                              curve: Curves.easeOutCubic,
                              builder: (context, t, _) {
                                final met = week[i].xp >= target;
                                final colors = met
                                    ? (week[i].today
                                          ? _sageBar
                                          : [
                                              sage.withValues(alpha: .4),
                                              sage.withValues(alpha: .7),
                                            ])
                                    : (week[i].today
                                          ? _goldBar
                                          : [
                                              gold.withValues(alpha: .25),
                                              gold.withValues(alpha: .45),
                                            ]);
                                return Container(
                                  height: ((week[i].xp / ceiling * 64) * t)
                                      .clamp(3.0, 64.0),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: colors,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: week[i].today
                                        ? [
                                            BoxShadow(
                                              color: colors.last.withValues(
                                                alpha: .35,
                                              ),
                                              blurRadius: 10,
                                            ),
                                          ]
                                        : null,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Text(
                              week[i].label,
                              style: TextStyle(
                                fontSize: 11,
                                color: week[i].today ? gold : muted,
                                fontWeight: week[i].today
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _Legend(color: gold, label: 'Below goal'),
              _Legend(color: sage, label: 'Goal met'),
            ],
          ),
        ],
      ),
    );
  }
}

/// The big flame: streak count, flame tier, XP multiplier, today's status,
/// this week's strip, and progress to the next milestone.
class StreakHero extends StatelessWidget {
  const StreakHero({super.key, required this.habits});
  final HabitStore habits;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final streak = habits.currentStreak(now: now);
    final tier = streakTier(streak);
    final activeToday = habits.activeOn(now: now);
    final next = nextStreakMilestone(streak);
    final previous = previousStreakMilestone(streak);
    final span = next - previous;
    final hoursLeft = DateTime(
      now.year,
      now.month,
      now.day + 1,
    ).difference(now).inHours;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tierBonus = tierXpBonus[tier.name] ?? 0;
    final tierIndex = streakTiers.indexOf(tier);
    final nextTier = tierIndex + 1 < streakTiers.length
        ? streakTiers[tierIndex + 1]
        : null;

    final (statusIcon, statusColor, statusText) = activeToday
        ? (
            Icons.check_circle,
            sage,
            streak == 1
                ? 'Streak started today — see you tomorrow'
                : 'Streak extended today',
          )
        : streak > 0
        ? (
            Icons.schedule,
            ember,
            hoursLeft <= 1
                ? 'Less than an hour left to keep your streak'
                : 'Read today to keep it · ${hoursLeft}h left',
          )
        : (Icons.play_circle_outline, muted, 'Read a page to start a streak');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: RadialGradient(
          center: const Alignment(0, -.45),
          radius: 1.1,
          colors: [
            Color.lerp(panel, tier.color, streak > 0 ? .16 : .04)!,
            panel,
            const Color(0xff121b22),
          ],
          stops: const [0, .55, 1],
        ),
        border: Border.all(
          color: tier.color.withValues(alpha: streak > 0 ? .32 : .15),
        ),
      ),
      child: Column(
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _Chip(
                icon: Icons.local_fire_department,
                color: tier.color,
                label: tier.name.toUpperCase(),
                tooltip:
                    'Flame tiers: Spark 1+, Flame 7+ (+10% XP), Blaze 30+ (+20%), Inferno 100+ (+35%), Eternal 365+ (+50%)',
              ),
              if (tierBonus > 0)
                _Chip(
                  icon: Icons.bolt,
                  color: gold,
                  label: '+$tierBonus%',
                  tooltip:
                      'Your ${tier.name} flame adds $tierBonus% to all XP you earn.',
                ),

              _Chip(
                icon: Icons.ac_unit,
                color: frost,
                label: '× ${habits.freezes}',
                tooltip:
                    'Streak freezes protect missed days automatically. Earn one every $freezeEveryStreak streak days, from chests or gold weeks (max $maxFreezes).',
              ),
            ],
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            key: ValueKey('flame-$streak-$activeToday'),
            tween: Tween(begin: reduceMotion ? 1 : .7, end: 1),
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 900),
            curve: Curves.elasticOut,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: LivingFlame(
              color: tier.color,
              size: 124,
              lit: streak > 0,
              intensity: (streak / 100).clamp(.25, 1).toDouble(),
              icon: activeToday || streak == 0
                  ? Icons.local_fire_department
                  : Icons.local_fire_department_outlined,
            ),
          ),
          CountUp(
            streak,
            duration: const Duration(milliseconds: 1200),
            style: const TextStyle(
              fontSize: 64,
              height: 1,
              fontWeight: FontWeight.w300,
              letterSpacing: -2,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'DAY STREAK',
            style: TextStyle(
              color: gold,
              fontSize: 12,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Pulse(
            active: !activeToday && streak > 0,
            color: ember,
            radius: 50,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, size: 15, color: statusColor),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          _WeekStrip(
            days: habits.calendarWeeks(1, now: now),
            color: tier.color,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  streak >= next
                      ? ''
                      : '${next - streak} ${next - streak == 1 ? 'day' : 'days'} to $next',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ),
              Icon(Icons.emoji_events_outlined, size: 14, color: tier.color),
              const SizedBox(width: 4),
              Text(
                '$next-day milestone',
                style: TextStyle(
                  color: tier.color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          GlowBar(
            value: span <= 0 ? 0 : (streak - previous) / span,
            colors: [Color.lerp(tier.color, ink, .3)!, tier.color],
          ),
          if (nextTier != null) ...[
            const SizedBox(height: 10),
            Text(
              '${nextTier.minDays - streak} more ${nextTier.minDays - streak == 1 ? 'day' : 'days'} to ${nextTier.name}'
              '${(tierXpBonus[nextTier.name] ?? 0) > 0 ? ' · +${tierXpBonus[nextTier.name]}% XP' : ''}',
              style: TextStyle(
                color: nextTier.color.withValues(alpha: .9),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Today's mystery chest: locked until the goal is met, then pulsing to be
/// opened, then a countdown to tomorrow's.
class _ChestCard extends StatelessWidget {
  const _ChestCard({required this.habits});
  final HabitStore habits;
  @override
  Widget build(BuildContext context) {
    final available = habits.chestAvailable();
    final opened = habits.data['chestOpenedOn'] == habits.todayKey;
    final now = DateTime.now();
    final hours = DateTime(
      now.year,
      now.month,
      now.day + 1,
    ).difference(now).inHours;
    final card = ReaderPanel(
      margin: available ? EdgeInsets.zero : const EdgeInsets.only(bottom: 16),
      accent: available,
      padding: const EdgeInsets.all(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: available
            ? () {
                HapticFeedback.lightImpact();
                showChest(context, habits);
              }
            : null,
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: available
                  ? LightRays(
                      color: gold,
                      size: 64,
                      child: const Icon(
                        Icons.inventory_2_rounded,
                        color: gold,
                        size: 36,
                      ),
                    )
                  : Icon(
                      opened ? Icons.inventory_2_outlined : Icons.lock_outline,
                      color: opened ? sage : _dim,
                      size: 34,
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    available
                        ? 'Mystery chest ready!'
                        : opened
                        ? 'Chest opened'
                        : 'Daily mystery chest',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    available
                        ? 'Tap to open. It may hold bonus XP or a streak freeze.'
                        : opened
                        ? 'A new chest unlocks tomorrow · ${hours}h'
                        : 'Meet today\'s goal to unlock it · ${(habits.goalTargetXp - habits.todayXp).clamp(0, 9999)} XP to go',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  if (!available && !opened) ...[
                    const SizedBox(height: 8),
                    GlowBar(
                      value: habits.todayGoalProgress,
                      height: 5,
                      colors: _goldBar,
                    ),
                  ],
                ],
              ),
            ),
            if (available) const Icon(Icons.chevron_right_rounded, color: gold),
          ],
        ),
      ),
    );
    return available
        ? Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Pulse(child: Shine(child: card)),
          )
        : card;
  }
}

/// This week's challenge: a bar with bronze, silver and gold stops, each
/// claimable once reached.
class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard({required this.habits});
  final HabitStore habits;

  Future<void> _claim(BuildContext context, int tier) async {
    HapticFeedback.mediumImpact();
    final result = await habits.claimWeekly(tier);
    if (result != null && context.mounted) {
      await showRewardDialog<void>(
        context,
        (_) => WeeklyRewardDialog(tier: result),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = habits.weeklyChallenge();
    final daysLeft = c.ends.difference(DateTime.now()).inDays + 1;
    final nextTier = c.nextTier;
    return ReaderPanel(
      accent: c.claimableCount > 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_outlined, color: gold, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Weekly challenge',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
              Text(
                daysLeft <= 1 ? 'Ends tonight' : '$daysLeft days left',
                style: TextStyle(
                  color: daysLeft <= 1 ? ember : muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          CountUp(
            c.xp,
            format: (n) => nextTier == null
                ? '$n XP this week · gold reached'
                : '$n XP this week · ${c.targets[nextTier] - n} to ${weeklyTiers[nextTier].name.toLowerCase()}',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          GlowBar(
            value: c.progress,
            height: 10,
            colors: _goldBar,
            shimmer: c.claimableCount > 0,
            markers: [for (final t in c.targets) t / c.targets.last],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < weeklyTiers.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: _tier(context, c, i)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _tier(BuildContext context, WeeklyChallenge c, int i) {
    final tier = weeklyTiers[i];
    final claimed = c.claimed.contains(i);
    final claimable = c.claimable(i);
    final content = Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: claimable ? tier.color.withValues(alpha: .14) : _cellEmpty,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: claimable || claimed
              ? tier.color.withValues(alpha: .55)
              : _cellBorder,
        ),
      ),
      child: Column(
        children: [
          Icon(
            claimed ? Icons.verified_rounded : Icons.emoji_events_rounded,
            color: c.reached(i) ? tier.color : _dim,
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            tier.name,
            style: TextStyle(
              color: c.reached(i) ? Colors.white : muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            claimed
                ? 'Claimed'
                : claimable
                ? 'Tap to claim'
                : '${c.targets[i]} XP',
            style: TextStyle(
              color: claimable ? tier.color : muted,
              fontSize: 10,
              fontWeight: claimable ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '+${tier.rewardXp} XP',
                style: TextStyle(
                  color: claimable ? Colors.white70 : muted,
                  fontSize: 10,
                ),
              ),
              if (tier.freeze) ...[
                const SizedBox(width: 3),
                const Icon(Icons.ac_unit, size: 11, color: frost),
              ],
            ],
          ),
        ],
      ),
    );
    if (!claimable) return content;
    return Pulse(
      color: tier.color,
      radius: 16,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _claim(context, i),
        child: Shine(child: content),
      ),
    );
  }
}

/// How far into each novel the reader has come, and when they will finish
/// at their recent pace.
class _JourneyCard extends StatelessWidget {
  const _JourneyCard({required this.habits, required this.editions});
  final HabitStore habits;
  final List<Edition> editions;

  @override
  Widget build(BuildContext context) {
    final pace = habits.insights().chaptersPerDay;
    final books = <String>[];
    for (final e in editions) {
      if (!books.contains(e.book)) books.add(e.book);
    }
    return ReaderPanel(
      child: Column(
        children: [
          for (var b = 0; b < books.length; b++) ...[
            if (b > 0) const Divider(height: 30, color: _cellBorder),
            _book(books[b], pace),
          ],
        ],
      ),
    );
  }

  Widget _book(String book, double pace) {
    final inBook = editions.where((e) => e.book == book).toList();
    final reference = inBook.reduce(
      (a, b) => a.chapters.length >= b.chapters.length ? a : b,
    );
    final total = reference.chapters.length;
    final done = habits.completedChapters(book);
    final count = done.length.clamp(0, total);
    final fraction = total == 0 ? 0.0 : count / total;
    String? volume;
    if (done.isNotEmpty) {
      final furthest = done.reduce((a, b) => a > b ? a : b);
      volume = reference.chapter(furthest)?.category;
    }
    final remaining = total - count;
    String projection;
    if (remaining <= 0) {
      projection = 'Finished. A true Beyonder of this story.';
    } else if (pace <= 0) {
      projection = 'Finish a chapter to see when you will reach the end.';
    } else {
      final days = (remaining / pace).ceil();
      final date = DateTime.now().add(Duration(days: days));
      projection = days > 3650
          ? 'Read a little more each day to bring the finish line closer.'
          : 'At ${pace.toStringAsFixed(1)} chapters a day you finish ${_months[date.month - 1]} ${date.day}, ${date.year}';
    }
    final nextMark = [
      .1,
      .25,
      .5,
      .75,
      .9,
      1.0,
    ].firstWhere((m) => fraction < m, orElse: () => 1.0);
    final toMark = (nextMark * total).ceil() - count;
    final title = book == 'lotm'
        ? 'Lord of the Mysteries'
        : 'Circle of Inevitability';
    final colors = book == 'lotm'
        ? const [Color(0xff6f8f9a), Color(0xffb7d3dc)]
        : const [Color(0xff9a6f86), Color(0xffe0b7cc)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              book == 'lotm'
                  ? Icons.menu_book_rounded
                  : Icons.hourglass_bottom_rounded,
              color: colors.last,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            CountUp(
              (fraction * 1000).round(),
              format: (n) => '${(n / 10).toStringAsFixed(1)}%',
              style: TextStyle(
                color: colors.last,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        GlowBar(
          value: fraction,
          height: 8,
          colors: colors,
          markers: const [.25, .5, .75],
        ),
        const SizedBox(height: 8),
        Text(
          '$count of $total chapters${volume == null ? '' : ' · $volume'}',
          style: const TextStyle(fontSize: 12),
        ),
        if (remaining > 0 && toMark > 0) ...[
          const SizedBox(height: 3),
          Text(
            '$toMark ${toMark == 1 ? 'chapter' : 'chapters'} to ${(nextMark * 100).round()}%',
            style: TextStyle(
              color: colors.last,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 3),
        Text(
          projection,
          style: const TextStyle(color: muted, fontSize: 11, height: 1.4),
        ),
      ],
    );
  }
}

class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.habits});
  final HabitStore habits;
  @override
  Widget build(BuildContext context) {
    final i = habits.insights();
    final rows = [
      (
        Icons.calendar_today_outlined,
        'Active days',
        '${i.activeDays} of the last 30',
      ),
      (
        Icons.bolt,
        'Average active day',
        '${i.averageXp} XP · ${i.averageMinutes} min',
      ),
      (
        Icons.wb_twilight,
        'You read most in',
        i.favoritePeriod ?? 'Not enough data yet',
      ),
      (Icons.event, 'Strongest day', i.bestWeekday ?? 'Not enough data yet'),
      (
        Icons.speed,
        'Recent pace',
        '${i.chaptersPerDay.toStringAsFixed(1)} chapters a day',
      ),
    ];
    return ReaderPanel(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        children: [
          for (var r = 0; r < rows.length; r++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  Icon(rows[r].$1, size: 18, color: gold),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      rows[r].$2,
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      rows[r].$3,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
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

/// Eighteen weeks of reading as a contribution-style grid; brighter cells
/// mean more XP relative to the daily goal.
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.habits});
  final HabitStore habits;
  static const weeks = 18;

  @override
  Widget build(BuildContext context) {
    final days = habits.calendarWeeks(weeks);
    final goal = habits.goalTargetXp;
    final active = days.where((d) => d.xp > 0).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$active active days',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              'Last $weeks weeks',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 3.0;
            final cell = ((constraints.maxWidth - gap * (weeks - 1)) / weeks)
                .clamp(6.0, 22.0);
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var w = 0; w < weeks; w++)
                  Column(
                    children: [
                      for (var d = 0; d < 7; d++)
                        Padding(
                          padding: EdgeInsets.only(bottom: d == 6 ? 0 : gap),
                          child: PopIn(
                            delay: (w * 18).clamp(0, 400),
                            child: _heatCell(days[w * 7 + d], goal, cell),
                          ),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Text('Less', style: TextStyle(color: muted, fontSize: 10)),
            const SizedBox(width: 6),
            for (final level in [0, 1, 2, 3, 4]) ...[
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: _heatColor(level),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 3),
            ],
            const SizedBox(width: 3),
            const Text('More', style: TextStyle(color: muted, fontSize: 10)),
          ],
        ),
      ],
    );
  }

  static Color _heatColor(int level) => switch (level) {
    0 => _cellEmpty,
    1 => gold.withValues(alpha: .22),
    2 => gold.withValues(alpha: .45),
    3 => gold.withValues(alpha: .75),
    _ => const Color(0xffffe2a3),
  };

  Widget _heatCell(DayActivity day, int goal, double size) {
    final ratio = goal <= 0 ? 0 : day.xp / goal;
    final level = day.xp <= 0
        ? 0
        : ratio < .5
        ? 1
        : ratio < 1
        ? 2
        : ratio < 2
        ? 3
        : 4;
    final color = day.future
        ? Colors.transparent
        : day.state == DayState.frozen
        ? frost.withValues(alpha: .55)
        : day.state == DayState.repaired
        ? sage.withValues(alpha: .55)
        : _heatColor(level);
    return Tooltip(
      message: day.future
          ? _shortDate(day.date)
          : '${_shortDate(day.date)} · ${day.xp} XP',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(size * .25),
          border: day.future
              ? Border.all(color: _cellBorder.withValues(alpha: .4))
              : null,
          boxShadow: level == 4
              ? [BoxShadow(color: gold.withValues(alpha: .4), blurRadius: 4)]
              : null,
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.color,
    required this.label,
    required this.tooltip,
  });
  final IconData icon;
  final Color color;
  final String label;
  final String tooltip;
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    triggerMode: TooltipTriggerMode.tap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(50),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Monday–Sunday circles for the current week.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days, required this.color});
  final List<DayActivity> days;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final today = dateKey(DateTime.now());
    return Row(
      children: [
        for (final day in days)
          Expanded(
            child: Column(
              children: [
                Text(
                  _weekdayLetters[day.date.weekday - 1],
                  style: TextStyle(
                    color: day.key == today ? gold : muted,
                    fontSize: 11,
                    fontWeight: day.key == today
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 6),
                _dot(day, day.key == today),
              ],
            ),
          ),
      ],
    );
  }

  Widget _dot(DayActivity day, bool isToday) {
    final (fill, icon, iconColor) = switch (day.state) {
      DayState.active => (color, Icons.local_fire_department, ink),
      DayState.frozen => (frost, Icons.ac_unit, ink),
      DayState.repaired => (sage, Icons.healing, ink),
      DayState.none => (_cellEmpty, null, muted),
    };
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: day.future ? Colors.transparent : fill,
        border: Border.all(
          color: isToday
              ? gold
              : day.future
              ? _cellBorder
              : (day.state == DayState.none ? _cellBorder : fill),
          width: isToday ? 2 : 1,
        ),
      ),
      alignment: Alignment.center,
      child: icon == null ? null : Icon(icon, size: 17, color: iconColor),
    );
  }
}

class _RescueCard extends StatelessWidget {
  const _RescueCard({required this.rescue});
  final StreakRescue rescue;
  @override
  Widget build(BuildContext context) {
    final left = rescue.targetXp - rescue.currentXp;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Pulse(
        color: ember,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [const Color(0xff3a2622), panel],
            ),
            border: Border.all(color: ember.withValues(alpha: .35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.healing, color: ember, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Rescue your ${rescue.length}-day streak',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'You missed ${rescue.gap.length} ${rescue.gap.length == 1 ? 'day' : 'days'} without a freeze. '
                'Earn ${rescue.targetXp} XP today ($rescueGoalMultiplier× your goal) and the streak comes back. '
                'The offer ends at midnight.',
                style: const TextStyle(fontSize: 12, height: 1.5, color: muted),
              ),
              const SizedBox(height: 12),
              GlowBar(
                value: rescue.progress,
                height: 8,
                colors: const [Color(0xffb3622e), ember],
                shimmer: true,
              ),
              const SizedBox(height: 6),
              Text(
                '${rescue.currentXp}/${rescue.targetXp} XP · $left to go',
                style: const TextStyle(color: ember, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestsCard extends StatelessWidget {
  const _QuestsCard({required this.quests, required this.claimed});
  final List<DailyQuest> quests;
  final bool claimed;
  @override
  Widget build(BuildContext context) => ReaderPanel(
    accent: claimed,
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
    child: Column(
      children: [
        for (final quest in quests) ...[
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: (quest.done ? sage : gold).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  transitionBuilder: (child, a) =>
                      ScaleTransition(scale: a, child: child),
                  child: Icon(
                    quest.done ? Icons.check_rounded : quest.icon,
                    key: ValueKey(quest.done),
                    size: 19,
                    color: quest.done ? sage : gold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            quest.title,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: quest.done ? muted : Colors.white,
                            ),
                          ),
                        ),
                        Text(
                          '${quest.current.clamp(0, quest.target)}/${quest.target}',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    GlowBar(
                      value: quest.progress,
                      height: 5,
                      colors: quest.done ? _sageBar : _goldBar,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            Icon(
              claimed ? Icons.redeem : Icons.card_giftcard_outlined,
              size: 18,
              color: claimed ? sage : muted,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                claimed
                    ? 'All quests done · +$questBonusXp XP bonus earned'
                    : 'Finish all three for a +$questBonusXp XP bonus · new quests tomorrow',
                style: TextStyle(color: claimed ? sage : muted, fontSize: 11),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _StreakGrid extends StatelessWidget {
  const _StreakGrid({required this.days});
  final List<DayActivity> days;

  @override
  Widget build(BuildContext context) {
    final first = days.first.date;
    final last = days.last.date;
    final range = first.month == last.month
        ? '${_months[first.month - 1]} ${first.year}'
        : '${_months[first.month - 1]} – ${_months[last.month - 1]} ${last.year}';
    final weeks = days.length ~/ 7;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          range,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final label in _weekdayLetters)
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        for (var row = 0; row < weeks; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: PopIn(
                      delay: row * 50 + col * 20,
                      child: _cell(days[row * 7 + col]),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        const Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _Legend(color: gold, label: 'Goal met'),
            _Legend(color: Color(0xff7a6c4c), label: 'Read'),
            _Legend(color: frost, label: 'Freeze'),
            _Legend(color: sage, label: 'Rescued'),
            _Legend(color: _cellBorder, label: 'Missed'),
          ],
        ),
      ],
    );
  }

  Widget _cell(DayActivity day) {
    final (color, border, textColor) = switch (day.state) {
      DayState.active when day.goalMet => (gold, gold, ink),
      DayState.active => (
        const Color(0xff7a6c4c),
        const Color(0xff7a6c4c),
        Colors.white,
      ),
      DayState.frozen => (frost.withValues(alpha: .8), frost, ink),
      DayState.repaired => (sage.withValues(alpha: .8), sage, ink),
      DayState.none => (_cellEmpty, _cellBorder, muted),
    };
    final today = day.key == dateKey(DateTime.now());
    final detail = switch (day.state) {
      DayState.frozen => 'Streak freeze used',
      DayState.repaired => 'Streak rescued',
      _ =>
        '${day.xp} XP · ${day.pages} pages${day.goalMet ? ' · goal met' : ''}',
    };
    return Center(
      child: Tooltip(
        message: day.future
            ? _shortDate(day.date)
            : '${_shortDate(day.date)}\n$detail',
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: day.future ? Colors.transparent : color,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: today
                  ? Colors.white.withValues(alpha: .8)
                  : day.future
                  ? _cellBorder.withValues(alpha: .5)
                  : border,
              width: today ? 1.6 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: switch (day.state) {
            DayState.frozen => const Icon(Icons.ac_unit, size: 15, color: ink),
            DayState.repaired => const Icon(
              Icons.healing,
              size: 15,
              color: ink,
            ),
            _ => Text(
              '${day.date.day}',
              style: TextStyle(
                fontSize: 10,
                color: day.future ? _dim : textColor,
                fontWeight: day.state == DayState.active
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          },
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: muted, fontSize: 11)),
    ],
  );
}

class _NextAchievementTile extends StatelessWidget {
  const _NextAchievementTile({
    required this.achievement,
    required this.current,
    required this.onTap,
  });
  final Achievement achievement;
  final int current;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: _BadgeIcon(achievement: achievement, unlocked: false, size: 42),
    title: Text(
      achievement.title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: GlowBar(
              value: current / achievement.target,
              height: 5,
              colors: _goldBar,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            achievement.metric == 'totalSeconds' ||
                    achievement.metric == 'longestSession'
                ? '${formatDuration(current)}/${formatDuration(achievement.target)}'
                : '${_thousands(current)}/${_thousands(achievement.target)}',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
    ),
  );
}

class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({
    required this.achievement,
    required this.unlocked,
    this.size = 54,
  });
  final Achievement achievement;
  final bool unlocked;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      gradient: unlocked
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                gold.withValues(alpha: .26),
                gold.withValues(alpha: .08),
              ],
            )
          : null,
      color: unlocked ? null : _cellEmpty,
      borderRadius: BorderRadius.circular(size * .3),
      border: Border.all(
        color: unlocked ? gold.withValues(alpha: .5) : _cellBorder,
      ),
    ),
    alignment: Alignment.center,
    child: Icon(
      achievement.icon,
      size: size * .45,
      color: unlocked ? gold : _dim,
    ),
  );
}

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({
    required this.achievement,
    required this.unlocked,
    required this.progress,
    required this.onTap,
    this.width = 82,
  });
  final Achievement achievement;
  final bool unlocked;
  final double progress;
  final double width;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: unlocked
        ? '${achievement.title}, unlocked. ${achievement.description}'
        : '${achievement.title}, locked. ${achievement.description}',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Shine(
                  active: unlocked,
                  child: _BadgeIcon(
                    achievement: achievement,
                    unlocked: unlocked,
                  ),
                ),
                if (!unlocked)
                  const Positioned(
                    right: -4,
                    bottom: -4,
                    child: CircleAvatar(
                      radius: 9,
                      backgroundColor: panel,
                      child: Icon(Icons.lock, size: 11, color: _dim),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              achievement.title,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10,
                height: 1.3,
                color: unlocked ? Colors.white : muted,
              ),
            ),
            if (!unlocked && progress > 0) ...[
              const SizedBox(height: 5),
              SizedBox(
                width: 46,
                child: GlowBar(
                  value: progress.clamp(0, 1).toDouble(),
                  height: 3,
                  colors: _goldBar,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Full-screen moment for streak milestones and rescued streaks, shown on
/// the home screen once the reader closes.
class StreakCelebrationDialog extends StatelessWidget {
  const StreakCelebrationDialog({
    super.key,
    required this.days,
    this.repaired = false,
  });
  final int days;
  final bool repaired;

  @override
  Widget build(BuildContext context) {
    final tier = streakTier(days);
    final next = nextStreakMilestone(days);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: ConfettiBurst(
            colors: [tier.color, gold, Colors.white, repaired ? sage : ember],
            count: days >= 100 ? 120 : 80,
          ),
        ),
        Dialog(
          backgroundColor: panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: tier.color.withValues(alpha: .4)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: reduceMotion ? 1 : .3, end: 1),
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 1100),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: LightRays(
                    color: repaired ? sage : tier.color,
                    size: 190,
                    child: LivingFlame(
                      color: repaired ? sage : tier.color,
                      size: 132,
                      intensity: 1,
                      icon: repaired
                          ? Icons.healing
                          : Icons.local_fire_department,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$days',
                  style: const TextStyle(
                    fontSize: 56,
                    height: 1,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  repaired ? 'STREAK RESCUED' : 'DAY STREAK',
                  style: TextStyle(
                    color: repaired ? sage : tier.color,
                    fontSize: 12,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  repaired
                      ? 'You earned double your goal and brought your streak back to life.'
                      : days >= 365
                      ? 'A whole year of reading. The Mist bows to you.'
                      : 'Milestone reached — your flame is now ${tier.name}. Next stop: $next days.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Keep reading'),
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
