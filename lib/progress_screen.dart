import 'package:flutter/material.dart';
import 'design.dart';
import 'habit_store.dart';

const frost = Color(0xff9fc2dd);
const sage = Color(0xff80bea4);
const ember = Color(0xffe8a54b);
const _track = Color(0xff2b3842);
const _cellEmpty = Color(0xff1a252d);
const _cellBorder = Color(0xff26343f);
const _dim = Color(0xff4b5a66);

const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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

/// The Duolingo-style motivation home: streak, rescue, daily goal and
/// quests, level, records, weekly activity, streak calendar, and
/// achievements.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, required this.habits, this.onOpenSettings});
  final HabitStore habits;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final rescue = habits.streakRescue();
    final quests = habits.todayQuests;
    final questsDone = quests.where((q) => q.done).length;
    final unlocked = habits.unlockedAchievements.toSet();
    final next = habits.nextAchievements();

    return ListView(
      key: const PageStorageKey('progress'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        MotionEntry(child: StreakHero(habits: habits)),
        if (rescue != null)
          MotionEntry(delay: 40, child: _RescueCard(rescue: rescue)),
        const SectionLabel('Today'),
        MotionEntry(delay: 70, child: _goalCard()),
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
          delay: 100,
          child: _QuestsCard(
            quests: quests,
            claimed: habits.questBonusClaimedToday,
          ),
        ),
        const SectionLabel('Level'),
        MotionEntry(delay: 130, child: _levelCard()),
        const SectionLabel('Records'),
        MotionEntry(delay: 150, child: _recordsCard()),
        const SectionLabel('This week'),
        MotionEntry(delay: 170, child: _weekCard()),
        const SectionLabel('Streak calendar'),
        MotionEntry(
          delay: 200,
          child: ReaderPanel(
            child: _StreakGrid(days: habits.calendarWeeks(5)),
          ),
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: unlocked.length / achievements.length,
                    minHeight: 6,
                  ),
                ),
                for (final category in AchievementCategory.values) ...[
                  const SizedBox(height: 18),
                  _categoryHeader(category, unlocked),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      const gap = 6.0;
                      final columns =
                          ((constraints.maxWidth + gap) / (72 + gap)).floor().clamp(3, 8);
                      final width =
                          (constraints.maxWidth - gap * (columns - 1)) / columns;
                      return Wrap(
                        spacing: gap,
                        runSpacing: 16,
                        children: [
                          for (final a in achievements)
                            if (a.category == category)
                              _AchievementBadge(
                                achievement: a,
                                width: width,
                                unlocked: unlocked.contains(a.id),
                                progress:
                                    habits.achievementProgress(a) / a.target,
                                onTap: () => _showAchievement(
                                  context,
                                  a,
                                  unlocked.contains(a.id),
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
        Text(
          achievementCategoryLabels[category]!,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const Spacer(),
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
              _BadgeIcon(achievement: a, unlocked: unlocked, size: 84),
              const SizedBox(height: 16),
              Text(
                a.title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
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
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: current / a.target,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_thousands(current)} / ${_thousands(a.target)}',
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
    return ReaderPanel(
      accent: goalMet,
      child: Row(
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: habits.todayGoalProgress),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => CircularProgressIndicator(
                      value: value,
                      strokeWidth: 9,
                      strokeCap: StrokeCap.round,
                      color: goalMet ? sage : gold,
                      backgroundColor: _track,
                    ),
                  ),
                ),
                if (goalMet)
                  const Icon(Icons.check_rounded, color: sage, size: 36)
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${stats['xp']}',
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
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
                      : '$remaining XP to go — about ${(remaining / xpPerPage).ceil()} pages.',
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
    );
  }

  Widget _levelCard() {
    final level = habits.level;
    final xpToNext = level.xpForNextLevel - level.xpIntoLevel;
    return ReaderPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${level.level}',
                  style: const TextStyle(
                    color: gold,
                    fontSize: 18,
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
                    Text(
                      '${_thousands(habits.totalXp)} XP in total',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: level.progress, minHeight: 6),
          ),
          const SizedBox(height: 8),
          Text(
            '$xpToNext XP to Level ${level.level + 1} · ${levelTitle(level.level + 1)}',
            style: const TextStyle(color: muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _recordsCard() {
    final records = [
      (Icons.local_fire_department, ember, '${habits.longestStreak}', 'Longest streak'),
      (Icons.event_available, sage, '${habits.longestGoalStreak}', 'Best goal run'),
      (Icons.flag_outlined, gold, '${habits.goalDays}', 'Goal days'),
      (Icons.bolt, gold, _thousands(habits.bestDayXp), 'Best day XP'),
      (Icons.auto_stories_outlined, gold, _thousands(habits.totalPages), 'Pages read'),
      (Icons.done_all, gold, _thousands(habits.totalChapters), 'Chapters'),
      (Icons.task_alt, sage, '${habits.questDays}', 'Quest days'),
      (Icons.ac_unit, frost, '${habits.freezesUsed}', 'Freezes used'),
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
              for (final (icon, color, value, label) in records)
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
                            Text(
                              value,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: muted, fontSize: 11),
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

  Widget _weekCard() {
    final week = habits.weekly;
    final target = habits.goalTargetXp;
    final maxXp = week.fold<int>(0, (m, d) => d.xp > m ? d.xp : m);
    final ceiling = (maxXp > target ? maxXp : target).toDouble();
    return ReaderPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, color: gold, size: 20),
              const SizedBox(width: 8),
              const Text('XP earned', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                '${week.fold<int>(0, (sum, d) => sum + d.xp)} XP',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 108,
            child: Stack(
              children: [
                // Dashed goal line across the bars.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 26 + target / ceiling * 64,
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
                    for (final day in week)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              day.xp == 0 ? '' : '${day.xp}',
                              style: TextStyle(
                                fontSize: 10,
                                color: day.today ? gold : muted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: (day.xp / ceiling * 64).clamp(3.0, 64.0),
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              decoration: BoxDecoration(
                                color: day.xp >= target
                                    ? (day.today ? sage : sage.withValues(alpha: .55))
                                    : (day.today ? gold : gold.withValues(alpha: .38)),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              day.label,
                              style: TextStyle(
                                fontSize: 11,
                                color: day.today ? gold : muted,
                                fontWeight:
                                    day.today ? FontWeight.w700 : FontWeight.w400,
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

/// The big flame: streak count, flame tier, today's status, this week's
/// strip, and progress to the next milestone.
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
    final hoursLeft = DateTime(now.year, now.month, now.day + 1)
        .difference(now)
        .inHours;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final (statusIcon, statusColor, statusText) = activeToday
        ? (Icons.check_circle, sage, streak == 1
            ? 'Streak started today — see you tomorrow'
            : 'Streak extended today')
        : streak > 0
            ? (Icons.schedule, ember, hoursLeft <= 1
                ? 'Less than an hour left to keep your streak'
                : 'Read today to keep it · ${hoursLeft}h left')
            : (Icons.play_circle_outline, muted, 'Read a page to start a streak');

    return ReaderPanel(
      accent: true,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        children: [
          Row(
            children: [
              _Chip(
                icon: Icons.local_fire_department,
                color: tier.color,
                label: tier.name.toUpperCase(),
                tooltip: 'Flame tiers: Spark 1+, Flame 7+, Blaze 30+, Inferno 100+, Eternal 365+',
              ),
              const Spacer(),
              _Chip(
                icon: Icons.ac_unit,
                color: frost,
                label: '× ${habits.freezes}',
                tooltip:
                    'Streak freezes protect missed days automatically. Earn one every $freezeEveryStreak streak days (max $maxFreezes).',
              ),
            ],
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            key: ValueKey('flame-$streak-$activeToday'),
            tween: Tween(begin: reduceMotion ? 1 : .7, end: 1),
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 900),
            curve: Curves.elasticOut,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 116,
              height: 116,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    tier.color.withValues(alpha: streak > 0 ? .38 : .10),
                    tier.color.withValues(alpha: 0),
                  ],
                ),
              ),
              child: Icon(
                activeToday || streak == 0
                    ? Icons.local_fire_department
                    : Icons.local_fire_department_outlined,
                size: 68,
                color: tier.color,
              ),
            ),
          ),
          Text(
            '$streak',
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
          Container(
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
          const SizedBox(height: 18),
          _WeekStrip(days: habits.calendarWeeks(1, now: now), color: tier.color),
          const SizedBox(height: 18),
          Row(
            children: [
              Text(
                streak >= next ? '' : '${next - streak} ${next - streak == 1 ? 'day' : 'days'} to $next',
                style: const TextStyle(color: muted, fontSize: 11),
              ),
              const Spacer(),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: span <= 0 ? 0 : (streak - previous) / span,
              minHeight: 6,
              color: tier.color,
            ),
          ),
        ],
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
                    fontWeight: day.key == today ? FontWeight.w700 : FontWeight.w400,
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
      child: icon == null
          ? null
          : Icon(icon, size: 17, color: iconColor),
    );
  }
}

class _RescueCard extends StatelessWidget {
  const _RescueCard({required this.rescue});
  final StreakRescue rescue;
  @override
  Widget build(BuildContext context) {
    final left = rescue.targetXp - rescue.currentXp;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: rescue.progress,
              minHeight: 8,
              color: ember,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${rescue.currentXp}/${rescue.targetXp} XP · $left to go',
            style: const TextStyle(color: ember, fontSize: 11),
          ),
        ],
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
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (quest.done ? sage : gold).withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      quest.done ? Icons.check_rounded : quest.icon,
                      size: 19,
                      color: quest.done ? sage : gold,
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
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: quest.progress,
                            minHeight: 5,
                            color: quest.done ? sage : gold,
                          ),
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
                    style: TextStyle(
                      color: claimed ? sage : muted,
                      fontSize: 11,
                    ),
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
                  Expanded(child: _cell(days[row * 7 + col])),
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
      DayState.active => (const Color(0xff7a6c4c), const Color(0xff7a6c4c), Colors.white),
      DayState.frozen => (frost.withValues(alpha: .8), frost, ink),
      DayState.repaired => (sage.withValues(alpha: .8), sage, ink),
      DayState.none => (_cellEmpty, _cellBorder, muted),
    };
    final today = day.key == dateKey(DateTime.now());
    final detail = switch (day.state) {
      DayState.frozen => 'Streak freeze used',
      DayState.repaired => 'Streak rescued',
      _ => '${day.xp} XP · ${day.pages} pages${day.goalMet ? ' · goal met' : ''}',
    };
    return Center(
      child: Tooltip(
        message: day.future ? _shortDate(day.date) : '${_shortDate(day.date)}\n$detail',
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
            DayState.repaired => const Icon(Icons.healing, size: 15, color: ink),
            _ => Text(
                '${day.date.day}',
                style: TextStyle(
                  fontSize: 10,
                  color: day.future ? _dim : textColor,
                  fontWeight:
                      day.state == DayState.active ? FontWeight.w700 : FontWeight.w400,
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: current / achievement.target,
                    minHeight: 5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${_thousands(current)}/${_thousands(achievement.target)}',
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
                  colors: [gold.withValues(alpha: .26), gold.withValues(alpha: .08)],
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
                    _BadgeIcon(achievement: achievement, unlocked: unlocked),
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0, 1).toDouble(),
                        minHeight: 3,
                      ),
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
    return Dialog(
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
              child: Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      tier.color.withValues(alpha: .45),
                      tier.color.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Icon(
                  repaired ? Icons.healing : Icons.local_fire_department,
                  size: 76,
                  color: repaired ? sage : tier.color,
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
              style: const TextStyle(color: muted, fontSize: 13, height: 1.5),
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
    );
  }
}
