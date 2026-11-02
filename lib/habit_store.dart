import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;

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

enum DayState { active, frozen, none }

class DayActivity {
  const DayActivity(this.date, this.pages, this.chapters, this.xp, this.state);
  final DateTime date;
  final int pages, chapters, xp;
  final DayState state;
  String get key => dateKey(date);
}

class Achievement {
  const Achievement(this.id, this.title, this.description, this.icon);
  final String id;
  final String title;
  final String description;
  final IconData icon;
}

const List<Achievement> achievements = [
  Achievement(
    'first-page',
    'First Steps',
    'Read your first page',
    Icons.menu_book_outlined,
  ),
  Achievement(
    'first-chapter',
    'Chapter Complete',
    'Finish a full chapter',
    Icons.done_all,
  ),
  Achievement(
    'xp-100',
    'Warming Up',
    'Earn 100 total XP',
    Icons.bolt,
  ),
  Achievement(
    'xp-500',
    'Committed Reader',
    'Earn 500 total XP',
    Icons.bolt,
  ),
  Achievement(
    'xp-1000',
    'Deep into the Mist',
    'Earn 1,000 total XP',
    Icons.bolt,
  ),
  Achievement(
    'xp-2500',
    'Avid Reader',
    'Earn 2,500 total XP',
    Icons.bolt,
  ),
  Achievement(
    'xp-5000',
    'Walking the Path',
    'Earn 5,000 total XP',
    Icons.auto_awesome,
  ),
  Achievement(
    'chapters-10',
    'Ten Chapters',
    'Finish 10 chapters',
    Icons.library_books_outlined,
  ),
  Achievement(
    'chapters-50',
    'Half the Mystery',
    'Finish 50 chapters',
    Icons.library_books_outlined,
  ),
  Achievement(
    'chapters-100',
    'Century of Chapters',
    'Finish 100 chapters',
    Icons.local_library_outlined,
  ),
  Achievement(
    'streak-3',
    'Three-Day Streak',
    'Read on 3 days in a row',
    Icons.local_fire_department_outlined,
  ),
  Achievement(
    'streak-7',
    'Week of Reading',
    'Reach a 7-day streak',
    Icons.local_fire_department_outlined,
  ),
  Achievement(
    'streak-14',
    'Fortnight Flame',
    'Reach a 14-day streak',
    Icons.local_fire_department_outlined,
  ),
  Achievement(
    'streak-30',
    'Month of the Seer',
    'Reach a 30-day streak',
    Icons.local_fire_department_outlined,
  ),
  Achievement(
    'streak-100',
    'Hundred Days',
    'Reach a 100-day streak',
    Icons.local_fire_department_outlined,
  ),
  Achievement(
    'freezes-2',
    'Ice Keeper',
    'Hold 2 streak freezes at once',
    Icons.ac_unit,
  ),
];

/// Duolingo-style motivation for steady reading: XP, levels, daily goals,
/// streaks with freezes, and achievements. Device-global like bookmarks and
/// reader settings; it never leaves the phone and is not part of account sync
/// or reading backups.
///
/// Activity is measured in the same logical pages (800px) as account sync,
/// with per-day/per-chapter floors so re-reading never double-counts. A day
/// counts as active once at least one page is read. Missed days are bridged
/// automatically by banked streak freezes.
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
        'days': <String, dynamic>{},
        'freezeDates': <String>[],
        'floors': <String, dynamic>{},
        'chaptersCompleted': <String>[],
        'achievements': <String>[],
        'freezeMilestones': <int>[],
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
  ];

  Map<String, dynamic> get _days =>
      Map<String, dynamic>.from(data['days'] as Map? ?? {});
  Set<String> get _freezeDates =>
      Set<String>.from(data['freezeDates'] as List? ?? []);
  Map<String, dynamic> get _floors =>
      Map<String, dynamic>.from(data['floors'] as Map? ?? {});

  int get totalXp => data['totalXp'] as int? ?? 0;
  int get totalPages => data['totalPages'] as int? ?? 0;
  int get totalChapters => data['totalChapters'] as int? ?? 0;
  int get freezes => data['freezes'] as int? ?? 0;
  int get longestStreak => data['longestStreak'] as int? ?? 0;
  String get goal => data['goal'] as String? ?? defaultGoal;
  int get goalTargetXp => goalXp(goal);
  String get reminderTime => data['reminderTime'] as String? ?? defaultReminderTime;
  bool get remindersEnabled => data['remindersEnabled'] == true;
  bool get winBackEnabled => data['winBackEnabled'] == true;
  LevelInfo get level => levelForXp(totalXp);
  List<String> get unlockedAchievements =>
      List<String>.from(data['achievements'] as List? ?? []);

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
    _reconcileFreezes(DateTime.now());
    _updateLongestStreak(DateTime.now());
    _prune(DateTime.now());
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
        };
      }
    }
    final freezeDates = value['freezeDates'];
    if (freezeDates is List) {
      final kept = <String>{};
      for (final raw in freezeDates) {
        if (raw is String && recent(raw)) kept.add(raw);
      }
      next['freezeDates'] = kept.toList()..sort();
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
    final unlocked = value['achievements'];
    if (unlocked is List) {
      final known = <String>{for (final a in achievements) a.id};
      final kept = <String>{};
      for (final raw in unlocked) {
        if (raw is String && known.contains(raw)) kept.add(raw);
      }
      next['achievements'] = kept.toList();
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
    final days = _days;
    final day = Map<String, dynamic>.from(
      days[today] as Map? ?? {'pages': 0, 'chapters': 0, 'xp': 0},
    );
    day['pages'] = (day['pages'] as int? ?? 0) + pages;
    day['chapters'] = (day['chapters'] as int? ?? 0) + (chapterDone ? 1 : 0);
    day['xp'] =
        (day['xp'] as int? ?? 0) + pages * xpPerPage + chapterXp;
    days[today] = day;
    data['days'] = days;
    data['totalPages'] = totalPages + pages;
    data['totalChapters'] = totalChapters + (chapterDone ? 1 : 0);
    data['totalXp'] = totalXp + pages * xpPerPage + chapterXp;

    _reconcileFreezes(at);
    _updateLongestStreak(at);
    _maybeAwardFreeze();
    _evaluateAchievements();

    if (!beforeGoalMet &&
        _goalMetFor(today) &&
        data['goalCelebratedOn'] != today) {
      data['goalCelebratedOn'] = today;
      _celebrations.add('goal');
    }
    final afterLevel = levelForXp(totalXp).level;
    if (afterLevel > beforeLevel) {
      _celebrations.add('level:$afterLevel');
    }
    await persist();
  }

  bool _goalMetFor(String key) {
    final xp = dayStats(key)['xp'] as int;
    return xp >= goalTargetXp;
  }

  Set<String> _activeDates() => _days.keys.toSet();

  /// Walks backwards from [start] (inclusive of active days, skipping frozen
  /// days without counting them) and returns the run length.
  int _runEndingAt(DateTime start, Set<String> freezeDates) {
    var d = DateTime(start.year, start.month, start.day);
    var streak = 0;
    final days = _activeDates();
    // If the starting day itself is neither active nor frozen, the run is 0.
    while (true) {
      final key = dateKey(d);
      if (days.contains(key)) {
        streak++;
        d = d.subtract(const Duration(days: 1));
      } else if (freezeDates.contains(key)) {
        d = d.subtract(const Duration(days: 1));
      } else {
        return streak;
      }
    }
  }

  /// Current streak. A day with no activity neither counts nor breaks the
  /// streak while today is still open; a full missed day without a freeze
  /// ends the run.
  int currentStreak({DateTime? now}) {
    final t = now ?? DateTime.now();
    final d = DateTime(t.year, t.month, t.day);
    final days = _activeDates();
    final freezeDates = _freezeDates;
    final todayActive = days.contains(dateKey(d));
    final anchor = todayActive ? d : d.subtract(const Duration(days: 1));
    if (!todayActive &&
        !days.contains(dateKey(anchor)) &&
        !freezeDates.contains(dateKey(anchor))) {
      return 0;
    }
    return _runEndingAt(anchor, freezeDates);
  }

  /// Spends banked freezes on missed days between the last active day
  /// before today and today itself. Today is excluded so a freshly recorded
  /// reading still triggers the reconcile; freezes are never spent unless
  /// they cover the whole gap, since a streak needs every day bridged.
  void _reconcileFreezes(DateTime now) {
    final days = _activeDates();
    if (days.isEmpty) return;
    final today = DateTime(now.year, now.month, now.day);
    final todayKey = dateKey(today);
    String? previous;
    for (final key in days) {
      if (key == todayKey) continue;
      if (previous == null || key.compareTo(previous) > 0) previous = key;
    }
    if (previous == null) return; // First-ever reading; nothing to bridge.
    final freezeDates = _freezeDates;
    final missed = <String>[];
    var d = parseDateKey(previous)!.add(const Duration(days: 1));
    while (d.isBefore(today)) {
      final key = dateKey(d);
      if (!days.contains(key) && !freezeDates.contains(key)) missed.add(key);
      d = d.add(const Duration(days: 1));
    }
    if (missed.isEmpty) return;
    final available = data['freezes'] as int? ?? 0;
    if (available < missed.length) return; // Streak is lost; freezes remain.
    data['freezes'] = available - missed.length;
    final updated = [...freezeDates, ...missed]..sort();
    data['freezeDates'] = updated;
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
      if (banked < maxFreezes) data['freezes'] = banked + 1;
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
    final freezeDates = _freezeDates.toList()
      ..removeWhere((key) => key.compareTo(cutoffKey) < 0);
    data['freezeDates'] = freezeDates;
    final floors = _floors
      ..removeWhere((key, _) => key.split('/').last.compareTo(cutoffKey) < 0);
    data['floors'] = floors;
  }

  bool _achievementMet(String id) {
    switch (id) {
      case 'first-page':
        return totalPages >= 1;
      case 'first-chapter':
        return totalChapters >= 1;
      case 'xp-100':
        return totalXp >= 100;
      case 'xp-500':
        return totalXp >= 500;
      case 'xp-1000':
        return totalXp >= 1000;
      case 'xp-2500':
        return totalXp >= 2500;
      case 'xp-5000':
        return totalXp >= 5000;
      case 'chapters-10':
        return totalChapters >= 10;
      case 'chapters-50':
        return totalChapters >= 50;
      case 'chapters-100':
        return totalChapters >= 100;
      case 'streak-3':
        return longestStreak >= 3;
      case 'streak-7':
        return longestStreak >= 7;
      case 'streak-14':
        return longestStreak >= 14;
      case 'streak-30':
        return longestStreak >= 30;
      case 'streak-100':
        return longestStreak >= 100;
      case 'freezes-2':
        return freezes >= 2;
      default:
        return false;
    }
  }

  void _evaluateAchievements() {
    final unlocked = List<String>.from(
      data['achievements'] as List? ?? [],
    );
    var changed = false;
    for (final achievement in achievements) {
      if (unlocked.contains(achievement.id)) continue;
      if (!_achievementMet(achievement.id)) continue;
      unlocked.add(achievement.id);
      _celebrations.add('achievement:${achievement.id}');
      changed = true;
    }
    if (changed) data['achievements'] = unlocked;
  }

  /// Celebrations queued since the last call: `goal`, `level:<n>`, or
  /// `achievement:<id>`. The UI shows them once and clears the queue.
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

  /// The last [count] days, oldest first, including today. Days with no
  /// reading are marked [DayState.none]; days bridged by a freeze are marked
  /// [DayState.frozen].
  List<DayActivity> recentDays(int count, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    final freezeDates = _freezeDates;
    final result = <DayActivity>[];
    for (var offset = count - 1; offset >= 0; offset--) {
      final d = today.subtract(Duration(days: offset));
      final key = dateKey(d);
      final stats = dayStats(key);
      final state = (stats['xp'] as int) > 0
          ? DayState.active
          : freezeDates.contains(key)
              ? DayState.frozen
              : DayState.none;
      result.add(
        DayActivity(
          d,
          stats['pages'] as int,
          stats['chapters'] as int,
          stats['xp'] as int,
          state,
        ),
      );
    }
    return result;
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
