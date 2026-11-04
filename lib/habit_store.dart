import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color, IconData, Icons;

const int xpPerPage = 2;
const int xpPerChapter = 25;
const int maxFreezes = 2;
const int freezeEveryStreak = 10;
const String defaultGoal = 'regular';
const String defaultReminderTime = '20:00';
const int retentionDays = 400;

/// Daily goals in XP. One 800px logical page earns [xpPerPage], so the hints
/// translate the target into pages.
const Map<String, ({String label, int xp, String hint})> dailyGoals = {
  'casual': (label: 'Casual', xp: 20, hint: '~10 pages a day'),
  'regular': (label: 'Regular', xp: 50, hint: '~25 pages a day'),
  'serious': (label: 'Serious', xp: 100, hint: '~50 pages a day'),
  'intense': (label: 'Intense', xp: 200, hint: '~100 pages a day'),
};

int goalXp(String goal) => dailyGoals[goal]?.xp ?? dailyGoals[defaultGoal]!.xp;

const List<String> levelTitles = [
  'Newcomer',
  'Page Turner',
  'Chapter Hunter',
  'Lore Keeper',
  'Devoted Reader',
  'Pathwalker',
  'Mist Walker',
  'Seer',
  'Beyonder',
  'Mystic',
];

String levelTitle(int level) => level <= levelTitles.length
    ? levelTitles[level - 1]
    : 'Grand Mystic ${level - levelTitles.length}';

/// XP required to advance from [level] to [level] + 1. Grows linearly so
/// early levels come quickly and later ones take real dedication.
int levelCost(int level) => 100 + 50 * (level - 1);

class LevelInfo {
  const LevelInfo(this.level, this.xpIntoLevel, this.xpForNextLevel);
  final int level;
  final int xpIntoLevel;
  final int xpForNextLevel;
  String get title => levelTitle(level);
  double get progress =>
      xpForNextLevel <= 0 ? 1 : (xpIntoLevel / xpForNextLevel).clamp(0, 1);
}

LevelInfo levelForXp(int totalXp) {
  var level = 1;
  var remaining = totalXp < 0 ? 0 : totalXp;
  while (remaining >= levelCost(level)) {
    remaining -= levelCost(level);
    level++;
  }
  return LevelInfo(level, remaining, levelCost(level));
}

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseDateKey(String key) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
  if (match == null) return null;
  final d = DateTime(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
  );
  return d.year == int.parse(match[1]!) ? d : null;
}

enum DayState { active, frozen, repaired, none }

class DayActivity {
  const DayActivity(
    this.date,
    this.pages,
    this.chapters,
    this.xp,
    this.state, {
    this.goalMet = false,
    this.future = false,
  });
  final DateTime date;
  final int pages, chapters, xp;
  final DayState state;
  final bool goalMet;
  final bool future;
  String get key => dateKey(date);
}

enum AchievementCategory { streak, reading, xp, goals, habits }

const Map<AchievementCategory, String> achievementCategoryLabels = {
  AchievementCategory.streak: 'Streaks',
  AchievementCategory.reading: 'Reading',
  AchievementCategory.xp: 'XP & levels',
  AchievementCategory.goals: 'Goals & quests',
  AchievementCategory.habits: 'Habits',
};

/// An achievement unlocks once [metric] (see [HabitStore.metricValue])
/// reaches [target]. Progress toward locked achievements is shown in the UI.
class Achievement {
  const Achievement(
    this.id,
    this.title,
    this.description,
    this.icon, {
    required this.category,
    required this.metric,
    required this.target,
  });
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final AchievementCategory category;
  final String metric;
  final int target;
}

const List<Achievement> achievements = [
  // Streaks.
  Achievement('streak-3', 'Three-Day Streak', 'Read on 3 days in a row',
      Icons.local_fire_department_outlined,
      category: AchievementCategory.streak, metric: 'longestStreak', target: 3),
  Achievement('streak-7', 'Week of Reading', 'Reach a 7-day streak',
      Icons.local_fire_department_outlined,
      category: AchievementCategory.streak, metric: 'longestStreak', target: 7),
  Achievement('streak-14', 'Fortnight Flame', 'Reach a 14-day streak',
      Icons.local_fire_department_outlined,
      category: AchievementCategory.streak, metric: 'longestStreak', target: 14),
  Achievement('streak-30', 'Month of the Seer', 'Reach a 30-day streak',
      Icons.local_fire_department,
      category: AchievementCategory.streak, metric: 'longestStreak', target: 30),
  Achievement('streak-50', 'Fifty Flames', 'Reach a 50-day streak',
      Icons.local_fire_department,
      category: AchievementCategory.streak, metric: 'longestStreak', target: 50),
  Achievement('streak-100', 'Hundred Days', 'Reach a 100-day streak',
      Icons.whatshot,
      category: AchievementCategory.streak, metric: 'longestStreak', target: 100),
  Achievement('streak-200', 'Unwavering', 'Reach a 200-day streak',
      Icons.whatshot,
      category: AchievementCategory.streak, metric: 'longestStreak', target: 200),
  Achievement('streak-365', 'A Year in the Mist', 'Reach a 365-day streak',
      Icons.emoji_events,
      category: AchievementCategory.streak, metric: 'longestStreak', target: 365),
  Achievement('freezes-2', 'Ice Keeper', 'Hold 2 streak freezes at once',
      Icons.ac_unit,
      category: AchievementCategory.streak, metric: 'freezes', target: 2),
  Achievement('freeze-saved', 'Saved by the Frost',
      'Let a streak freeze protect a missed day', Icons.severe_cold,
      category: AchievementCategory.streak, metric: 'freezesUsed', target: 1),
  Achievement('streak-repaired', 'Phoenix Rising',
      'Rescue a broken streak by earning double your goal', Icons.healing,
      category: AchievementCategory.streak, metric: 'repairs', target: 1),
  Achievement('comeback', 'Welcome Back', 'Return after a week or more away',
      Icons.waving_hand_outlined,
      category: AchievementCategory.streak, metric: 'comebacks', target: 1),
  // Reading volume.
  Achievement('first-page', 'First Steps', 'Read your first page',
      Icons.menu_book_outlined,
      category: AchievementCategory.reading, metric: 'totalPages', target: 1),
  Achievement('pages-100', 'Hundred Pages', 'Read 100 pages',
      Icons.auto_stories_outlined,
      category: AchievementCategory.reading, metric: 'totalPages', target: 100),
  Achievement('pages-1000', 'Thousand Pages', 'Read 1,000 pages',
      Icons.auto_stories,
      category: AchievementCategory.reading, metric: 'totalPages', target: 1000),
  Achievement('pages-5000', 'Tome Devourer', 'Read 5,000 pages',
      Icons.auto_stories,
      category: AchievementCategory.reading, metric: 'totalPages', target: 5000),
  Achievement('first-chapter', 'Chapter Complete', 'Finish a full chapter',
      Icons.done_all,
      category: AchievementCategory.reading, metric: 'totalChapters', target: 1),
  Achievement('chapters-10', 'Ten Chapters', 'Finish 10 chapters',
      Icons.library_books_outlined,
      category: AchievementCategory.reading, metric: 'totalChapters', target: 10),
  Achievement('chapters-50', 'Half the Mystery', 'Finish 50 chapters',
      Icons.library_books_outlined,
      category: AchievementCategory.reading, metric: 'totalChapters', target: 50),
  Achievement('chapters-100', 'Century of Chapters', 'Finish 100 chapters',
      Icons.local_library_outlined,
      category: AchievementCategory.reading, metric: 'totalChapters', target: 100),
  Achievement('chapters-250', 'Sequence Ascension', 'Finish 250 chapters',
      Icons.local_library,
      category: AchievementCategory.reading, metric: 'totalChapters', target: 250),
  Achievement('chapters-500', 'Half a Thousand', 'Finish 500 chapters',
      Icons.local_library,
      category: AchievementCategory.reading, metric: 'totalChapters', target: 500),
  Achievement('chapters-1000', 'The Whole Saga', 'Finish 1,000 chapters',
      Icons.workspace_premium,
      category: AchievementCategory.reading, metric: 'totalChapters', target: 1000),
  Achievement('marathon', 'Marathon Session', 'Read 100 pages in a single day',
      Icons.directions_run,
      category: AchievementCategory.reading, metric: 'bestDayPages', target: 100),
  Achievement('binge', 'Binge Reader', 'Finish 5 chapters in a single day',
      Icons.fast_forward,
      category: AchievementCategory.reading, metric: 'bestDayChapters', target: 5),
  Achievement('two-worlds', 'Two Worlds', 'Finish a chapter of both novels',
      Icons.public,
      category: AchievementCategory.reading, metric: 'novels', target: 2),
  // XP and levels.
  Achievement('xp-100', 'Warming Up', 'Earn 100 total XP', Icons.bolt,
      category: AchievementCategory.xp, metric: 'totalXp', target: 100),
  Achievement('xp-500', 'Committed Reader', 'Earn 500 total XP', Icons.bolt,
      category: AchievementCategory.xp, metric: 'totalXp', target: 500),
  Achievement('xp-1000', 'Deep into the Mist', 'Earn 1,000 total XP',
      Icons.bolt,
      category: AchievementCategory.xp, metric: 'totalXp', target: 1000),
  Achievement('xp-2500', 'Avid Reader', 'Earn 2,500 total XP', Icons.bolt,
      category: AchievementCategory.xp, metric: 'totalXp', target: 2500),
  Achievement('xp-5000', 'Walking the Path', 'Earn 5,000 total XP',
      Icons.auto_awesome,
      category: AchievementCategory.xp, metric: 'totalXp', target: 5000),
  Achievement('xp-10000', 'Ten Thousand Whispers', 'Earn 10,000 total XP',
      Icons.auto_awesome,
      category: AchievementCategory.xp, metric: 'totalXp', target: 10000),
  Achievement('xp-25000', 'Legend of the Mist', 'Earn 25,000 total XP',
      Icons.diamond_outlined,
      category: AchievementCategory.xp, metric: 'totalXp', target: 25000),
  Achievement('level-5', 'Rising Reader', 'Reach level 5', Icons.trending_up,
      category: AchievementCategory.xp, metric: 'level', target: 5),
  Achievement('level-10', 'Ascended Mystic', 'Reach level 10',
      Icons.military_tech,
      category: AchievementCategory.xp, metric: 'level', target: 10),
  // Goals and quests.
  Achievement('goal-1', 'Goal Getter', 'Meet your daily goal',
      Icons.flag_outlined,
      category: AchievementCategory.goals, metric: 'goalDays', target: 1),
  Achievement('goal-7', 'Consistent', 'Meet your daily goal on 7 days',
      Icons.flag,
      category: AchievementCategory.goals, metric: 'goalDays', target: 7),
  Achievement('goal-30', 'Dedicated', 'Meet your daily goal on 30 days',
      Icons.flag,
      category: AchievementCategory.goals, metric: 'goalDays', target: 30),
  Achievement('goal-100', 'Unstoppable', 'Meet your daily goal on 100 days',
      Icons.flag_circle,
      category: AchievementCategory.goals, metric: 'goalDays', target: 100),
  Achievement('perfect-week', 'Perfect Week',
      'Meet your goal 7 days in a row', Icons.event_available,
      category: AchievementCategory.goals, metric: 'longestGoalStreak', target: 7),
  Achievement('perfect-month', 'Perfect Month',
      'Meet your goal 30 days in a row', Icons.calendar_month,
      category: AchievementCategory.goals, metric: 'longestGoalStreak', target: 30),
  Achievement('overachiever', 'Overachiever',
      'Earn double your daily goal in one day', Icons.rocket_launch_outlined,
      category: AchievementCategory.goals, metric: 'overtimeDays', target: 1),
  Achievement('quests-1', 'Quest Complete', 'Finish all daily quests once',
      Icons.task_alt,
      category: AchievementCategory.goals, metric: 'questDays', target: 1),
  Achievement('quests-10', 'Questmaster', 'Finish all daily quests on 10 days',
      Icons.task_alt,
      category: AchievementCategory.goals, metric: 'questDays', target: 10),
  Achievement('quests-50', 'Legendary Quester',
      'Finish all daily quests on 50 days', Icons.stars,
      category: AchievementCategory.goals, metric: 'questDays', target: 50),
  // Reading habits.
  Achievement('early-bird', 'Early Bird', 'Read before 7 AM',
      Icons.wb_twilight,
      category: AchievementCategory.habits, metric: 'earlyBird', target: 1),
  Achievement('night-owl', 'Night Owl', 'Read between 11 PM and 4 AM',
      Icons.nightlight_outlined,
      category: AchievementCategory.habits, metric: 'nightOwl', target: 1),
  Achievement('weekend-warrior', 'Weekend Warrior',
      'Read on both days of a weekend', Icons.weekend_outlined,
      category: AchievementCategory.habits, metric: 'weekends', target: 1),
  Achievement('weekend-10', 'Weekend Devotee',
      'Read on both days of 10 weekends', Icons.weekend,
      category: AchievementCategory.habits, metric: 'weekends', target: 10),
];

Achievement? achievementById(String id) {
  for (final a in achievements) {
    if (a.id == id) return a;
  }
  return null;
}

/// Flame tiers give long streaks a visibly different look.
class StreakTier {
  const StreakTier(this.name, this.minDays, this.color);
  final String name;
  final int minDays;
  final Color color;
}

const List<StreakTier> streakTiers = [
  StreakTier('Unlit', 0, Color(0xff4b5a66)),
  StreakTier('Spark', 1, Color(0xffe8a54b)),
  StreakTier('Flame', 7, Color(0xfff08a3c)),
  StreakTier('Blaze', 30, Color(0xffff6a3d)),
  StreakTier('Inferno', 100, Color(0xffff4d6d)),
  StreakTier('Eternal', 365, Color(0xffb28dff)),
];

StreakTier streakTier(int streak) {
  var tier = streakTiers.first;
  for (final t in streakTiers) {
    if (streak >= t.minDays) tier = t;
  }
  return tier;
}

/// Streak lengths worth a celebration. Past the list, every 100 days counts.
const List<int> streakMilestones = [3, 7, 14, 30, 50, 100, 150, 200, 250, 300, 365];

bool isStreakMilestone(int streak) =>
    streakMilestones.contains(streak) || (streak > 365 && streak % 100 == 0);

int nextStreakMilestone(int streak) {
  for (final m in streakMilestones) {
    if (m > streak) return m;
  }
  return (streak ~/ 100 + 1) * 100;
}

int previousStreakMilestone(int streak) {
  var previous = 0;
  for (final m in streakMilestones) {
    if (m <= streak) previous = m;
  }
  if (streak > 365) {
    final hundred = streak ~/ 100 * 100;
    if (hundred > previous) previous = hundred;
  }
  return previous;
}

/// A broken streak can be rescued on the day you come back by earning this
/// multiple of the daily goal, as long as the gap is short.
const int rescueGoalMultiplier = 2;
const int maxRescueGap = 3;
const int questBonusXp = 15;

class DailyQuest {
  const DailyQuest(this.id, this.title, this.icon, this.current, this.target);
  final String id;
  final String title;
  final IconData icon;
  final int current;
  final int target;
  bool get done => current >= target;
  double get progress => target <= 0 ? 1 : (current / target).clamp(0, 1).toDouble();
}

/// A streak lost on [on] that may still be rescued that same day.
class StreakRescue {
  const StreakRescue(this.length, this.on, this.gap, this.targetXp, this.currentXp);
  final int length;
  final String on;
  final List<String> gap;
  final int targetXp;
  final int currentXp;
  double get progress => (currentXp / targetXp).clamp(0, 1).toDouble();
}

/// Duolingo-style motivation for steady reading: XP, levels, daily goals,
/// daily quests, streaks with freezes and same-day rescues, and
/// achievements. Device-global like bookmarks and reader settings; it never
/// leaves the phone and is not part of account sync or reading backups.
///
/// Activity is measured in the same logical pages (800px) as account sync,
/// with per-day/per-chapter floors so re-reading never double-counts. A day
/// counts as active once at least one page is read. Missed days are bridged
/// automatically by banked streak freezes; a longer gap (up to
/// [maxRescueGap] days) can be rescued on the day you come back by earning
/// [rescueGoalMultiplier]× the daily goal.
class HabitStore extends ChangeNotifier {
  HabitStore(this.file);
  final File file;
  Map<String, dynamic> data = _fresh();
  Future<void> _pending = Future.value();
  bool _disposed = false;
  final List<String> _celebrations = [];

  static Map<String, dynamic> _fresh() => {
        'version': 1,
        'totalXp': 0,
        'totalPages': 0,
        'totalChapters': 0,
        'freezes': 1,
        'longestStreak': 0,
        'goalDays': 0,
        'longestGoalStreak': 0,
        'bestDayPages': 0,
        'bestDayChapters': 0,
        'bestDayXp': 0,
        'freezesUsed': 0,
        'repairs': 0,
        'comebacks': 0,
        'questDays': 0,
        'earlyBird': 0,
        'nightOwl': 0,
        'weekends': 0,
        'overtimeDays': 0,
        'days': <String, dynamic>{},
        'freezeDates': <String>[],
        'repairDates': <String>[],
        'goalDates': <String>[],
        'floors': <String, dynamic>{},
        'chaptersCompleted': <String>[],
        'achievements': <String>[],
        'achievementDates': <String, dynamic>{},
        'freezeMilestones': <int>[],
        'lostStreak': null,
        'goal': defaultGoal,
        'remindersEnabled': true,
        'reminderTime': defaultReminderTime,
        'winBackEnabled': true,
        'goalCelebratedOn': null,
      };

  static const _intKeys = [
    'totalXp',
    'totalPages',
    'totalChapters',
    'freezes',
    'longestStreak',
    'goalDays',
    'longestGoalStreak',
    'bestDayPages',
    'bestDayChapters',
    'bestDayXp',
    'freezesUsed',
    'repairs',
    'comebacks',
    'questDays',
    'earlyBird',
    'nightOwl',
    'weekends',
    'overtimeDays',
  ];

  static final _dateListKeys = ['freezeDates', 'repairDates', 'goalDates'];

  Map<String, dynamic> get _days =>
      Map<String, dynamic>.from(data['days'] as Map? ?? {});
  Set<String> get _freezeDates =>
      Set<String>.from(data['freezeDates'] as List? ?? []);
  Set<String> get _repairDates =>
      Set<String>.from(data['repairDates'] as List? ?? []);
  Set<String> get _goalDates =>
      Set<String>.from(data['goalDates'] as List? ?? []);
  Set<String> get _bridgedDates => {..._freezeDates, ..._repairDates};
  Map<String, dynamic> get _floors =>
      Map<String, dynamic>.from(data['floors'] as Map? ?? {});

  int _int(String key) => data[key] as int? ?? 0;

  int get totalXp => _int('totalXp');
  int get totalPages => _int('totalPages');
  int get totalChapters => _int('totalChapters');
  int get freezes => _int('freezes');
  int get longestStreak => _int('longestStreak');
  int get goalDays => _int('goalDays');
  int get longestGoalStreak => _int('longestGoalStreak');
  int get bestDayPages => _int('bestDayPages');
  int get bestDayChapters => _int('bestDayChapters');
  int get bestDayXp => _int('bestDayXp');
  int get freezesUsed => _int('freezesUsed');
  int get repairs => _int('repairs');
  int get questDays => _int('questDays');
  String get goal => data['goal'] as String? ?? defaultGoal;
  int get goalTargetXp => goalXp(goal);
  String get reminderTime => data['reminderTime'] as String? ?? defaultReminderTime;
  bool get remindersEnabled => data['remindersEnabled'] == true;
  bool get winBackEnabled => data['winBackEnabled'] == true;
  LevelInfo get level => levelForXp(totalXp);
  List<String> get unlockedAchievements =>
      List<String>.from(data['achievements'] as List? ?? []);

  /// The day an achievement was unlocked, when known (older unlocks predate
  /// tracking).
  DateTime? achievementUnlockedOn(String id) {
    final raw = (data['achievementDates'] as Map?)?[id];
    return raw is String ? parseDateKey(raw) : null;
  }

  String get todayKey => dateKey(DateTime.now());

  Map<String, dynamic> dayStats(String key) {
    final day = _days[key];
    if (day is Map) {
      return {
        'pages': (day['pages'] as num?)?.toInt() ?? 0,
        'chapters': (day['chapters'] as num?)?.toInt() ?? 0,
        'xp': (day['xp'] as num?)?.toInt() ?? 0,
      };
    }
    return const {'pages': 0, 'chapters': 0, 'xp': 0};
  }

  int get todayXp => dayStats(todayKey)['xp'] as int;
  int get todayPages => dayStats(todayKey)['pages'] as int;
  int get todayChapters => dayStats(todayKey)['chapters'] as int;
  bool get goalMetToday => todayXp >= goalTargetXp;

  double get todayGoalProgress =>
      (todayXp / goalTargetXp).clamp(0, 1).toDouble();

  /// Whether today already counts toward the streak.
  bool activeOn({DateTime? now}) =>
      _days.containsKey(dateKey(now ?? DateTime.now()));

  /// Most recent day with reading activity, if any.
  String? get lastActiveKey {
    final keys = _days.keys.toList()..sort();
    return keys.isEmpty ? null : keys.last;
  }

  Future<void> load() async {
    if (await file.exists()) {
      try {
        data = _validate(jsonDecode(await file.readAsString()));
      } catch (_) {
        try {
          await file.rename('${file.path}.corrupt');
        } catch (_) {
          /* A fresh file is safer than a broken one. */
        }
        data = _fresh();
      }
    }
    final before = jsonEncode(data);
    final now = DateTime.now();
    _reconcileFreezes(now);
    _updateLongestStreak(now);
    _backfillBests();
    _prune(now);
    if (jsonEncode(data) != before) await persist();
    notifyListeners();
  }

  static Map<String, dynamic> _validate(dynamic value) {
    if (value is! Map<String, dynamic> || value['version'] != 1) {
      throw const FormatException('Unsupported habits file.');
    }
    final next = _fresh();
    for (final key in _intKeys) {
      final raw = value[key];
      if (raw is num && raw.isFinite && raw >= 0) {
        next[key] = raw.round();
      }
    }
    next['freezes'] = (next['freezes'] as int).clamp(0, maxFreezes);
    final cutoff = DateTime.now().subtract(const Duration(days: retentionDays));
    bool recent(String key) {
      final d = parseDateKey(key);
      return d != null && !d.isBefore(DateTime(cutoff.year, cutoff.month, cutoff.day));
    }

    final days = value['days'];
    if (days is Map) {
      for (final entry in days.entries) {
        final key = entry.key as String;
        if (!recent(key)) continue;
        final day = entry.value;
        if (day is! Map) continue;
        next['days'][key] = {
          'pages': _posInt(day['pages']),
          'chapters': _posInt(day['chapters']),
          'xp': _posInt(day['xp']),
          if (day['quests'] == true) 'quests': true,
        };
      }
    }
    for (final listKey in _dateListKeys) {
      final raw = value[listKey];
      if (raw is List) {
        final kept = <String>{};
        for (final item in raw) {
          if (item is String && recent(item)) kept.add(item);
        }
        next[listKey] = kept.toList()..sort();
      }
    }
    final floors = value['floors'];
    if (floors is Map) {
      final kept = <String, dynamic>{};
      for (final entry in floors.entries) {
        final key = entry.key as String;
        final datePart = key.split('/').lastOrNull ?? '';
        if (!recent(datePart)) continue;
        if (!RegExp(r'^(lotm|coi)/(webnovel|oldtl|pt-br)/[1-9][0-9]{0,3}/\d{4}-\d{2}-\d{2}$')
            .hasMatch(key)) {
          continue;
        }
        final raw = entry.value;
        if (raw is num && raw.isFinite && raw >= -1) {
          kept[key] = raw.floor().clamp(-1, 5000);
        }
      }
      next['floors'] = kept;
    }
    final completed = value['chaptersCompleted'];
    if (completed is List) {
      final kept = <String>{};
      for (final raw in completed) {
        if (raw is String &&
            RegExp(r'^(lotm|coi)/(webnovel|oldtl|pt-br)/[1-9][0-9]{0,3}$')
                .hasMatch(raw)) {
          kept.add(raw);
        }
      }
      next['chaptersCompleted'] = kept.toList();
    }
    final known = <String>{for (final a in achievements) a.id};
    final unlocked = value['achievements'];
    if (unlocked is List) {
      final kept = <String>{};
      for (final raw in unlocked) {
        if (raw is String && known.contains(raw)) kept.add(raw);
      }
      next['achievements'] = kept.toList();
    }
    final unlockedDates = value['achievementDates'];
    if (unlockedDates is Map) {
      final kept = <String, dynamic>{};
      for (final entry in unlockedDates.entries) {
        if (entry.key is String &&
            known.contains(entry.key) &&
            entry.value is String &&
            parseDateKey(entry.value as String) != null) {
          kept[entry.key as String] = entry.value;
        }
      }
      next['achievementDates'] = kept;
    }
    final milestones = value['freezeMilestones'];
    if (milestones is List) {
      final kept = <int>{};
      for (final raw in milestones) {
        if (raw is num && raw.isFinite && raw >= freezeEveryStreak) {
          kept.add(raw.round());
        }
      }
      next['freezeMilestones'] = kept.toList()..sort();
    }
    final lost = value['lostStreak'];
    if (lost is Map &&
        lost['on'] is String &&
        parseDateKey(lost['on'] as String) != null &&
        lost['length'] is num &&
        (lost['length'] as num) > 0 &&
        lost['gap'] is List) {
      final gap = <String>[
        for (final g in lost['gap'] as List)
          if (g is String && parseDateKey(g) != null) g,
      ];
      if (gap.isNotEmpty && gap.length <= maxRescueGap) {
        next['lostStreak'] = {
          'on': lost['on'],
          'length': (lost['length'] as num).round(),
          'gap': gap,
        };
      }
    }
    final goal = value['goal'];
    if (goal is String && dailyGoals.containsKey(goal)) next['goal'] = goal;
    if (value['remindersEnabled'] is bool) {
      next['remindersEnabled'] = value['remindersEnabled'];
    }
    if (value['winBackEnabled'] is bool) {
      next['winBackEnabled'] = value['winBackEnabled'];
    }
    final time = value['reminderTime'];
    if (time is String && RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(time)) {
      next['reminderTime'] = time;
    }
    final celebrated = value['goalCelebratedOn'];
    if (celebrated is String && parseDateKey(celebrated) != null) {
      next['goalCelebratedOn'] = celebrated;
    }
    return next;
  }

  static int _posInt(dynamic raw) =>
      raw is num && raw.isFinite && raw > 0 ? raw.round() : 0;

  Future<void> persist() {
    final snapshot = jsonEncode(data);
    _pending = _pending.catchError((Object _) {}).then((_) async {
      await file.parent.create(recursive: true);
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(snapshot, flush: true);
      await temp.rename(file.path);
    });
    notifyListeners();
    return _pending;
  }

  /// Records raw scroll offset for a chapter. New logical pages award XP;
  /// pages already counted for this day/chapter are ignored.
  Future<void> recordReading({
    required String edition,
    required int slug,
    num? ratio,
    num scroll = 0,
    DateTime? now,
  }) async {
    if (_disposed) return;
    if (!RegExp(r'^(lotm|coi)/(webnovel|oldtl|pt-br)$').hasMatch(edition) ||
        slug < 1 ||
        slug > 1500) {
      return;
    }
    final at = now ?? DateTime.now();
    final today = dateKey(at);
    final beforeLevel = levelForXp(totalXp).level;
    final beforeGoalMet = _goalMetFor(today);
    final wasActive = _days.containsKey(today);
    final dayXpBefore = dayStats(today)['xp'] as int;
    final previousActive = _lastActiveBefore(today);

    final floors = _floors;
    final floorKey = '$edition/$slug/$today';
    final previous = (floors[floorKey] as num?)?.toInt() ?? -1;
    final current = (scroll / 800).floor().clamp(0, 5000);
    var pages = 0;
    if (current > previous) {
      pages = current - previous;
      floors[floorKey] = current;
    }

    var chapterXp = 0;
    var chapterDone = false;
    if (ratio != null && ratio.isFinite && ratio >= 0.95) {
      final chapterKey = '$edition/$slug';
      final completed = List<dynamic>.from(
        data['chaptersCompleted'] as List? ?? [],
      );
      if (!completed.contains(chapterKey)) {
        completed.add(chapterKey);
        data['chaptersCompleted'] = completed;
        chapterXp = xpPerChapter;
        chapterDone = true;
      }
    }

    if (pages == 0 && !chapterDone) return;

    data['floors'] = floors;
    final gained = pages * xpPerPage + chapterXp;
    _addToDay(today, pages: pages, chapters: chapterDone ? 1 : 0, xp: gained);
    data['totalPages'] = totalPages + pages;
    data['totalChapters'] = totalChapters + (chapterDone ? 1 : 0);
    data['totalXp'] = totalXp + gained;

    _recordTimeOfDay(at);
    if (!wasActive) _recordNewActiveDay(at, previousActive);

    // Quests complete first so their bonus counts toward the goal.
    final quests = questsFor(today);
    final day = _days[today] as Map;
    if (quests.every((q) => q.done) && day['quests'] != true) {
      _addToDay(today, xp: questBonusXp, quests: true);
      data['totalXp'] = totalXp + questBonusXp;
      data['questDays'] = questDays + 1;
      _celebrations.add('quests');
    }

    _reconcileFreezes(at);
    final repaired = _tryRescue(at);
    final streak = currentStreak(now: at);

    if (!beforeGoalMet &&
        _goalMetFor(today) &&
        data['goalCelebratedOn'] != today) {
      data['goalCelebratedOn'] = today;
      data['goalDays'] = goalDays + 1;
      data['goalDates'] = ([..._goalDates, today]..sort());
      final goalRun = _goalRunEndingAt(at);
      if (goalRun > longestGoalStreak) data['longestGoalStreak'] = goalRun;
      _celebrations.add('goal');
    }
    final todayStats = dayStats(today);
    if ((todayStats['xp'] as int) >= goalTargetXp * 2 &&
        dayXpBefore < goalTargetXp * 2) {
      data['overtimeDays'] = _int('overtimeDays') + 1;
    }
    _updateBests(todayStats);

    if (!wasActive) _celebrations.add('streak-extended:$streak');
    if ((!wasActive || repaired) && isStreakMilestone(streak)) {
      _celebrations.add('streak:$streak');
    }

    _updateLongestStreak(at);
    _maybeAwardFreeze();
    _evaluateAchievements(at);

    final afterLevel = levelForXp(totalXp).level;
    if (afterLevel > beforeLevel) {
      _celebrations.add('level:$afterLevel');
    }
    await persist();
  }

  void _addToDay(
    String key, {
    int pages = 0,
    int chapters = 0,
    int xp = 0,
    bool quests = false,
  }) {
    final days = _days;
    final day = Map<String, dynamic>.from(
      days[key] as Map? ?? {'pages': 0, 'chapters': 0, 'xp': 0},
    );
    day['pages'] = (day['pages'] as int? ?? 0) + pages;
    day['chapters'] = (day['chapters'] as int? ?? 0) + chapters;
    day['xp'] = (day['xp'] as int? ?? 0) + xp;
    if (quests) day['quests'] = true;
    days[key] = day;
    data['days'] = days;
  }

  String? _lastActiveBefore(String key) {
    String? best;
    for (final k in _days.keys) {
      if (k.compareTo(key) >= 0) continue;
      if (best == null || k.compareTo(best) > 0) best = k;
    }
    return best;
  }

  void _recordTimeOfDay(DateTime at) {
    if (at.hour < 7 && at.hour >= 4) data['earlyBird'] = 1;
    if (at.hour >= 23 || at.hour < 4) data['nightOwl'] = 1;
  }

  /// Bookkeeping for the first reading of a calendar day: weekends and
  /// returns after a long break.
  void _recordNewActiveDay(DateTime at, String? previousActive) {
    final d = DateTime(at.year, at.month, at.day);
    final days = _days;
    if (d.weekday == DateTime.sunday || d.weekday == DateTime.saturday) {
      final other = d.weekday == DateTime.sunday
          ? d.subtract(const Duration(days: 1))
          : d.add(const Duration(days: 1));
      if (days.containsKey(dateKey(other))) {
        data['weekends'] = _int('weekends') + 1;
      }
    }
    if (previousActive != null) {
      final last = parseDateKey(previousActive)!;
      if (d.difference(last).inDays >= 8) {
        data['comebacks'] = _int('comebacks') + 1;
      }
    }
  }

  void _updateBests(Map<String, dynamic> day) {
    if ((day['pages'] as int) > bestDayPages) data['bestDayPages'] = day['pages'];
    if ((day['chapters'] as int) > bestDayChapters) {
      data['bestDayChapters'] = day['chapters'];
    }
    if ((day['xp'] as int) > bestDayXp) data['bestDayXp'] = day['xp'];
  }

  void _backfillBests() {
    for (final key in _days.keys) {
      _updateBests(dayStats(key));
    }
  }

  bool _goalMetFor(String key) {
    final xp = dayStats(key)['xp'] as int;
    return xp >= goalTargetXp;
  }

  Set<String> _activeDates() => _days.keys.toSet();

  /// Walks backwards from [start] (inclusive of active days, skipping
  /// bridged days without counting them) and returns the run length.
  int _runEndingAt(DateTime start, Set<String> bridged) {
    var d = DateTime(start.year, start.month, start.day);
    var streak = 0;
    final days = _activeDates();
    while (true) {
      final key = dateKey(d);
      if (days.contains(key)) {
        streak++;
        d = d.subtract(const Duration(days: 1));
      } else if (bridged.contains(key)) {
        d = d.subtract(const Duration(days: 1));
      } else {
        return streak;
      }
    }
  }

  int _goalRunEndingAt(DateTime start) {
    final goals = _goalDates;
    var d = DateTime(start.year, start.month, start.day);
    var run = 0;
    while (goals.contains(dateKey(d))) {
      run++;
      d = d.subtract(const Duration(days: 1));
    }
    return run;
  }

  /// Consecutive days (ending today or yesterday) on which the daily goal
  /// was met.
  int currentGoalStreak({DateTime? now}) {
    final t = now ?? DateTime.now();
    final d = DateTime(t.year, t.month, t.day);
    final goals = _goalDates;
    return goals.contains(dateKey(d))
        ? _goalRunEndingAt(d)
        : _goalRunEndingAt(d.subtract(const Duration(days: 1)));
  }

  /// Current streak. A day with no activity neither counts nor breaks the
  /// streak while today is still open; a full missed day without a freeze
  /// ends the run.
  int currentStreak({DateTime? now}) {
    final t = now ?? DateTime.now();
    final d = DateTime(t.year, t.month, t.day);
    final days = _activeDates();
    final bridged = _bridgedDates;
    final todayActive = days.contains(dateKey(d));
    final anchor = todayActive ? d : d.subtract(const Duration(days: 1));
    if (!todayActive &&
        !days.contains(dateKey(anchor)) &&
        !bridged.contains(dateKey(anchor))) {
      return 0;
    }
    return _runEndingAt(anchor, bridged);
  }

  /// Spends banked freezes on missed days between the last active day
  /// before today and today itself. Today is excluded so a freshly recorded
  /// reading still triggers the reconcile; freezes are never spent unless
  /// they cover the whole gap, since a streak needs every day bridged. A gap
  /// the bank cannot cover is remembered as a rescuable lost streak.
  void _reconcileFreezes(DateTime now) {
    final days = _activeDates();
    if (days.isEmpty) return;
    final today = DateTime(now.year, now.month, now.day);
    final todayKey = dateKey(today);
    final previous = _lastActiveBefore(todayKey);
    if (previous == null) return; // First-ever reading; nothing to bridge.
    final bridged = _bridgedDates;
    final missed = <String>[];
    var d = parseDateKey(previous)!.add(const Duration(days: 1));
    while (d.isBefore(today)) {
      final key = dateKey(d);
      if (!days.contains(key) && !bridged.contains(key)) missed.add(key);
      d = d.add(const Duration(days: 1));
    }
    if (missed.isEmpty) return;
    final available = data['freezes'] as int? ?? 0;
    if (available < missed.length) {
      // Streak is lost; freezes remain. Offer a same-day rescue.
      final lostLength = _runEndingAt(parseDateKey(previous)!, bridged);
      final existing = data['lostStreak'];
      if (lostLength >= 2 &&
          missed.length <= maxRescueGap &&
          !(existing is Map && existing['on'] == todayKey)) {
        data['lostStreak'] = {
          'on': todayKey,
          'length': lostLength,
          'gap': missed,
        };
      }
      return;
    }
    data['freezes'] = available - missed.length;
    data['freezesUsed'] = freezesUsed + missed.length;
    final updated = [..._freezeDates, ...missed]..sort();
    data['freezeDates'] = updated;
    _celebrations.add('freeze-used:${missed.length}');
  }

  /// A rescue that can still be earned today, if any.
  StreakRescue? streakRescue({DateTime? now}) {
    final t = now ?? DateTime.now();
    final lost = data['lostStreak'];
    if (lost is! Map || lost['on'] != dateKey(t)) return null;
    final gap = List<String>.from(lost['gap'] as List);
    final bridged = _bridgedDates;
    if (gap.every(bridged.contains)) return null;
    return StreakRescue(
      (lost['length'] as num).toInt(),
      lost['on'] as String,
      gap,
      goalTargetXp * rescueGoalMultiplier,
      dayStats(dateKey(t))['xp'] as int,
    );
  }

  bool _tryRescue(DateTime now) {
    final rescue = streakRescue(now: now);
    if (rescue == null || rescue.currentXp < rescue.targetXp) return false;
    data['repairDates'] = ([..._repairDates, ...rescue.gap]..sort());
    data['repairs'] = repairs + 1;
    data['lostStreak'] = null;
    _celebrations.add('repaired:${currentStreak(now: now)}');
    return true;
  }

  void _updateLongestStreak(DateTime now) {
    final streak = currentStreak(now: now);
    final longest = data['longestStreak'] as int? ?? 0;
    if (streak > longest) data['longestStreak'] = streak;
  }

  /// Every [freezeEveryStreak] streak days earns one freeze, up to
  /// [maxFreezes] banked. Each milestone is awarded only once ever, and only
  /// once the streak has actually reached it.
  void _maybeAwardFreeze() {
    final longest = data['longestStreak'] as int? ?? 0;
    if (longest < freezeEveryStreak) return;
    final awarded = List<int>.from(
      (data['freezeMilestones'] as List? ?? [])
          .whereType<num>()
          .map((n) => n.round()),
    );
    var changed = false;
    for (var milestone = freezeEveryStreak;
        milestone <= longest;
        milestone += freezeEveryStreak) {
      if (awarded.contains(milestone)) continue;
      awarded.add(milestone);
      final banked = data['freezes'] as int? ?? 0;
      if (banked < maxFreezes) {
        data['freezes'] = banked + 1;
        _celebrations.add('freeze-earned');
      }
      changed = true;
    }
    if (changed) {
      awarded.sort();
      data['freezeMilestones'] = awarded;
    }
  }

  void _prune(DateTime now) {
    final cutoff = now.subtract(const Duration(days: retentionDays));
    final cutoffKey = dateKey(cutoff);
    final days = _days;
    days.removeWhere((key, _) => key.compareTo(cutoffKey) < 0);
    data['days'] = days;
    for (final listKey in _dateListKeys) {
      final kept = Set<String>.from(data[listKey] as List? ?? []).toList()
        ..removeWhere((key) => key.compareTo(cutoffKey) < 0)
        ..sort();
      data[listKey] = kept;
    }
    final floors = _floors
      ..removeWhere((key, _) => key.split('/').last.compareTo(cutoffKey) < 0);
    data['floors'] = floors;
    final lost = data['lostStreak'];
    if (lost is Map && lost['on'] != dateKey(now)) data['lostStreak'] = null;
  }

  /// Current value of an achievement metric.
  int metricValue(String metric) {
    switch (metric) {
      case 'level':
        return level.level;
      case 'novels':
        final completed = List<String>.from(
          data['chaptersCompleted'] as List? ?? [],
        );
        return completed.map((c) => c.split('/').first).toSet().length;
      default:
        return _int(metric);
    }
  }

  /// Progress toward an achievement, clamped to its target.
  int achievementProgress(Achievement a) =>
      metricValue(a.metric).clamp(0, a.target);

  /// Locked achievements closest to unlocking, best first.
  List<Achievement> nextAchievements([int count = 3]) {
    final unlocked = unlockedAchievements.toSet();
    final locked = [
      for (final a in achievements)
        if (!unlocked.contains(a.id) && metricValue(a.metric) > 0) a,
    ]..sort((a, b) => (achievementProgress(b) / b.target)
        .compareTo(achievementProgress(a) / a.target));
    return locked.take(count).toList();
  }

  void _evaluateAchievements(DateTime at) {
    final unlocked = List<String>.from(
      data['achievements'] as List? ?? [],
    );
    final dates = Map<String, dynamic>.from(
      data['achievementDates'] as Map? ?? {},
    );
    var changed = false;
    for (final achievement in achievements) {
      if (unlocked.contains(achievement.id)) continue;
      if (metricValue(achievement.metric) < achievement.target) continue;
      unlocked.add(achievement.id);
      dates[achievement.id] = dateKey(at);
      _celebrations.add('achievement:${achievement.id}');
      changed = true;
    }
    if (changed) {
      data['achievements'] = unlocked;
      data['achievementDates'] = dates;
    }
  }

  /// Three quests for [key]: meeting the goal, plus two picked
  /// deterministically from the date so they stay fixed all day. Targets
  /// scale with the daily goal.
  List<DailyQuest> questsFor(String key) {
    final stats = dayStats(key);
    final xp = stats['xp'] as int;
    final pages = stats['pages'] as int;
    final chapters = stats['chapters'] as int;
    final distinct = _floors.keys.where((k) => k.endsWith('/$key')).length;
    final target = goalTargetXp;
    final pageTarget = (target ~/ 4).clamp(5, 60);
    final chapterTarget = target >= 200 ? 2 : 1;
    final distinctTarget = target >= 100 ? 3 : 2;
    final overtime = (target * 3 / 2).round();
    final pool = [
      DailyQuest('pages', 'Read $pageTarget pages', Icons.auto_stories_outlined,
          pages, pageTarget),
      DailyQuest(
          'chapter',
          chapterTarget == 1 ? 'Finish a chapter' : 'Finish $chapterTarget chapters',
          Icons.done_all,
          chapters,
          chapterTarget),
      DailyQuest('distinct', 'Open $distinctTarget different chapters',
          Icons.layers_outlined, distinct, distinctTarget),
      DailyQuest('overtime', 'Earn $overtime XP', Icons.rocket_launch_outlined,
          xp, overtime),
    ];
    final seed = key.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0x7fffffff);
    final first = seed % pool.length;
    final second = (first + 1 + (seed ~/ pool.length) % (pool.length - 1)) %
        pool.length;
    return [
      DailyQuest('goal', 'Meet your daily goal', Icons.flag_outlined, xp, target),
      pool[first],
      pool[second],
    ];
  }

  List<DailyQuest> get todayQuests => questsFor(todayKey);
  bool get questBonusClaimedToday =>
      (_days[todayKey] as Map?)?['quests'] == true;

  /// Celebrations queued since the last call: `goal`, `quests`,
  /// `level:<n>`, `achievement:<id>`, `streak-extended:<n>`, `streak:<n>`
  /// (a milestone), `repaired:<n>`, `freeze-used:<n>` or `freeze-earned`.
  /// The UI shows them once and clears the queue.
  List<String> consumeCelebrations() {
    final pending = List<String>.from(_celebrations);
    _celebrations.clear();
    return pending;
  }

  Future<void> setGoal(String value) async {
    if (!dailyGoals.containsKey(value) || value == goal) return;
    data['goal'] = value;
    await persist();
  }

  Future<void> setReminderTime(String value) async {
    if (!RegExp(r'^([01][0-9]|2[0-3]):[0-5][0-9]$').hasMatch(value)) return;
    data['reminderTime'] = value;
    await persist();
  }

  Future<void> setRemindersEnabled(bool enabled) async {
    data['remindersEnabled'] = enabled;
    await persist();
  }

  Future<void> setWinBackEnabled(bool enabled) async {
    data['winBackEnabled'] = enabled;
    await persist();
  }

  DayActivity _activity(DateTime d, DateTime today) {
    final key = dateKey(d);
    final stats = dayStats(key);
    final state = (stats['xp'] as int) > 0
        ? DayState.active
        : _freezeDates.contains(key)
            ? DayState.frozen
            : _repairDates.contains(key)
                ? DayState.repaired
                : DayState.none;
    return DayActivity(
      d,
      stats['pages'] as int,
      stats['chapters'] as int,
      stats['xp'] as int,
      state,
      goalMet: _goalDates.contains(key),
      future: d.isAfter(today),
    );
  }

  /// The last [count] days, oldest first, including today. Days with no
  /// reading are marked [DayState.none]; days bridged by a freeze or a
  /// rescue are marked [DayState.frozen] / [DayState.repaired].
  List<DayActivity> recentDays(int count, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    return [
      for (var offset = count - 1; offset >= 0; offset--)
        _activity(today.subtract(Duration(days: offset)), today),
    ];
  }

  /// [weeks] full Monday–Sunday weeks ending with the current week, oldest
  /// first. Days after today are flagged [DayActivity.future].
  List<DayActivity> calendarWeeks(int weeks, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final start = monday.subtract(Duration(days: 7 * (weeks - 1)));
    return [
      for (var i = 0; i < weeks * 7; i++)
        _activity(DateTime(start.year, start.month, start.day + i), today),
    ];
  }

  /// Last 7 days (oldest first) with single-letter weekday labels for the
  /// weekly chart.
  List<({String label, int xp, bool today})> get weekly => [
        for (final d in recentDays(7))
          (
            label: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][d.date.weekday - 1],
            xp: d.xp,
            today: d.key == todayKey,
          ),
      ];

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
