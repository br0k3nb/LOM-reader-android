import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'auth_store.dart';
import 'background_downloads.dart' show writeJson;
import 'habit_store.dart';
import 'reader_api.dart';

// Cross-device habit sync, protocol v1. This is a line-for-line mirror of the
// website's src/lib/habits/sync.ts; test/habit_sync_test.dart replays the
// website's generated vectors (test/fixtures/habit_sync_vectors.json) so both
// sides merge identically.
//
// Each device keeps its full habit record and remembers `base`, the last
// record the server confirmed. Syncing sends `diffDocs(local, base)` with a
// unique id; the server applies it exactly once and returns the merged record,
// which becomes the new base. Changes made during the request are replayed on
// top (`rebaseDoc`).
//
// Counters and per-day totals add up across devices, records take the maximum,
// dated sets are unions (refunding a once-only reward earned on two offline
// devices), and the daily goal is last-writer-wins. Reminder and HUD
// preferences, the bonus rounding carry, today's rescue offer and the reading
// session stay on the device.

const int habitSyncVersion = 1;

const List<String> syncCounters = [
  'totalXp',
  'totalPages',
  'totalChapters',
  'freezes',
  'goalDays',
  'freezesUsed',
  'repairs',
  'comebacks',
  'questDays',
  'weekends',
  'overtimeDays',
  'totalSeconds',
  'focusSessions',
  'chestsOpened',
  'weeklyClaims',
  'weeklyGolds',
  'bonusXp',
  'rewardXp',
];

const List<String> syncMaxima = [
  'longestStreak',
  'longestGoalStreak',
  'bestDayPages',
  'bestDayChapters',
  'bestDayXp',
  'earlyBird',
  'nightOwl',
  'longestSession',
];

const List<String> syncSets = [
  'freezeDates',
  'repairDates',
  'goalDates',
  'chaptersCompleted',
  'achievements',
];

const int floorSyncDays = 7;
const int weekClaimDays = 63;
const int _maxCounter = 1000000000;
const int _maxDayValue = 1000000;
const int _maxSafeInteger = 9007199254740991;

final RegExp _chapterKey = RegExp(
  r'^(lotm|coi)/(webnovel|oldtl|pt-br)/[1-9][0-9]{0,3}$',
);
final RegExp _floorKey = RegExp(
  r'^(lotm|coi)/(webnovel|oldtl|pt-br)/[1-9][0-9]{0,3}/\d{4}-\d{2}-\d{2}$',
);
final Set<String> _achievementIds = {for (final a in achievements) a.id};

/// A strict YYYY-MM-DD calendar date (rejects e.g. 2026-02-31).
bool isDateKey(Object? key) {
  if (key is! String) return false;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(key);
  if (match == null) return false;
  final y = int.parse(match[1]!), m = int.parse(match[2]!);
  final d = int.parse(match[3]!);
  final date = DateTime(y, m, d);
  return date.year == y && date.month == m && date.day == d;
}

int? _int(Object? value, int min, int max) {
  int? n;
  if (value is int) {
    n = value;
  } else if (value is double &&
      value.isFinite &&
      value == value.roundToDouble()) {
    n = value.toInt();
  }
  return n != null && n >= min && n <= max ? n : null;
}

int _posInt(Object? raw) =>
    raw is num && raw.isFinite && raw > 0 ? raw.round() : 0;

String _cutoffKey(int days, DateTime now) =>
    dateKey(DateTime(now.year, now.month, now.day - days));

String _lastPart(String key) => key.split('/').last;

Map<String, T> _sorted<T>(Map<String, T> map) => {
  for (final key in map.keys.toList()..sort()) key: map[key] as T,
};

Map<String, dynamic> _canonical(Map<String, dynamic> doc) {
  doc['days'] = _sorted(Map<String, dynamic>.from(doc['days'] as Map));
  doc['floors'] = _sorted(Map<String, dynamic>.from(doc['floors'] as Map));
  doc['weekClaims'] = _sorted(
    Map<String, dynamic>.from(doc['weekClaims'] as Map),
  );
  doc['achievementDates'] = _sorted(
    Map<String, dynamic>.from(doc['achievementDates'] as Map),
  );
  return doc;
}

List<String> _sortedUnique(Iterable<String> items) =>
    items.toSet().toList()..sort();

Map<String, dynamic> _day(Map raw) => {
  'pages': (raw['pages'] as num?)?.toInt() ?? 0,
  'chapters': (raw['chapters'] as num?)?.toInt() ?? 0,
  'xp': (raw['xp'] as num?)?.toInt() ?? 0,
  if (((raw['seconds'] as num?)?.toInt() ?? 0) > 0)
    'seconds': (raw['seconds'] as num).toInt(),
  if (raw['quests'] == true) 'quests': true,
};

Map<String, dynamic> freshHabitData() => {
  'version': 1,
  for (final key in [...syncCounters, ...syncMaxima])
    key: key == 'freezes' ? 1 : 0,
  'bonusCarry': 0,
  'hours': List<int>.filled(24, 0),
  'weekClaims': <String, dynamic>{},
  'chestOpenedOn': null,
  'chestReward': null,
  'days': <String, dynamic>{},
  for (final key in syncSets) key: <String>[],
  'floors': <String, dynamic>{},
  'achievementDates': <String, dynamic>{},
  'freezeMilestones': <int>[],
  'goal': defaultGoal,
  'goalUpdatedAt': 0,
  'goalCelebratedOn': null,
};

Map<String, dynamic> freshDoc() => toDoc(freshHabitData(), DateTime.now());

/// The synced part of a habit record (HabitStore.data).
Map<String, dynamic> toDoc(Map<String, dynamic> data, [DateTime? now]) {
  final at = now ?? DateTime.now();
  final doc = <String, dynamic>{'version': habitSyncVersion};
  for (final key in syncCounters) {
    doc[key] = (data[key] as num?)?.toInt() ?? (key == 'freezes' ? 1 : 0);
  }
  for (final key in syncMaxima) {
    doc[key] = (data[key] as num?)?.toInt() ?? 0;
  }
  for (final key in syncSets) {
    doc[key] = _sortedUnique(
      (data[key] as List? ?? const []).whereType<String>(),
    );
  }
  final hours = data['hours'];
  doc['hours'] = hours is List && hours.length == 24
      ? [for (final h in hours) (h as num?)?.toInt() ?? 0]
      : List<int>.filled(24, 0);
  doc['days'] = <String, dynamic>{
    for (final entry in (data['days'] as Map? ?? const {}).entries)
      if (entry.value is Map) entry.key as String: _day(entry.value as Map),
  };
  final floorCutoff = _cutoffKey(floorSyncDays, at);
  doc['floors'] = <String, dynamic>{
    for (final entry in (data['floors'] as Map? ?? const {}).entries)
      if (_lastPart(entry.key as String).compareTo(floorCutoff) >= 0)
        entry.key as String: (entry.value as num).toInt(),
  };
  doc['weekClaims'] = <String, dynamic>{
    for (final entry in (data['weekClaims'] as Map? ?? const {}).entries)
      entry.key as String: (List<int>.from(
        (entry.value as List).whereType<int>(),
      )..sort()),
  };
  doc['achievementDates'] = Map<String, dynamic>.from(
    data['achievementDates'] as Map? ?? const {},
  );
  doc['freezeMilestones'] =
      (data['freezeMilestones'] as List? ?? const [])
          .whereType<num>()
          .map((n) => n.round())
          .toSet()
          .toList()
        ..sort();
  doc['chestOpenedOn'] = data['chestOpenedOn'];
  final reward = data['chestReward'];
  doc['chestReward'] = reward is Map ? Map<String, dynamic>.from(reward) : null;
  doc['goalCelebratedOn'] = data['goalCelebratedOn'];
  doc['goal'] = data['goal'] ?? defaultGoal;
  doc['goalUpdatedAt'] = (data['goalUpdatedAt'] as num?)?.toInt() ?? 0;
  return _canonical(doc);
}

/// Writes a merged document into a local record, keeping device-only fields.
Map<String, dynamic> fromDoc(
  Map<String, dynamic> doc,
  Map<String, dynamic> local,
) {
  final next = Map<String, dynamic>.from(jsonDecode(jsonEncode(local)) as Map);
  for (final key in [...syncCounters, ...syncMaxima]) {
    next[key] = doc[key];
  }
  for (final key in syncSets) {
    next[key] = List<String>.from(doc[key] as List);
  }
  next['hours'] = List<int>.from(doc['hours'] as List);
  next['days'] = jsonDecode(jsonEncode(doc['days']));
  // Older floors are device-only history; synced ones win where both exist.
  final floors = Map<String, dynamic>.from(next['floors'] as Map? ?? {});
  for (final entry in (doc['floors'] as Map).entries) {
    final mine = (floors[entry.key] as num?)?.toInt() ?? -1;
    final theirs = (entry.value as num).toInt();
    floors[entry.key as String] = theirs > mine ? theirs : mine;
  }
  next['floors'] = floors;
  next['weekClaims'] = jsonDecode(jsonEncode(doc['weekClaims']));
  next['achievementDates'] = Map<String, dynamic>.from(
    doc['achievementDates'] as Map,
  );
  next['freezeMilestones'] = List<int>.from(doc['freezeMilestones'] as List);
  next['chestOpenedOn'] = doc['chestOpenedOn'];
  next['chestReward'] = doc['chestReward'] == null
      ? null
      : Map<String, dynamic>.from(doc['chestReward'] as Map);
  next['goalCelebratedOn'] = doc['goalCelebratedOn'];
  next['goal'] = doc['goal'];
  next['goalUpdatedAt'] = doc['goalUpdatedAt'];
  return next;
}

bool _validSetItem(String key, Object? item, String retention) {
  if (key == 'chaptersCompleted') {
    return item is String && _chapterKey.hasMatch(item);
  }
  if (key == 'achievements') {
    return item is String && _achievementIds.contains(item);
  }
  return isDateKey(item) && (item as String).compareTo(retention) >= 0;
}

/// Validates an untrusted document.
Map<String, dynamic> validateDoc(Object? value, [DateTime? now]) {
  final at = now ?? DateTime.now();
  final doc = toDoc(freshHabitData(), at);
  if (value is! Map || value['version'] != habitSyncVersion) return doc;
  for (final key in [...syncCounters, ...syncMaxima]) {
    final raw = _int(value[key], 0, _maxCounter);
    if (raw != null) doc[key] = raw;
  }
  doc['freezes'] = math.min(maxFreezes, doc['freezes'] as int);
  final retention = _cutoffKey(retentionDays, at);
  for (final key in syncSets) {
    final raw = value[key];
    if (raw is! List) continue;
    doc[key] = _sortedUnique(
      raw.where((item) => _validSetItem(key, item, retention)).cast<String>(),
    );
  }
  final hours = value['hours'];
  if (hours is List && hours.length == 24) {
    doc['hours'] = [for (final h in hours) math.min(_maxCounter, _posInt(h))];
  }
  final days = value['days'];
  if (days is Map) {
    final kept = <String, dynamic>{};
    for (final entry in days.entries) {
      final key = entry.key;
      final raw = entry.value;
      if (!isDateKey(key) ||
          (key as String).compareTo(retention) < 0 ||
          raw is! Map) {
        continue;
      }
      final seconds = math.min(86400, _posInt(raw['seconds']));
      kept[key] = {
        'pages': math.min(_maxDayValue, _posInt(raw['pages'])),
        'chapters': math.min(_maxDayValue, _posInt(raw['chapters'])),
        'xp': math.min(_maxDayValue, _posInt(raw['xp'])),
        if (seconds > 0) 'seconds': seconds,
        if (raw['quests'] == true) 'quests': true,
      };
    }
    doc['days'] = kept;
  }
  final floors = value['floors'];
  if (floors is Map) {
    final floorCutoff = _cutoffKey(floorSyncDays, at);
    final kept = <String, dynamic>{};
    for (final entry in floors.entries) {
      final floor = _int(entry.value, -1, 5000);
      final key = entry.key;
      if (floor != null &&
          key is String &&
          _floorKey.hasMatch(key) &&
          _lastPart(key).compareTo(floorCutoff) >= 0) {
        kept[key] = floor;
      }
    }
    doc['floors'] = kept;
  }
  final claims = value['weekClaims'];
  if (claims is Map) {
    final claimCutoff = _cutoffKey(weekClaimDays, at);
    final kept = <String, dynamic>{};
    for (final entry in claims.entries) {
      final week = entry.key;
      final raw = entry.value;
      if (!isDateKey(week) ||
          (week as String).compareTo(claimCutoff) < 0 ||
          raw is! List) {
        continue;
      }
      kept[week] = <int>{
        for (final t in raw) ?_int(t, 0, weeklyTiers.length - 1),
      }.toList()..sort();
    }
    doc['weekClaims'] = kept;
  }
  final dates = value['achievementDates'];
  if (dates is Map) {
    doc['achievementDates'] = <String, dynamic>{
      for (final entry in dates.entries)
        if (_achievementIds.contains(entry.key) && isDateKey(entry.value))
          entry.key as String: entry.value,
    };
  }
  final milestones = value['freezeMilestones'];
  if (milestones is List) {
    doc['freezeMilestones'] = <int>{
      for (final m in milestones) ?_int(m, freezeEveryStreak, _maxCounter),
    }.toList()..sort();
  }
  if (isDateKey(value['chestOpenedOn'])) {
    doc['chestOpenedOn'] = value['chestOpenedOn'];
  }
  final reward = value['chestReward'];
  if (reward is Map && isDateKey(reward['on'])) {
    doc['chestReward'] = {
      'on': reward['on'],
      'xp': math.min(10000, _posInt(reward['xp'])),
      'freeze': reward['freeze'] == true,
    };
  }
  if (isDateKey(value['goalCelebratedOn'])) {
    doc['goalCelebratedOn'] = value['goalCelebratedOn'];
  }
  final goal = value['goal'];
  if (goal is String && dailyGoals.containsKey(goal)) doc['goal'] = goal;
  final goalAt = _int(value['goalUpdatedAt'], 0, _maxSafeInteger);
  if (goalAt != null) doc['goalUpdatedAt'] = goalAt;
  return _canonical(doc);
}

/// What [local] gained since [base]; empty when nothing changed.
Map<String, dynamic> diffDocs(
  Map<String, dynamic> local,
  Map<String, dynamic> base,
) {
  final delta = <String, dynamic>{};
  final add = <String, int>{};
  for (final key in syncCounters) {
    var change = (local[key] as int) - (base[key] as int);
    // Counters only grow locally; only freezes are spent.
    if (key != 'freezes' && change < 0) change = 0;
    if (change != 0) add[key] = change;
  }
  if (add.isNotEmpty) delta['add'] = add;

  final localHours = local['hours'] as List;
  final baseHours = base['hours'] as List;
  final hours = [
    for (var i = 0; i < 24; i++)
      math.max(0, (localHours[i] as int) - (baseHours[i] as int? ?? 0)),
  ];
  if (hours.any((h) => h > 0)) delta['hours'] = hours;

  final days = <String, dynamic>{};
  final baseDays = base['days'] as Map;
  for (final entry in (local['days'] as Map).entries) {
    final day = entry.value as Map;
    final before = baseDays[entry.key] as Map?;
    final change = <String, dynamic>{};
    for (final field in ['pages', 'chapters', 'xp', 'seconds']) {
      final value =
          ((day[field] as int?) ?? 0) - ((before?[field] as int?) ?? 0);
      if (value > 0) change[field] = value;
    }
    if (day['quests'] == true && before?['quests'] != true) {
      change['quests'] = true;
    }
    if (change.isNotEmpty || before == null) days[entry.key as String] = change;
  }
  if (days.isNotEmpty) delta['days'] = days;

  final max = <String, int>{};
  for (final key in syncMaxima) {
    if ((local[key] as int) > (base[key] as int)) max[key] = local[key] as int;
  }
  if (max.isNotEmpty) delta['max'] = max;

  final floors = <String, int>{};
  final baseFloors = base['floors'] as Map;
  for (final entry in (local['floors'] as Map).entries) {
    final value = entry.value as int;
    if (value > ((baseFloors[entry.key] as int?) ?? -1)) {
      floors[entry.key as String] = value;
    }
  }
  if (floors.isNotEmpty) delta['floors'] = floors;

  final sets = <String, List<String>>{};
  for (final key in syncSets) {
    final known = Set<String>.from(base[key] as List);
    final added = _sortedUnique(
      (local[key] as List).cast<String>().where((i) => !known.contains(i)),
    );
    if (added.isNotEmpty) sets[key] = added;
  }
  if (sets.isNotEmpty) delta['sets'] = sets;

  final knownMilestones = Set<int>.from(base['freezeMilestones'] as List);
  final milestones = [
    for (final m in local['freezeMilestones'] as List)
      if (!knownMilestones.contains(m)) m as int,
  ];
  if (milestones.isNotEmpty) delta['freezeMilestones'] = milestones;

  final weekClaims = <String, List<int>>{};
  final baseClaims = base['weekClaims'] as Map;
  for (final entry in (local['weekClaims'] as Map).entries) {
    final known = Set<int>.from(baseClaims[entry.key] as List? ?? const []);
    final added = [
      for (final t in entry.value as List)
        if (!known.contains(t)) t as int,
    ];
    if (added.isNotEmpty) weekClaims[entry.key as String] = added;
  }
  if (weekClaims.isNotEmpty) delta['weekClaims'] = weekClaims;

  final achievementDates = <String, String>{};
  final baseDates = base['achievementDates'] as Map;
  for (final entry in (local['achievementDates'] as Map).entries) {
    if (baseDates[entry.key] != entry.value) {
      achievementDates[entry.key as String] = entry.value as String;
    }
  }
  if (achievementDates.isNotEmpty) {
    delta['achievementDates'] = achievementDates;
  }

  final chest = local['chestOpenedOn'];
  if (chest is String && chest != base['chestOpenedOn']) {
    delta['chestOpenedOn'] = chest;
  }
  final reward = local['chestReward'];
  if (reward is Map && reward['on'] != (base['chestReward'] as Map?)?['on']) {
    delta['chestReward'] = Map<String, dynamic>.from(reward);
  }
  final celebrated = local['goalCelebratedOn'];
  if (celebrated is String && celebrated != base['goalCelebratedOn']) {
    delta['goalCelebratedOn'] = celebrated;
  }
  if ((local['goalUpdatedAt'] as int) > (base['goalUpdatedAt'] as int)) {
    delta['goal'] = {'value': local['goal'], 'at': local['goalUpdatedAt']};
  }
  return delta;
}

int _clampCounter(String key, int value) =>
    key == 'freezes' ? value.clamp(0, maxFreezes) : value.clamp(0, _maxCounter);

/// Applies a delta and returns a new document; identical to the website's
/// applyDelta. A delta must be applied at most once.
Map<String, dynamic> applyDelta(
  Map<String, dynamic> doc,
  Map<String, dynamic> delta, [
  DateTime? now,
]) {
  final at = now ?? DateTime.now();
  final next = validateDoc(jsonDecode(jsonEncode(doc)), at);
  final add = <String, int>{
    for (final entry in (delta['add'] as Map? ?? const {}).entries)
      entry.key as String: (entry.value as num).toInt(),
  };
  void bump(String key, int by) => add[key] = (add[key] ?? 0) + by;

  // Once-only things earned on two devices while offline are refunded.
  final sets = delta['sets'] as Map? ?? const {};
  for (final key in syncSets) {
    final incoming = List<String>.from(sets[key] as List? ?? const []);
    if (incoming.isEmpty) continue;
    final existing = Set<String>.from(next[key] as List);
    final duplicates = incoming.where(existing.contains).length;
    if (duplicates > 0) {
      if (key == 'freezeDates') {
        bump('freezes', duplicates);
        bump('freezesUsed', -duplicates);
      } else if (key == 'goalDates') {
        bump('goalDays', -duplicates);
      } else if (key == 'repairDates') {
        if (duplicates == incoming.length && (add['repairs'] ?? 0) > 0) {
          bump('repairs', -1);
        }
      } else if (key == 'chaptersCompleted') {
        bump('totalChapters', -duplicates);
        bump('totalXp', -duplicates * xpPerChapter);
      }
    }
    next[key] = _sortedUnique([...existing, ...incoming]);
  }

  final knownMilestones = Set<int>.from(next['freezeMilestones'] as List);
  for (final raw in delta['freezeMilestones'] as List? ?? const []) {
    final milestone = (raw as num).toInt();
    if (knownMilestones.contains(milestone)) bump('freezes', -1);
    knownMilestones.add(milestone);
  }
  next['freezeMilestones'] = knownMilestones.toList()..sort();

  final weekClaims = Map<String, dynamic>.from(next['weekClaims'] as Map);
  for (final entry in (delta['weekClaims'] as Map? ?? const {}).entries) {
    final claimed = Set<int>.from(
      weekClaims[entry.key] as List? ?? const <int>[],
    );
    for (final raw in entry.value as List) {
      final tier = (raw as num).toInt();
      if (claimed.contains(tier)) {
        final reward = weeklyTiers[tier];
        bump('weeklyClaims', -1);
        if (tier == weeklyTiers.length - 1) bump('weeklyGolds', -1);
        bump('rewardXp', -reward.rewardXp);
        bump('totalXp', -reward.rewardXp);
        if (reward.freeze) bump('freezes', -1);
      }
      claimed.add(tier);
    }
    weekClaims[entry.key as String] = claimed.toList()..sort();
  }
  next['weekClaims'] = weekClaims;

  final chest = delta['chestOpenedOn'] as String?;
  final reward = delta['chestReward'] as Map?;
  if (chest != null) {
    final current = next['chestOpenedOn'] as String?;
    if (current == chest) {
      bump('chestsOpened', -1);
      if (reward?['on'] == chest) {
        final xp = (reward!['xp'] as num).toInt();
        bump('rewardXp', -xp);
        bump('totalXp', -xp);
        if (reward['freeze'] == true) bump('freezes', -1);
      }
    } else if (current == null || chest.compareTo(current) > 0) {
      next['chestOpenedOn'] = chest;
    }
  }
  final currentReward = next['chestReward'] as Map?;
  if (reward != null &&
      (currentReward == null ||
          (reward['on'] as String).compareTo(currentReward['on'] as String) >
              0)) {
    next['chestReward'] = Map<String, dynamic>.from(reward);
  }

  final days = Map<String, dynamic>.from(next['days'] as Map);
  for (final entry in (delta['days'] as Map? ?? const {}).entries) {
    final change = entry.value as Map;
    final day = Map<String, dynamic>.from(
      days[entry.key] as Map? ?? {'pages': 0, 'chapters': 0, 'xp': 0},
    );
    var xp = (change['xp'] as num?)?.toInt() ?? 0;
    if (change['quests'] == true && day['quests'] == true) {
      // Both devices paid the all-quests bonus for this day.
      bump('questDays', -1);
      bump('totalXp', -questBonusXp);
      xp -= questBonusXp;
    }
    int field(String name) => (change[name] as num?)?.toInt() ?? 0;
    day['pages'] = math.min(
      _maxDayValue,
      (day['pages'] as int) + field('pages'),
    );
    day['chapters'] = math.min(
      _maxDayValue,
      (day['chapters'] as int) + field('chapters'),
    );
    day['xp'] = ((day['xp'] as int) + xp).clamp(0, _maxDayValue);
    final seconds = math.min(
      86400,
      ((day['seconds'] as int?) ?? 0) + field('seconds'),
    );
    if (seconds > 0) day['seconds'] = seconds;
    if (change['quests'] == true) day['quests'] = true;
    days[entry.key as String] = day;
  }
  next['days'] = days;

  for (final key in syncCounters) {
    final change = add[key] ?? 0;
    if (change != 0) {
      next[key] = _clampCounter(key, (next[key] as int) + change);
    }
  }
  final deltaHours = delta['hours'] as List?;
  if (deltaHours != null) {
    final hours = next['hours'] as List;
    next['hours'] = [
      for (var i = 0; i < 24; i++)
        math.min(
          _maxCounter,
          (hours[i] as int) + math.max(0, (deltaHours[i] as num).toInt()),
        ),
    ];
  }
  final max = delta['max'] as Map? ?? const {};
  for (final key in syncMaxima) {
    final value = (max[key] as num?)?.toInt();
    if (value != null && value > (next[key] as int)) next[key] = value;
  }
  final floors = Map<String, dynamic>.from(next['floors'] as Map);
  for (final entry in (delta['floors'] as Map? ?? const {}).entries) {
    final value = (entry.value as num).toInt();
    if (value > ((floors[entry.key] as int?) ?? -1)) {
      floors[entry.key as String] = value;
    }
  }
  next['floors'] = floors;
  final dates = Map<String, dynamic>.from(next['achievementDates'] as Map);
  for (final entry in (delta['achievementDates'] as Map? ?? const {}).entries) {
    final current = dates[entry.key] as String?;
    if (current == null || (entry.value as String).compareTo(current) < 0) {
      dates[entry.key as String] = entry.value;
    }
  }
  next['achievementDates'] = dates;
  final celebrated = delta['goalCelebratedOn'] as String?;
  final currentCelebrated = next['goalCelebratedOn'] as String?;
  if (celebrated != null &&
      (currentCelebrated == null ||
          celebrated.compareTo(currentCelebrated) > 0)) {
    next['goalCelebratedOn'] = celebrated;
  }
  final goal = delta['goal'] as Map?;
  if (goal != null &&
      (goal['at'] as num).toInt() > (next['goalUpdatedAt'] as int) &&
      dailyGoals.containsKey(goal['value'])) {
    next['goal'] = goal['value'];
    next['goalUpdatedAt'] = (goal['at'] as num).toInt();
  }
  return validateDoc(next, at);
}

/// Replays changes made since [snapshot] on top of a confirmed document.
Map<String, dynamic> rebaseDoc(
  Map<String, dynamic> confirmed,
  Map<String, dynamic> local,
  Map<String, dynamic> snapshot, [
  DateTime? now,
]) {
  final delta = diffDocs(local, snapshot);
  return delta.isEmpty ? confirmed : applyDelta(confirmed, delta, now);
}

bool _hasActivity(Map<String, dynamic> data) =>
    (data['days'] as Map? ?? const {}).isNotEmpty ||
    ((data['totalXp'] as num?) ?? 0) > 0;

/// Keeps the active account's habit record in step with the website. Signed
/// out, habits stay in `habits.json`; each account gets `habits-<id>.json`,
/// and progress made while signed out joins the account on sign-in.
class HabitSync extends ChangeNotifier {
  HabitSync(this.auth, this.habits, this.directory);
  final AuthStore auth;
  final HabitStore habits;
  final Directory directory;

  static const _anonymous = 'anonymous';
  File get _stateFile => File('${directory.path}/habit-sync.json');
  Map<String, dynamic> _state = {};
  String _owner = _anonymous;
  Timer? _debounce, _retry;
  Future<void>? _inFlight;
  bool _again = false;
  bool _applying = false;
  bool _disposed = false;
  int _generation = 0;
  bool syncing = false;
  String? error;
  DateTime? lastSynced;

  bool get signedIn => _owner != _anonymous;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  File fileFor(String owner) => owner == _anonymous
      ? File('${directory.path}/habits.json')
      : File(
          '${directory.path}/habits-${owner.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json',
        );

  Future<void> initialize() async {
    try {
      if (await _stateFile.exists()) {
        final raw = jsonDecode(await _stateFile.readAsString());
        if (raw is Map<String, dynamic>) _state = raw;
      }
    } catch (_) {
      _state = {};
    }
    habits.addListener(_habitsChanged);
    await activate();
    _retry = Timer.periodic(
      const Duration(minutes: 2),
      (_) => unawaited(synchronize()),
    );
  }

  /// Follows the signed-in account: switches the habit file and merges
  /// signed-out progress into the account.
  Future<void> activate() async {
    if (_disposed) return;
    final owner = auth.userId ?? _anonymous;
    if (owner == _owner && habits.file.path == fileFor(owner).path) return;
    _generation++;
    _debounce?.cancel();
    syncing = false;
    error = null;
    lastSynced = null;
    _owner = owner;
    _applying = true;
    try {
      Map<String, dynamic>? anonymous;
      if (owner != _anonymous) {
        anonymous = habits.file.path == fileFor(_anonymous).path
            ? Map<String, dynamic>.from(habits.data)
            : await _read(fileFor(_anonymous));
      }
      await habits.switchFile(fileFor(owner));
      if (anonymous != null && _hasActivity(anonymous)) {
        final merged = applyDelta(
          toDoc(habits.data),
          diffDocs(toDoc(anonymous), freshDoc()),
        );
        await habits.applySynced(fromDoc(merged, habits.data));
        final reset = HabitStore(fileFor(_anonymous));
        for (final key in HabitStore.deviceKeys) {
          if (anonymous[key] != null) reset.data[key] = anonymous[key];
        }
        await reset.persist();
        reset.dispose();
      }
    } finally {
      _applying = false;
    }
    _notify();
    if (owner != _anonymous) unawaited(synchronize());
  }

  Future<Map<String, dynamic>?> _read(File file) async {
    try {
      if (!await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString());
      return raw is Map<String, dynamic> ? raw : null;
    } catch (_) {
      return null;
    }
  }

  void _habitsChanged() {
    if (_applying || _disposed || !signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(seconds: 2),
      () => unawaited(synchronize(pull: false)),
    );
  }

  Map<String, dynamic> _record(String owner) =>
      Map<String, dynamic>.from(_state[owner] as Map? ?? const {});

  Future<void> _saveRecord(String owner, Map<String, dynamic> record) {
    _state[owner] = record;
    return writeJson(_stateFile, _state);
  }

  String _randomId() {
    final random = math.Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  Future<Map<String, dynamic>> _request([Map<String, dynamic>? body]) async {
    final response = await auth.api.request('/api/reading/habits', body: body);
    if (response['habits'] is! Map) {
      throw const ReaderApiException('Unexpected progress response', 503);
    }
    return validateDoc(response['habits']);
  }

  /// One sync round. A pending upload is resent with its original id until
  /// the server confirms it, so a lost response never double-counts.
  Future<void> synchronize({bool pull = true}) {
    if (_disposed || !signedIn || _owner != auth.userId) {
      return Future.value();
    }
    final inFlight = _inFlight;
    if (inFlight != null) {
      _again = true;
      return inFlight;
    }
    final run = _run(_owner, pull).whenComplete(() {
      _inFlight = null;
      if (_again && !_disposed) {
        _again = false;
        _habitsChanged();
      }
    });
    _inFlight = run;
    return run;
  }

  Future<void> _run(String owner, bool pull) async {
    final generation = _generation;
    bool current() =>
        !_disposed &&
        owner == _owner &&
        owner == auth.userId &&
        generation == _generation;
    syncing = true;
    error = null;
    _notify();
    try {
      final record = _record(owner);
      final base = record['base'] == null
          ? freshDoc()
          : validateDoc(record['base']);
      final pending = record['pending'] as Map?;
      Map<String, dynamic> snapshot;
      Map<String, dynamic> confirmed;
      if (pending != null && pending['id'] is String) {
        snapshot = validateDoc(pending['snapshot']);
        confirmed = await _request({
          'version': habitSyncVersion,
          'id': pending['id'],
          'delta': diffDocs(snapshot, base),
        });
      } else {
        snapshot = toDoc(habits.data);
        final delta = diffDocs(snapshot, base);
        if (delta.isEmpty) {
          if (!pull) return;
          confirmed = await _request();
        } else {
          final id = _randomId();
          await _saveRecord(owner, {
            'base': record['base'],
            'pending': {'id': id, 'snapshot': snapshot},
          });
          confirmed = await _request({
            'version': habitSyncVersion,
            'id': id,
            'delta': delta,
          });
        }
      }
      if (!current()) return;
      final merged = rebaseDoc(confirmed, toDoc(habits.data), snapshot);
      await _saveRecord(owner, {'base': confirmed, 'pending': null});
      _applying = true;
      try {
        await habits.applySynced(fromDoc(merged, habits.data));
      } finally {
        _applying = false;
      }
      // Changes made during the request, or by bookkeeping, go up next.
      if (diffDocs(toDoc(habits.data), confirmed).isNotEmpty) _again = true;
      lastSynced = DateTime.now();
    } on ReaderApiException catch (e) {
      if (current()) {
        error = e.status == 401
            ? 'Session expired. Sign in again to sync progress.'
            : 'Progress sync paused. It is saved on this device.';
        if (e.status == 401) unawaited(auth.refresh());
      }
    } catch (_) {
      if (current()) {
        error = 'Offline. Progress will sync when connected.';
      }
    } finally {
      if (current()) {
        syncing = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _debounce?.cancel();
    _retry?.cancel();
    habits.removeListener(_habitsChanged);
    super.dispose();
  }
}
