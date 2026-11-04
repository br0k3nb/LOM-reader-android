import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotm_reader/habit_store.dart';
import 'package:lotm_reader/progress_screen.dart';
import 'package:lotm_reader/reading_reminders.dart';

/// Scroll offset at which a chapter has shown [pages] logical pages.
num pagesScroll(int pages) => (pages - 1) * 800;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('streak-test');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<HabitStore> freshStore([String name = 'habits.json']) async {
    final store = HabitStore(File('${temp.path}/$name'));
    await store.load();
    return store;
  }

  Future<void> read(
    HabitStore store,
    DateTime at, {
    int pages = 3,
    int slug = 1,
    String edition = 'lotm/webnovel',
    num? ratio,
  }) =>
      store.recordReading(
        edition: edition,
        slug: slug,
        scroll: pagesScroll(pages),
        ratio: ratio,
        now: at,
      );

  group('tiers and milestones', () {
    test('flame tiers follow streak length', () {
      expect(streakTier(0).name, 'Unlit');
      expect(streakTier(1).name, 'Spark');
      expect(streakTier(6).name, 'Spark');
      expect(streakTier(7).name, 'Flame');
      expect(streakTier(30).name, 'Blaze');
      expect(streakTier(100).name, 'Inferno');
      expect(streakTier(400).name, 'Eternal');
    });

    test('milestones and the next target', () {
      expect(isStreakMilestone(7), isTrue);
      expect(isStreakMilestone(8), isFalse);
      expect(isStreakMilestone(500), isTrue);
      expect(isStreakMilestone(450), isFalse);
      expect(nextStreakMilestone(0), 3);
      expect(nextStreakMilestone(7), 14);
      expect(nextStreakMilestone(365), 400);
      expect(previousStreakMilestone(10), 7);
      expect(previousStreakMilestone(2), 0);
      expect(previousStreakMilestone(420), 400);
    });

    test('first read of a day celebrates the streak once, milestones too',
        () async {
      final store = await freshStore();
      for (var i = 0; i < 3; i++) {
        await read(store, DateTime(2026, 10, 1 + i, 9));
        final events = store.consumeCelebrations();
        expect(events, contains('streak-extended:${i + 1}'));
        expect(events.contains('streak:3'), i == 2);
        // A second read the same day does not re-celebrate.
        await read(store, DateTime(2026, 10, 1 + i, 10), pages: 6);
        expect(
          store.consumeCelebrations().where((e) => e.startsWith('streak')),
          isEmpty,
        );
      }
    });
  });

  group('freezes', () {
    test('a used freeze is counted and announced', () async {
      final store = await freshStore();
      await read(store, DateTime(2026, 10, 1, 9));
      await read(store, DateTime(2026, 10, 2, 9));
      store.consumeCelebrations();
      await read(store, DateTime(2026, 10, 4, 9)); // Oct 3 missed.
      expect(store.consumeCelebrations(), contains('freeze-used:1'));
      expect(store.freezesUsed, 1);
      expect(store.unlockedAchievements, contains('freeze-saved'));
    });
  });

  group('streak rescue', () {
    Future<HabitStore> brokenStreak() async {
      final store = await freshStore();
      for (var i = 0; i < 5; i++) {
        await read(store, DateTime(2026, 10, 1 + i, 9));
      }
      store.data['freezes'] = 0;
      await store.persist();
      return store;
    }

    test('a short gap offers a same-day rescue that double goal claims',
        () async {
      final store = await brokenStreak();
      final back = DateTime(2026, 10, 8, 9); // Oct 6 and 7 missed.
      await read(store, back);
      expect(store.currentStreak(now: back), 1);
      final rescue = store.streakRescue(now: back);
      expect(rescue, isNotNull);
      expect(rescue!.length, 5);
      expect(rescue.gap, ['2026-10-06', '2026-10-07']);
      expect(rescue.targetXp, goalXp(defaultGoal) * rescueGoalMultiplier);
      store.consumeCelebrations();

      // 50 pages = 100 XP = 2× the regular goal.
      await read(store, back.add(const Duration(hours: 1)), pages: 50, slug: 2);
      expect(store.consumeCelebrations(), contains('repaired:6'));
      expect(store.currentStreak(now: back), 6);
      expect(store.longestStreak, 6);
      expect(store.streakRescue(now: back), isNull);
      expect(store.repairs, 1);
      expect(store.unlockedAchievements, contains('streak-repaired'));
      final days = store.recentDays(3, now: back);
      expect(days[0].state, DayState.repaired);
      expect(days[1].state, DayState.repaired);
      expect(days[2].state, DayState.active);
    });

    test('the rescue expires at midnight', () async {
      final store = await brokenStreak();
      await read(store, DateTime(2026, 10, 7, 9)); // Oct 6 missed.
      expect(store.streakRescue(now: DateTime(2026, 10, 7, 20)), isNotNull);
      expect(store.streakRescue(now: DateTime(2026, 10, 8, 9)), isNull);
      await read(store, DateTime(2026, 10, 8, 9), pages: 60, slug: 3);
      expect(store.repairs, 0);
      expect(store.currentStreak(now: DateTime(2026, 10, 8, 21)), 2);
    });

    test('gaps longer than the rescue window are not rescuable', () async {
      final store = await brokenStreak();
      final back = DateTime(2026, 10, 10, 9); // 4 days missed.
      await read(store, back);
      expect(store.streakRescue(now: back), isNull);
    });

    test('a pending rescue survives a reload the same day', () async {
      final store = await freshStore();
      final now = DateTime.now();
      DateTime ago(int days) =>
          DateTime(now.year, now.month, now.day - days, 12);
      for (var i = 6; i >= 3; i--) {
        await read(store, ago(i));
      }
      store.data['freezes'] = 0;
      await store.persist();
      await read(store, ago(0)); // Two days missed.
      final reloaded = HabitStore(store.file);
      await reloaded.load();
      final rescue = reloaded.streakRescue();
      expect(rescue, isNotNull);
      expect(rescue!.length, 4);
      expect(rescue.gap, hasLength(2));
    });
  });

  group('daily quests', () {
    test('three quests: goal first, and the same set all day', () async {
      final store = await freshStore();
      final quests = store.questsFor('2026-10-05');
      expect(quests, hasLength(3));
      expect(quests.first.id, 'goal');
      expect(quests[1].id, isNot(quests[2].id));
      expect(
        store.questsFor('2026-10-05').map((q) => q.id),
        quests.map((q) => q.id),
      );
      // Different days rotate through the pool.
      final ids = <String>{
        for (var d = 1; d <= 28; d++)
          ...store.questsFor('2026-10-${d.toString().padLeft(2, '0')}').map((q) => q.id),
      };
      expect(ids, containsAll(['goal', 'pages', 'chapter', 'distinct', 'overtime']));
    });

    test('finishing every quest pays the bonus exactly once', () async {
      final store = await freshStore();
      final at = DateTime(2026, 10, 5, 9);
      // Satisfy every possible quest: 3 chapters opened and finished, plenty
      // of pages and XP.
      for (var slug = 1; slug <= 3; slug++) {
        await read(store, at, pages: 40, slug: slug, ratio: 1);
      }
      final events = store.consumeCelebrations();
      expect(events, contains('quests'));
      expect(store.questDays, 1);
      final xp = store.dayStats('2026-10-05')['xp'] as int;
      expect(xp, 120 * xpPerPage + 3 * xpPerChapter + questBonusXp);
      await read(store, at, pages: 60, slug: 1);
      expect(store.consumeCelebrations(), isNot(contains('quests')));
      expect(store.questDays, 1);
      expect(store.unlockedAchievements, contains('quests-1'));
    });
  });

  group('goal streaks and records', () {
    test('consecutive goal days build a goal streak', () async {
      final store = await freshStore();
      for (var i = 0; i < 7; i++) {
        await read(store, DateTime(2026, 10, 1 + i, 9), pages: 25);
      }
      expect(store.goalDays, 7);
      expect(store.longestGoalStreak, 7);
      expect(store.currentGoalStreak(now: DateTime(2026, 10, 7, 21)), 7);
      expect(store.currentGoalStreak(now: DateTime(2026, 10, 8, 9)), 7);
      expect(store.currentGoalStreak(now: DateTime(2026, 10, 9, 9)), 0);
      expect(store.unlockedAchievements, containsAll(['goal-1', 'goal-7', 'perfect-week']));
    });

    test('best-day records and overtime are tracked', () async {
      final store = await freshStore();
      await read(store, DateTime(2026, 10, 1, 9), pages: 100);
      expect(store.bestDayPages, 100);
      expect(store.metricValue('overtimeDays'), 1);
      expect(store.unlockedAchievements, containsAll(['marathon', 'overachiever', 'pages-100']));
      await read(store, DateTime(2026, 10, 2, 9), pages: 10);
      expect(store.bestDayPages, 100);
    });
  });

  group('habit achievements', () {
    test('time of day, weekends, both novels and comebacks', () async {
      final store = await freshStore();
      await read(store, DateTime(2026, 10, 3, 6)); // Saturday, early.
      expect(store.unlockedAchievements, contains('early-bird'));
      await read(store, DateTime(2026, 10, 4, 23, 30)); // Sunday, late.
      expect(store.unlockedAchievements, containsAll(['night-owl', 'weekend-warrior']));
      await read(store, DateTime(2026, 10, 5, 9), ratio: 1);
      await read(store, DateTime(2026, 10, 5, 10), edition: 'coi/webnovel', ratio: 1);
      expect(store.unlockedAchievements, contains('two-worlds'));
      await read(store, DateTime(2026, 10, 20, 9));
      expect(store.unlockedAchievements, contains('comeback'));
      expect(store.achievementUnlockedOn('comeback'), DateTime(2026, 10, 20));
    });

    test('every achievement id is unique and has a positive target', () {
      final ids = achievements.map((a) => a.id).toSet();
      expect(ids, hasLength(achievements.length));
      expect(achievements.length, greaterThanOrEqualTo(45));
      for (final a in achievements) {
        expect(a.target, greaterThan(0), reason: a.id);
      }
    });

    test('progress and the closest locked achievements', () async {
      final store = await freshStore();
      await read(store, DateTime(2026, 10, 1, 9), pages: 40);
      final pages100 = achievementById('pages-100')!;
      expect(store.achievementProgress(pages100), 40);
      final next = store.nextAchievements();
      expect(next, isNotEmpty);
      expect(next.any((a) => store.unlockedAchievements.contains(a.id)), isFalse);
    });
  });

  group('persistence', () {
    test('new counters and dates survive a reload', () async {
      final store = await freshStore();
      for (var i = 0; i < 3; i++) {
        await read(store, DateTime.now().subtract(Duration(days: 2 - i)), pages: 30);
      }
      final restored = HabitStore(store.file);
      await restored.load();
      expect(restored.goalDays, 3);
      expect(restored.longestGoalStreak, 3);
      expect(restored.bestDayPages, 30);
      expect(restored.currentGoalStreak(), 3);
      expect(restored.achievementUnlockedOn('first-page'), isNotNull);
    });

    test('malformed new fields fall back safely', () async {
      final file = File('${temp.path}/bad.json');
      await file.writeAsString(
        '{"version":1,"goalDays":-4,"repairDates":[1,"x"],'
        '"lostStreak":{"on":"nope","length":3,"gap":[]},'
        '"achievementDates":{"unknown":"2026-10-01","first-page":5}}',
      );
      final store = HabitStore(file);
      await store.load();
      expect(store.goalDays, 0);
      expect(store.data['repairDates'], isEmpty);
      expect(store.data['lostStreak'], isNull);
      expect(store.data['achievementDates'], isEmpty);
    });

    test('version-1 files from before this update still load', () async {
      final file = File('${temp.path}/old.json');
      final today = dateKey(DateTime.now());
      await file.writeAsString(
        '{"version":1,"totalXp":300,"totalPages":150,"days":{"$today":{"pages":80,"chapters":2,"xp":210}},'
        '"achievements":["first-page"]}',
      );
      final store = HabitStore(file);
      await store.load();
      expect(store.totalXp, 300);
      expect(store.bestDayPages, 80); // Backfilled from history.
      expect(store.unlockedAchievements, ['first-page']);
    });
  });

  group('calendar', () {
    test('calendar weeks start on Monday and flag future days', () async {
      final store = await freshStore();
      final wednesday = DateTime(2026, 11, 4, 12);
      final days = store.calendarWeeks(5, now: wednesday);
      expect(days, hasLength(35));
      expect(days.first.date.weekday, DateTime.monday);
      expect(days.last.date.weekday, DateTime.sunday);
      expect(days.where((d) => d.future), hasLength(4)); // Thu–Sun.
      expect(days[28 + 2].key, '2026-11-04');
    });

    test('calendar marks goal days', () async {
      final store = await freshStore();
      final now = DateTime.now();
      await read(store, now, pages: 30);
      final today = store.calendarWeeks(1, now: now).firstWhere((d) => d.key == dateKey(now));
      expect(today.goalMet, isTrue);
      expect(today.state, DayState.active);
    });
  });

  group('reminder copy', () {
    test('today reflects the live streak and rescue', () {
      expect(reminderCopy(streak: 12, isToday: true).title, contains('12-day'));
      expect(
        reminderCopy(streak: 0, isToday: true, rescueLength: 9, rescueXp: 100).title,
        contains('Rescue your 9-day'),
      );
      expect(reminderCopy(streak: 0, isToday: true).title, 'Start a new streak');
      expect(reminderCopy(streak: 12, isToday: false).title, 'Keep your streak alive');
    });
  });

  group('widgets', () {
    Future<void> pumpScreen(WidgetTester tester, HabitStore store) async {
      tester.view.physicalSize = const Size(420, 5200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: ProgressScreen(habits: store))),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('progress screen shows quests, records and categories',
        (tester) async {
      final store = HabitStore(File('${temp.path}/w.json'));
      await pumpScreen(tester, store);
      expect(find.text('DAY STREAK'), findsOneWidget);
      expect(find.text('UNLIT'), findsOneWidget);
      expect(find.text('Read a page to start a streak'), findsOneWidget);
      expect(find.text('DAILY QUESTS'), findsOneWidget);
      expect(find.text('Meet your daily goal'), findsOneWidget);
      expect(find.text('RECORDS'), findsOneWidget);
      expect(find.text('Streaks'), findsOneWidget);
      expect(find.text('Habits'), findsOneWidget);
      store.dispose();
    });

    testWidgets('tapping a badge opens its details', (tester) async {
      final store = HabitStore(File('${temp.path}/w.json'));
      await pumpScreen(tester, store);
      await tester.tap(find.text('Night Owl'));
      await tester.pumpAndSettle();
      expect(find.text('Read between 11 PM and 4 AM'), findsOneWidget);
      expect(find.text('0 / 1'), findsOneWidget);
      store.dispose();
    });

    testWidgets('the rescue card appears while a rescue is open',
        (tester) async {
      final store = HabitStore(File('${temp.path}/w.json'));
      final today = dateKey(DateTime.now());
      store.data['lostStreak'] = {
        'on': today,
        'length': 9,
        'gap': ['2000-01-01'],
      };
      await pumpScreen(tester, store);
      expect(find.text('Rescue your 9-day streak'), findsOneWidget);
      store.dispose();
    });

    testWidgets('milestone dialog names the tier', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: StreakCelebrationDialog(days: 30)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('30'), findsOneWidget);
      expect(find.textContaining('Blaze'), findsOneWidget);
    });
  });
}
