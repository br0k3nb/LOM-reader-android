import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotm_reader/celebrations.dart';
import 'package:lotm_reader/habit_store.dart';
import 'package:lotm_reader/models.dart';
import 'package:lotm_reader/progress_screen.dart';
import 'package:lotm_reader/reader_hud.dart';

num pagesScroll(int pages) => (pages - 1) * 800;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('engagement-test');
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
  }) => store.recordReading(
    edition: edition,
    slug: slug,
    scroll: pagesScroll(pages),
    ratio: ratio,
    now: at,
  );

  /// Reads one new page every [step] seconds for [count] events.
  Future<DateTime> steadyRead(
    HabitStore store,
    DateTime start, {
    required int count,
    int step = 60,
    int slug = 1,
  }) async {
    var at = start;
    for (var i = 1; i <= count; i++) {
      at = start.add(Duration(seconds: step * (i - 1)));
      await read(store, at, pages: i, slug: slug);
    }
    return at;
  }

  group('sessions and time', () {
    test('time between close events is counted, long gaps are not', () async {
      final store = await freshStore();
      final start = DateTime(2026, 10, 5, 9);
      await steadyRead(store, start, count: 6); // 5 minutes.
      expect(store.dayStats('2026-10-05')['seconds'], 300);
      expect(store.totalSeconds, 300);
      // A 10-minute break starts a new session without counting the gap.
      await read(store, start.add(const Duration(minutes: 15)), pages: 7);
      expect(store.totalSeconds, 300);
      expect(store.longestSession, 300);
    });

    test('focus starts after 15 minutes and adds bonus XP', () async {
      final store = await freshStore();
      final start = DateTime(2026, 10, 5, 9);
      final end = await steadyRead(store, start, count: 16); // 15 minutes.
      expect(store.session(now: end)!.focus, isTrue);
      expect(store.focusSessions, 1);
      expect(store.consumeCelebrations(), contains('focus'));
      expect(store.currentBonusPct(now: end), focusBonusPct);
      final before = store.totalXp;
      // Ten more pages at +25%: 20 base XP, 5 bonus.
      await read(store, end.add(const Duration(seconds: 30)), pages: 26);
      expect(store.totalXp - before, 25);
      expect(store.bonusXp, 5);
      expect(store.unlockedAchievements, contains('focus-1'));
    });

    test('a Flame streak multiplies XP and carries fractions', () async {
      final store = await freshStore();
      final start = DateTime(2026, 10, 1, 9);
      for (var d = 0; d < 7; d++) {
        await read(store, start.add(Duration(days: d)), pages: 1, slug: d + 1);
      }
      final today = start.add(const Duration(days: 7));
      expect(store.currentBonusPct(now: today), 10);
      final before = store.totalXp;
      // 4 pages = 8 XP at +10% -> 0.8 bonus carried, so no bonus yet.
      await read(store, today, pages: 4, slug: 20);
      expect(store.totalXp - before, 8);
      // 2 more pages: 4 XP base, carry 80 + 40 = 120 -> 1 bonus.
      await read(store, today, pages: 6, slug: 20);
      expect(store.totalXp - before, 13);
    });

    test('reading hours feed insights', () async {
      final store = await freshStore();
      final now = DateTime.now();
      await read(store, now, pages: 10, ratio: 1);
      final i = store.insights(now: now);
      expect(i.activeDays, 1);
      expect(i.favoritePeriod, isNotNull);
      expect(i.bestWeekday, isNotNull);
      expect(i.chaptersPerDay, closeTo(1 / 14, 1e-9));
    });
  });

  group('mystery chest', () {
    test('unlocks with the goal, opens once, and is fixed per day', () async {
      final store = await freshStore();
      final at = DateTime(2026, 10, 5, 9);
      expect(store.chestAvailable(now: at), isFalse);
      expect(await store.openChest(now: at), isNull);
      await read(store, at, pages: 30); // 60 XP > regular goal.
      expect(store.chestAvailable(now: at), isTrue);
      expect(store.rewardsWaiting(now: at), greaterThanOrEqualTo(1));
      final expected = store.chestFor('2026-10-05');
      final before = store.totalXp;
      final dayXp = store.dayStats('2026-10-05')['xp'];
      final reward = await store.openChest(now: at);
      expect(reward, isNotNull);
      expect(reward!.xp, expected.xp);
      expect(store.totalXp - before, reward.xp);
      // Reward XP never inflates the day (goal and weekly challenge).
      expect(store.dayStats('2026-10-05')['xp'], dayXp);
      expect(store.chestAvailable(now: at), isFalse);
      expect(await store.openChest(now: at), isNull);
      expect(store.chestsOpened, 1);
      expect(store.unlockedAchievements, contains('chest-1'));
    });

    test('rarities cover the full range across many days', () async {
      final store = await freshStore();
      final rarities = <String>{};
      for (var d = 0; d < 400; d++) {
        final day = DateTime(2026, 1, 1).add(Duration(days: d));
        final r = store.chestFor(dateKey(day));
        expect(r.xp, greaterThan(0));
        rarities.add(r.rarity);
      }
      expect(rarities, containsAll(['common', 'rare', 'epic', 'legendary']));
    });
  });

  group('weekly challenge', () {
    test('tiers become claimable once and grant rewards', () async {
      final store = await freshStore();
      // Monday 2026-10-05; regular goal 50 XP -> bronze 150.
      final monday = DateTime(2026, 10, 5, 9);
      await read(store, monday, pages: 40, slug: 1); // 80 XP
      await read(
        store,
        monday.add(const Duration(days: 1)),
        pages: 40,
        slug: 2,
      );
      final tuesday = monday.add(const Duration(days: 1));
      final c = store.weeklyChallenge(now: tuesday);
      expect(c.week, '2026-10-05');
      expect(c.targets, [150, 250, 350]);
      expect(c.reached(0), isTrue);
      expect(c.reached(1), isFalse);
      expect(store.consumeCelebrations(), contains('weekly-ready:0'));
      expect(await store.claimWeekly(1, now: tuesday), isNull);
      final before = store.totalXp;
      final tier = await store.claimWeekly(0, now: tuesday);
      expect(tier!.name, 'Bronze');
      expect(store.totalXp - before, tier.rewardXp);
      expect(await store.claimWeekly(0, now: tuesday), isNull);
      expect(store.unlockedAchievements, contains('weekly-1'));
      // Next week starts fresh.
      final next = store.weeklyChallenge(
        now: monday.add(const Duration(days: 7)),
      );
      expect(next.xp, 0);
      expect(next.claimed, isEmpty);
    });

    test('gold grants a freeze up to the cap', () async {
      final store = await freshStore();
      final monday = DateTime(2026, 10, 5, 9);
      await read(store, monday, pages: 200, slug: 1); // 400 XP.
      final freezes = store.freezes;
      expect(await store.claimWeekly(2, now: monday), isNotNull);
      expect(store.freezes, (freezes + 1).clamp(0, maxFreezes));
      expect(store.unlockedAchievements, contains('weekly-gold'));
    });
  });

  group('ranks and journey', () {
    test('every three levels advance one Sequence', () {
      expect(sequenceForLevel(levelForXp(0)).sequence, 9);
      expect(sequenceForLevel(levelForXp(0)).name, 'Seer');
      var xp = 0;
      for (var l = 1; l < 4; l++) {
        xp += levelCost(l);
      }
      final four = sequenceForLevel(levelForXp(xp));
      expect(four.sequence, 8);
      expect(four.name, 'Clown');
      expect(four.nextName, 'Magician');
      for (var l = 4; l < 40; l++) {
        xp += levelCost(l);
      }
      final top = sequenceForLevel(levelForXp(xp));
      expect(top.sequence, 0);
      expect(top.nextName, isNull);
    });

    test('completed chapters merge translations', () async {
      final store = await freshStore();
      final at = DateTime(2026, 10, 5, 9);
      await read(store, at, slug: 3, ratio: 1);
      await read(store, at, slug: 3, ratio: 1, edition: 'lotm/oldtl');
      await read(store, at, slug: 4, ratio: 1, edition: 'coi/webnovel');
      expect(store.completedChapters('lotm'), {3});
      expect(store.completedChapters('coi'), {4});
    });
  });

  test('new fields survive a reload and bad values are dropped', () async {
    final store = await freshStore();
    final at = DateTime.now();
    await steadyRead(store, at.subtract(const Duration(minutes: 5)), count: 4);
    await store.setReaderHud(false);
    final restored = HabitStore(store.file);
    await restored.load();
    expect(restored.totalSeconds, store.totalSeconds);
    expect(restored.readerHud, isFalse);
    expect((restored.data['hours'] as List).length, 24);

    final bad = File('${temp.path}/bad.json');
    await bad.writeAsString(
      '{"version":1,"hours":[1,2],"weekClaims":{"x":[9]},"bonusCarry":500,"readerHud":"yes"}',
    );
    final cleaned = HabitStore(bad);
    await cleaned.load();
    expect((cleaned.data['hours'] as List).length, 24);
    expect(cleaned.data['weekClaims'], isEmpty);
    expect(cleaned.data['bonusCarry'], 99);
    expect(cleaned.readerHud, isTrue);
  });

  group('widgets', () {
    final editions = [
      Edition('lotm', 'webnovel', [
        for (var i = 1; i <= 20; i++)
          Chapter('lotm', 'webnovel', i, 'Chapter $i', 'Volume 1', i - 1),
      ]),
      Edition('coi', 'webnovel', [
        for (var i = 1; i <= 10; i++)
          Chapter('coi', 'webnovel', i, 'Chapter $i', 'Volume 1', i - 1),
      ]),
    ];

    testWidgets('progress screen shows rewards, journey and insights', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(420, 12000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = HabitStore(File('${temp.path}/w.json'));
      await tester.runAsync(() async {
        await store.recordReading(
          edition: 'lotm/webnovel',
          slug: 5,
          ratio: 1,
          scroll: pagesScroll(30),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProgressScreen(habits: store, editions: editions),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mystery chest ready!'), findsOneWidget);
      expect(find.text('Weekly challenge'), findsOneWidget);
      expect(find.text('YOUR JOURNEY'), findsOneWidget);
      expect(find.text('Lord of the Mysteries'), findsOneWidget);
      expect(find.text('1 of 20 chapters · Volume 1'), findsOneWidget);
      expect(find.text('INSIGHTS'), findsOneWidget);
      expect(find.text('READING HEATMAP'), findsOneWidget);
      expect(find.text('SEQUENCE 9'), findsOneWidget);
      expect(find.text('Time & focus'), findsOneWidget);

      await tester.tap(find.text('Mystery chest ready!'));
      await tester.pumpAndSettle();
      expect(find.text('MYSTERY CHEST'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Open chest'));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      expect(store.chestsOpened, 1);
      // Let the burst animation finish, then the reveal continuation run.
      for (var i = 0; i < 3; i++) {
        await tester.pumpAndSettle();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('Collect'), findsOneWidget);
      await tester.tap(find.text('Collect'));
      await tester.pumpAndSettle();
      expect(find.text('Chest opened'), findsOneWidget);
      store.dispose();
    });

    testWidgets('level-up and achievement dialogs render', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LevelUpDialog(level: 4, sequence: 8)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SEQUENCE 8 REACHED'), findsOneWidget);
      expect(find.text('Clown'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AchievementsDialog(
              unlocked: [
                achievementById('chest-1')!,
                achievementById('focus-1')!,
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 ACHIEVEMENTS UNLOCKED'), findsOneWidget);
      expect(find.text('Treasure Hunter'), findsOneWidget);
    });

    testWidgets('reader HUD pops up on XP and fades away', (tester) async {
      final store = HabitStore(File('${temp.path}/hud.json'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: ReaderXpHud(habits: store),
            ),
          ),
        ),
      );
      store.gains.value = XpGain(6, 0, 0, false, DateTime.now());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1400));
      expect(find.text('+6 XP'), findsOneWidget);
      expect(find.text('0/50 XP today'), findsOneWidget);
      final opacity = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacity.opacity, 1);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        0,
      );
      store.dispose();
    });
  });
}
