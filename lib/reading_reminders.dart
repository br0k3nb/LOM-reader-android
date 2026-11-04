import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'habit_store.dart';

/// Times for the next [count] daily reminders, at [time] ('HH:MM'), starting
/// today. Today's slot is skipped when [skipToday] is set (goal already met)
/// or the time has passed. Pure; used by tests and by the sync routine.
List<DateTime> planDailyReminderTimes({
  required DateTime now,
  required String time,
  required bool skipToday,
  int count = 7,
}) {
  final match = RegExp(r'^([01][0-9]|2[0-3]):([0-5][0-9])$').firstMatch(time);
  final hour = match != null ? int.parse(match[1]!) : 20;
  final minute = match != null ? int.parse(match[2]!) : 0;
  final today = DateTime(now.year, now.month, now.day);
  final result = <DateTime>[];
  var day = today;
  while (result.length < count) {
    final at = DateTime(day.year, day.month, day.day, hour, minute);
    final isToday = day == today;
    if (at.isAfter(now) && !(isToday && skipToday)) result.add(at);
    day = day.add(const Duration(days: 1));
  }
  return result;
}

/// Reminder wording. Today's reminder knows the live streak (and any
/// rescue on offer); later reminders in the rolling window stay generic
/// because the streak may have changed by then.
({String title, String body}) reminderCopy({
  required int streak,
  required bool isToday,
  int? rescueLength,
  int? rescueXp,
}) {
  if (isToday && rescueLength != null && rescueXp != null) {
    return (
      title: 'Rescue your $rescueLength-day streak',
      body: 'Earn $rescueXp XP before midnight to bring your streak back.',
    );
  }
  if (isToday && streak > 0) {
    return (
      title: 'Your $streak-day streak ends at midnight',
      body: 'A few pages tonight keeps the flame burning.',
    );
  }
  if (!isToday) {
    return (
      title: 'Keep your streak alive',
      body: 'Your story is waiting. A few pages today keeps your streak alive.',
    );
  }
  return (
    title: 'Start a new streak',
    body: 'A few pages today begins a brand-new reading streak.',
  );
}

/// A come-back nudge [hours] after the last moment the app was in use.
/// Rescheduled on every sync, so it only fires when the user actually stops
/// opening the app. Never scheduled for readers who haven't read yet.
DateTime? planWinBackTime({
  required DateTime now,
  required bool enabled,
  required String? lastActiveKey,
  int hours = 48,
}) {
  if (!enabled || lastActiveKey == null) return null;
  return now.add(Duration(hours: hours));
}

/// Schedules and posts the reading-motivation notifications: a rolling
/// seven-day window of daily reminders, a 48h come-back nudge, and immediate
/// celebration alerts for goals, levels, and achievements.
///
/// All calls are best-effort: notifications may be disabled at the OS level
/// and reading must never depend on them. Alarms are inexact, so no exact-alarm
/// permission is required. The next seven days are scheduled as one-shots, so
/// reminders keep working even if the app is never reopened; every app
/// start/resume re-evaluates the plan.
class ReadingReminders {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const int reminderIdBase = 9100; // 9100-9106
  static const int reminderWindow = 7;
  static const int winBackId = 9110;
  static const int goalMetId = 9120;
  static const int levelUpId = 9121;
  static const int achievementId = 9130;
  static const int milestoneId = 9131;

  static const String reminderChannelId = 'reader_reminders';
  static const String celebrationChannelId = 'reader_celebrations';

  static const String _reminderChannelName = 'Reading reminders';
  static const String _reminderChannelDescription =
      'Daily streak and goal reminders';
  static const String _celebrationChannelName = 'Reading celebrations';
  static const String _celebrationChannelDescription =
      'Goals, levels, and achievements reached while reading';

  Future<void> initialize() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
      ),
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<bool> notificationsAllowed() async {
    try {
      return await _android?.areNotificationsEnabled() ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> requestPermission() async {
    try {
      return await _android?.requestNotificationsPermission() ?? true;
    } catch (_) {
      return true;
    }
  }

  AndroidNotificationDetails _details(String channelId) =>
      channelId == celebrationChannelId
      ? const AndroidNotificationDetails(
          celebrationChannelId,
          _celebrationChannelName,
          channelDescription: _celebrationChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_notification',
          autoCancel: true,
        )
      : const AndroidNotificationDetails(
          reminderChannelId,
          _reminderChannelName,
          channelDescription: _reminderChannelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: 'ic_notification',
          autoCancel: true,
        );

  Future<void> _show({
    required int id,
    required String title,
    required String body,
    required String channelId,
  }) async {
    try {
      await initialize();
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: _details(channelId)),
      );
    } catch (_) {
      /* Alerts are best-effort; they never block reading. */
    }
  }

  Future<void> showGoalMet() => _show(
        id: goalMetId,
        title: 'Daily goal complete',
        body: 'Your streak is safe for today. Come back tomorrow to keep it going.',
        channelId: celebrationChannelId,
      );

  Future<void> showLevelUp(int level, String title, int totalXp) => _show(
        id: levelUpId,
        title: 'Level $level · $title',
        body: 'Total XP: $totalXp. The Mist yields a little more every day.',
        channelId: celebrationChannelId,
      );

  Future<void> showAchievement(String title, String description) => _show(
        id: achievementId,
        title: 'Achievement unlocked · $title',
        body: description,
        channelId: celebrationChannelId,
      );

  /// Turns consumed celebration events into notification posts.
  Future<void> postCelebrations(
    HabitStore habits,
    List<String> celebrations,
  ) async {
    for (final event in celebrations) {
      if (event == 'goal') {
        await showGoalMet();
      } else if (event.startsWith('streak:')) {
        final days = int.tryParse(event.substring('streak:'.length));
        if (days != null) {
          await _show(
            id: milestoneId,
            title: '$days-day streak!',
            body:
                'Your flame is now ${streakTier(days).name}. Next milestone: ${nextStreakMilestone(days)} days.',
            channelId: celebrationChannelId,
          );
        }
      } else if (event.startsWith('repaired:')) {
        final days = int.tryParse(event.substring('repaired:'.length));
        if (days != null) {
          await _show(
            id: milestoneId,
            title: 'Streak rescued',
            body: 'Your $days-day streak is back. Keep it alive tomorrow.',
            channelId: celebrationChannelId,
          );
        }
      } else if (event.startsWith('level:')) {
        final level = int.tryParse(event.substring('level:'.length));
        if (level != null) {
          await showLevelUp(level, levelTitle(level), habits.totalXp);
        }
      } else if (event.startsWith('achievement:')) {
        final id = event.substring('achievement:'.length);
        final matches = achievements.where((a) => a.id == id);
        if (matches.isNotEmpty) {
          await showAchievement(matches.first.title, matches.first.description);
        }
      }
    }
  }

  /// Cancels and re-schedules all upcoming reminders from the current habit
  /// state. Called on app start/resume, after settings changes, and whenever
  /// a celebration fires (today's reminder is then skipped).
  Future<void> sync(HabitStore habits) async {
    try {
      await initialize();
    } catch (_) {
      return;
    }
    try {
      for (var i = 0; i < reminderWindow; i++) {
        await _plugin.cancel(id: reminderIdBase + i);
      }
      await _plugin.cancel(id: winBackId);

      if (habits.remindersEnabled) {
        final now = DateTime.now();
        final times = planDailyReminderTimes(
          now: now,
          time: habits.reminderTime,
          skipToday: habits.goalMetToday,
          count: reminderWindow,
        );
        final streak = habits.currentStreak(now: now);
        final rescue = habits.streakRescue(now: now);
        var index = 0;
        for (final at in times) {
          final copy = reminderCopy(
            streak: streak,
            isToday: dateKey(at) == dateKey(now),
            rescueLength: rescue?.length,
            rescueXp: rescue?.targetXp,
          );
          await _plugin.zonedSchedule(
            id: reminderIdBase + index,
            title: copy.title,
            body: copy.body,
            scheduledDate: tz.TZDateTime.from(at, tz.local),
            notificationDetails:
                NotificationDetails(android: _details(reminderChannelId)),
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          );
          index++;
        }
      }

      final winBackAt = planWinBackTime(
        now: DateTime.now(),
        enabled: habits.winBackEnabled,
        lastActiveKey: habits.lastActiveKey,
      );
      if (winBackAt != null) {
        await _plugin.zonedSchedule(
          id: winBackId,
          title: 'The story missed you',
          body: "You haven't read in two days. Pick up where you left off.",
          scheduledDate: tz.TZDateTime.from(winBackAt, tz.local),
          notificationDetails:
              NotificationDetails(android: _details(reminderChannelId)),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } catch (_) {
      /* Reminders are best-effort; reading never depends on them. */
    }
  }
}
