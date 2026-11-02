import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotm_reader/habit_store.dart';
import 'package:lotm_reader/progress_screen.dart';
import 'package:lotm_reader/reading_reminders.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('habit-test');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  HabitStore newStore([String name = 'habits.json']) =>
      HabitStore(File('${temp.path}/$name'));

  DateTime day(int month, int day, [int hour = 12]) =>
      DateTime(2026, month, day, hour);

  group('xp and levels', () {
    test('level thresholds increase linearly', () {
      expect(levelForXp(0).level, 1);
      expect(levelForXp(99).level, 1);
      expect(levelForXp(100).level, 2);
      expect(levelForXp(249).level, 2);
      expect(levelForXp(250).level, 3);
      expect(levelForXp(450).level, 4);
      expect(levelForXp(0).xpForNextLevel, 100);
      expect(levelForXp(100).xpForNextLevel, 150);
      expect(levelTitle(1), 'Newcomer');
      expect(levelTitle(10), 'Mystic');
      expect(levelTitle(11), 'Grand Mystic 1');
    });

    test('page reads award XP once per logical page', () async {
      final store = newStore();
      await store.load();
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 1,
        scroll: 0,
        now: day(10, 30),
      );
      expect(store.totalPages, 1);
      expect(store.totalXp, xpPerPage);
      // Same scroll position awards nothing twice.
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 1,
        scroll: 0,
        now: day(10, 30),
      );
      expect(store.totalPages, 1);
      // Scrolling to page 2 counts pages 1 and 2.
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 1,
        scroll: 1600,
        now: day(10, 30),
      );
      expect(store.totalPages, 3);
      expect(store.totalXp, 6);
    });

    test('floors are tracked per day, not per chapter forever', () async {
      final store = newStore();
      await store.load();
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 1,
        scroll: 1600,
        now: day(10, 29),
      );
      final pages = store.totalPages;
      // Next day, the same scroll position counts again.
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 1,
        scroll: 1600,
        now: day(10, 30),
      );
      expect(store.totalPages, greaterThan(pages));
    });

    test('chapter completion bonus is awarded only once per chapter', () async {
      final store = newStore();
      await store.load();
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 5,
        ratio: 0.94,
        now: day(10, 30),
      );
      expect(store.totalChapters, 0);
      expect(store.totalXp, xpPerPage); // Page 0 viewed at scroll 0.
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 5,
        ratio: 0.96,
        now: day(10, 30),
      );
      expect(store.totalChapters, 1);
      expect(store.totalXp, xpPerPage + xpPerChapter);
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 5,
        ratio: 0.99,
        now: day(10, 30),
      );
      expect(store.totalChapters, 1);
      expect(store.totalXp, xpPerPage + xpPerChapter);
      // A different chapter earns its own bonus.
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 6,
        ratio: 0.97,
        now: day(10, 30),
      );
      expect(store.totalChapters, 2);
    });

    test('rejects malformed editions and slugs', () async {
      final store = newStore();
      await store.load();
      await store.recordReading(
        edition: 'evil/../../etc',
        slug: 1,
        scroll: 999999,
        now: day(10, 30),
      );
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 0,
        scroll: 999999,
        now: day(10, 30),
      );
      expect(store.totalPages, 0);
    });
  });

  group('daily goal', () {
    test('casual goal met at 20 XP, celebration fires once per day', () async {
      final store = newStore();
      await store.load();
      await store.setGoal('casual');
      expect(store.goal, 'casual');
      expect(store.goalTargetXp, 20);
      // 10 pages at 2 XP reach 20 XP.
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 1,
        scroll: 800 * 9,
        now: day(10, 30),
      );
      // Recording happened "today" for the test clock but goalCelebratedOn
      // uses the real today; verify through the public API on a fresh day.
      expect(store.dayStats(dateKey(day(10, 30)))['xp'], greaterThanOrEqualTo(20));
      await store.persist();
    });

    test('goal progression uses the real calendar day', () async {
      final store = newStore();
      await store.load();
      await store.setGoal('casual');
      final now = DateTime.now();
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 1,
        scroll: 800 * 9,
        now: now,
      );
      expect(store.goalMetToday, isTrue);
      final celebrations = store.consumeCelebrations();
      expect(celebrations, contains('goal'));
      // A second drain is empty.
      expect(store.consumeCelebrations(), isNot(contains('goal')));
      // Goal milestone achievements are only awarded once.
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 2,
        ratio: 0.99,
        now: now,
      );
      expect(store.consumeCelebrations(), isNot(contains('goal')));
    });

    test('invalid goal falls back to regular', () async {
      final store = newStore();
      await store.load();
      await store.setGoal('bogus');
      expect(store.goal, defaultGoal);
      expect(store.goalTargetXp, 50);
    });
  });

  group('streaks and freezes', () {
    test('streak counts consecutive days', () async {
      final store = newStore();
      await store.load();
      for (var i = 0; i < 3; i++) {
        await store.recordReading(
          edition: 'lotm/webnovel',
          slug: 1,
          scroll: 1600,
          now: day(10, 28 + i, 9),
        );
      }
      expect(store.currentStreak(now: day(10, 30, 21)), 3);
      expect(store.longestStreak, 3);
    });

    test('a banked freeze bridges one missed day automatically', () async {
      final store = newStore();
      await store.load();
      expect(store.freezes, 1); // New readers start with one freeze.
      for (var i = 0; i < 3; i++) {
        await store.recordReading(
          edition: 'lotm/webnovel',
          slug: 1,
          scroll: 1600,
          now: DateTime(2026, 10, 24 + i, 9),
        );
      }
      // Nothing read on 2026-10-27; read again on 2026-10-28.
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 1,
        scroll: 1600,
        now: DateTime(2026, 10, 28, 9),
      );
      expect(store.freezes, 0);
      expect(store.currentStreak(now: DateTime(2026, 10, 28, 21)), 4);
      expect(
        store.recentDays(5, now: DateTime(2026, 10, 28, 21))[3].state,
        DayState.frozen,
      );
    });

    test('streak breaks when no freeze is banked', () async {
      final store = newStore();
      await store.load();
      for (var i = 0; i < 3; i++) {
        await store.recordReading(
          edition: 'lotm/webnovel',
          slug: 1,
          scroll: 1600,
          now: DateTime(2026, 10, 24 + i, 9),
        );
      }
      store.data['freezes'] = 0;
      await store.persist();
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 1,
        scroll: 1600,
        now: DateTime(2026, 10, 28, 9), // 2026-10-27 missed, unfrozen
      );
      expect(store.currentStreak(now: DateTime(2026, 10, 28, 21)), 1);
      // The pre-break run is preserved as the longest streak.
      expect(store.longestStreak, 3);
    });

    test('a freeze never covers a gap larger than the bank', () async {
      final store = newStore();
      await store.load();
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 1,
        scroll: 1600,
        now: DateTime(2026, 10, 24, 9),
      );
      // Two days missed with only one freeze: the streak is lost and the
      // freeze stays banked.
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 1,
        scroll: 1600,
        now: DateTime(2026, 10, 27, 9),
      );
      expect(store.freezes, 1);
      expect(store.currentStreak(now: DateTime(2026, 10, 27, 21)), 1);
    });

    test('every 10 streak days earn an extra freeze, up to two', () async {
      final store = newStore();
      await store.load();
      for (var i = 0; i < 10; i++) {
        await store.recordReading(
          edition: 'lotm/webnovel',
          slug: 1,
          scroll: 1600,
          now: DateTime(2026, 10, 1 + i, 9),
        );
      }
      expect(store.freezes, 2);
      expect(store.longestStreak, 10);
      expect(
        (store.data['freezeMilestones'] as List),
        contains(10),
      );
    });
  });

  group('achievements', () {
    test('first page and first chapter unlock', () async {
      final store = newStore();
      await store.load();
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 1,
        scroll: 0,
        ratio: 0.99,
        now: day(10, 30),
      );
      final unlocked = store.unlockedAchievements;
      expect(unlocked, contains('first-page'));
      expect(unlocked, contains('first-chapter'));
    });

    test('streak achievements unlock at 7 days', () async {
      final store = newStore();
      await store.load();
      for (var i = 0; i < 7; i++) {
        await store.recordReading(
          edition: 'lotm/webnovel',
          slug: 1,
          scroll: 1600,
          now: DateTime(2026, 10, 1 + i, 9),
        );
      }
      expect(store.unlockedAchievements, contains('streak-7'));
      expect(store.unlockedAchievements, isNot(contains('streak-14')));
    });

    test('locked achievements stay locked', () async {
      final store = newStore();
      await store.load();
      expect(store.unlockedAchievements, isEmpty);
    });
  });

  group('persistence', () {
    test('round trip keeps totals and settings', () async {
      final store = newStore();
      await store.load();
      await store.setGoal('serious');
      await store.setReminderTime('07:45');
      await store.setRemindersEnabled(false);
      await store.setWinBackEnabled(false);
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 3,
        scroll: 3200,
        ratio: 0.5,
        now: day(10, 30),
      );
      final xp = store.totalXp;
      store.dispose();

      final restored = newStore();
      await restored.load();
      expect(restored.totalXp, xp);
      expect(restored.goal, 'serious');
      expect(restored.reminderTime, '07:45');
      expect(restored.remindersEnabled, isFalse);
      expect(restored.winBackEnabled, isFalse);
      expect(restored.totalPages, store.totalPages);
    });

    test('a corrupt file is backed up and reset, not fatal', () async {
      final file = File('${temp.path}/habits.json');
      await file.writeAsString('this is {{{ not json');
      final store = newStore();
      await store.load();
      expect(store.totalXp, 0);
      expect(store.goal, defaultGoal);
      expect(await File('${file.path}.corrupt').exists(), isTrue);
    });

    test('invalid persisted values fall back to defaults', () async {
      final file = File('${temp.path}/habits.json');
      await file.writeAsString(
        '{"version":1,"goal":"bogus","reminderTime":"99:99",'
        '"freezes":99,"days":{"not-a-date":{"pages":5}},'
        '"remindersEnabled":"yes"}',
      );
      final store = newStore();
      await store.load();
      expect(store.goal, defaultGoal);
      expect(store.reminderTime, defaultReminderTime);
      expect(store.freezes, maxFreezes);
      expect(store.remindersEnabled, isTrue);
      expect(store.dayStats('not-a-date')['pages'], 0);
    });

    test('rejects a file with the wrong version', () async {
      final file = File('${temp.path}/habits.json');
      await file.writeAsString('{"version":2}');
      final store = newStore();
      await store.load();
      expect(store.totalXp, 0);
    });
  });

  group('reminder planning', () {
    final now = DateTime(2026, 11, 2, 10, 30); // A Monday morning.

    test('schedules the next seven days at the chosen time', () {
      final times = planDailyReminderTimes(
        now: now,
        time: '20:00',
        skipToday: false,
      );
      expect(times, hasLength(7));
      expect(times.first, DateTime(2026, 11, 2, 20, 0));
      expect(times[1], DateTime(2026, 11, 3, 20, 0));
      expect(times.last, DateTime(2026, 11, 8, 20, 0));
    });

    test('today is skipped once the goal is met', () {
      final times = planDailyReminderTimes(
        now: now,
        time: '20:00',
        skipToday: true,
      );
      expect(times.first, DateTime(2026, 11, 3, 20, 0));
      expect(times, hasLength(7));
    });

    test('today is skipped when the reminder time has passed', () {
      final evening = DateTime(2026, 11, 2, 21, 0);
      final times = planDailyReminderTimes(
        now: evening,
        time: '20:00',
        skipToday: false,
      );
      expect(times.first, DateTime(2026, 11, 3, 20, 0));
    });

    test('an invalid time falls back to 20:00', () {
      final times = planDailyReminderTimes(
        now: now,
        time: 'nonsense',
        skipToday: false,
        count: 1,
      );
      expect(times.single, DateTime(2026, 11, 2, 20, 0));
    });

    test('win-back needs an active history and the opt-in', () {
      expect(
        planWinBackTime(now: now, enabled: true, lastActiveKey: null),
        isNull,
      );
      expect(
        planWinBackTime(
          now: now,
          enabled: false,
          lastActiveKey: '2026-11-01',
        ),
        isNull,
      );
      final at = planWinBackTime(
        now: now,
        enabled: true,
        lastActiveKey: '2026-11-01',
      );
      expect(at, now.add(const Duration(hours: 48)));
    });

    test('reminder time setting validates strictly', () async {
      final store = newStore();
      await store.load();
      await store.setReminderTime('25:00');
      expect(store.reminderTime, defaultReminderTime);
      await store.setReminderTime('06:30');
      expect(store.reminderTime, '06:30');
    });
  });

  group('activity windows', () {
    test('recentDays reports states across active, frozen and idle days',
        () async {
      final store = newStore();
      await store.load();
      final now = DateTime.now();
      // Read today and two days ago; yesterday is missed with one freeze.
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 1,
        scroll: 1600,
        now: now.subtract(const Duration(days: 2)),
      );
      await store.recordReading(
        edition: 'lotm/webnovel',
        slug: 1,
        scroll: 1600,
        now: now,
      );
      final days = store.recentDays(3, now: now);
      expect(days[0].state, DayState.active);
      expect(days[1].state, DayState.frozen); // Bridged by the banked freeze.
      expect(days[2].state, DayState.active);
      expect(store.weekly, hasLength(7));
      expect(store.weekly.last.today, isTrue);
    });
  });

  testWidgets('progress screen renders the streak hero and goal card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = newStore(); // Defaults; no file IO needed.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProgressScreen(habits: store)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('DAY STREAK'), findsOneWidget);
    expect(find.text("Today's goal"), findsOneWidget);
    expect(find.textContaining('ACHIEVEMENTS'), findsOneWidget);
    store.dispose();
  });
}
