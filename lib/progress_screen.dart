import 'package:flutter/material.dart';
import 'design.dart';
import 'habit_store.dart';

const frost = Color(0xff9fc2dd);

/// The Duolingo-style motivation home: streak, daily goal, level, weekly
/// activity, streak calendar, and achievements.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key, required this.habits, this.onOpenSettings});
  final HabitStore habits;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final stats = habits.dayStats(habits.todayKey);
    final week = habits.weekly;
    final days = habits.recentDays(35);
    final unlocked = habits.unlockedAchievements.toSet();
    final goal = dailyGoals[habits.goal]!;
    final level = habits.level;
    final xpToNext = level.xpForNextLevel - level.xpIntoLevel;
    final goalMet = habits.goalMetToday;

    return ListView(
      key: const PageStorageKey('progress'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        MotionEntry(child: _streakHero()),
        const SectionLabel('Today'),
        MotionEntry(
          delay: 70,
          child: ReaderPanel(
            accent: goalMet,
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  height: 84,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: habits.todayGoalProgress,
                        strokeWidth: 9,
                        backgroundColor: const Color(0xff2b3842),
                      ),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              "Today's goal",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          if (goalMet)
                            const Icon(
                              Icons.check_circle,
                              color: Color(0xff80bea4),
                              size: 22,
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${goal.label} · ${goal.xp} XP',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        goalMet
                            ? 'Goal complete. Come back tomorrow to keep the streak.'
                            : '$xpToNext XP to go · ${stats['pages']} pages read',
                        style: const TextStyle(fontSize: 12, height: 1.5),
                      ),
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
          ),
        ),
        const SectionLabel('Level'),
        MotionEntry(
          delay: 120,
          child: ReaderPanel(
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
                      child: const Icon(Icons.auto_awesome, color: gold, size: 22),
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
                            '${habits.totalXp} XP in total',
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
                  child: LinearProgressIndicator(
                    value: level.progress,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$xpToNext XP to Level ${level.level + 1} · ${levelTitle(level.level + 1)}',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
        const SectionLabel('This week'),
        MotionEntry(
          delay: 160,
          child: ReaderPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bolt, color: gold, size: 20),
                    const SizedBox(width: 8),
                    const Text(
                      'XP earned',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
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
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxXp = week.fold<int>(
                        0,
                        (m, d) => d.xp > m ? d.xp : m,
                      );
                      final ceiling = maxXp < 40 ? 40 : maxXp;
                      return Row(
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
                                    height: (day.xp / ceiling * 56)
                                        .clamp(3.0, 56.0),
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: day.today
                                          ? gold
                                          : gold.withValues(alpha: .38),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    day.label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: day.today ? gold : muted,
                                      fontWeight: day.today
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SectionLabel('Last 5 weeks'),
        MotionEntry(
          delay: 200,
          child: ReaderPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StreakGrid(days: days),
                const SizedBox(height: 16),
                const Wrap(
                  spacing: 18,
                  runSpacing: 8,
                  children: [
                    _Legend(color: gold, label: 'Read'),
                    _Legend(color: frost, label: 'Freeze used'),
                    _Legend(color: Color(0xff26343f), label: 'Missed'),
                  ],
                ),
              ],
            ),
          ),
        ),
        SectionLabel(
          'Achievements · ${unlocked.length}/${achievements.length}',
        ),
        MotionEntry(
          delay: 240,
          child: ReaderPanel(
            child: Wrap(
              spacing: 12,
              runSpacing: 18,
              children: [
                for (final achievement in achievements)
                  _AchievementBadge(
                    achievement: achievement,
                    unlocked: unlocked.contains(achievement.id),
                  ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Text(
            'Pages earn 2 XP · chapters earn 25 XP. A streak freezes one missed day automatically. Finish a chapter and come back every day to grow your streak.',
            style: TextStyle(color: muted, fontSize: 11, height: 1.6),
          ),
        ),
      ],
    );
  }

  Widget _streakHero() {
    final streak = habits.currentStreak();
    final freezes = habits.freezes;
    return ReaderPanel(
      accent: true,
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(),
              Tooltip(
                message:
                    'A streak freeze protects one missed day. Earned every 10 streak days.',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: frost.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.ac_unit, size: 15, color: frost),
                      const SizedBox(width: 6),
                      Text(
                        '× $freezes',
                        style: const TextStyle(
                          color: frost,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  const Color(0xff8a5a2b).withValues(alpha: .55),
                  gold.withValues(alpha: .10),
                ],
              ),
            ),
            child: Icon(
              Icons.local_fire_department,
              size: 60,
              color: streak > 0 ? const Color(0xffe8a54b) : const Color(0xff4b5a66),
            ),
          ),
          const SizedBox(height: 14),
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
          const SizedBox(height: 16),
          Wrap(
            spacing: 26,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              Metric('Longest streak', '${habits.longestStreak} days'),
              Metric('Chapters', '${habits.totalChapters}'),
              Metric('Pages read', '${habits.totalPages}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StreakGrid extends StatelessWidget {
  const _StreakGrid({required this.days});
  final List<DayActivity> days;

  @override
  Widget build(BuildContext context) {
    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Column(
      children: [
        Row(
          children: [
            for (final label in weekdays)
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
        for (var row = 0; row < 5; row++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(child: _cell(days[row * 7 + col])),
              ],
            ),
          ),
      ],
    );
  }

  Widget _cell(DayActivity day) {
    final (color, border) = switch (day.state) {
      DayState.active => (gold, gold),
      DayState.frozen => (frost.withValues(alpha: .75), frost),
      DayState.none => (const Color(0xff1a252d), const Color(0xff26343f)),
    };
    final today = day.key == dateKey(DateTime.now());
    return Center(
      child: Tooltip(
        message:
            '${day.key}\n${day.state == DayState.frozen ? 'Streak freeze used' : '${day.xp} XP · ${day.pages} pages'}',
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: today ? Colors.white.withValues(alpha: .7) : border,
              width: today ? 1.4 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: day.state == DayState.frozen
              ? const Icon(Icons.ac_unit, size: 15, color: Color(0xff0c1319))
              : null,
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

class _AchievementBadge extends StatelessWidget {
  const _AchievementBadge({required this.achievement, required this.unlocked});
  final Achievement achievement;
  final bool unlocked;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: unlocked
            ? '${achievement.title} — ${achievement.description}'
            : 'Locked — ${achievement.description}',
        child: SizedBox(
          width: 88,
          child: Column(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: unlocked
                      ? gold.withValues(alpha: .14)
                      : const Color(0xff1a252d),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: unlocked
                        ? gold.withValues(alpha: .4)
                        : const Color(0xff26343f),
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  unlocked ? achievement.icon : Icons.lock_outline,
                  size: 24,
                  color: unlocked ? gold : const Color(0xff4b5a66),
                ),
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
            ],
          ),
        ),
      );
}
