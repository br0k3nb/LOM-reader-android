import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'account_screen.dart';
import 'auth_store.dart';
import 'background_downloads.dart';
import 'chapter_list.dart';
import 'cloud_sync.dart';
import 'celebrations.dart';
import 'design.dart';
import 'habit_store.dart';
import 'progress_screen.dart';
import 'reading_reminders.dart';
import 'library_store.dart';
import 'models.dart';
import 'motion.dart';
import 'reader_api.dart';
import 'reader_screen.dart';
import 'state_store.dart';
import 'storage_usage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  runApp(const LotmApp());
}

class LotmApp extends StatelessWidget {
  const LotmApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'LOTM Reader',
    debugShowCheckedModeBanner: false,
    theme: readerTheme(),
    home: const LibraryHome(),
  );
}

class LibraryHome extends StatefulWidget {
  const LibraryHome({super.key, this.supportDirectory});
  final Directory? supportDirectory;
  @override
  State<LibraryHome> createState() => _LibraryHomeState();
}

class _LibraryHomeState extends State<LibraryHome> with WidgetsBindingObserver {
  LibraryStore? library;
  StateStore? reading;
  BackgroundDownloads? downloads;
  AuthStore? auth;
  CloudSync? sync;
  HabitStore? habits;
  ReadingReminders? reminders;
  String? error;
  int tab = 0;
  bool? notificationsAllowed;
  StorageUsage usage = const StorageUsage();
  Timer? _storageTimer;
  bool _measuring = false;
  String? _lastAccount;
  static const files = MethodChannel('dev.lotm.reader/documents');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    rewardDialogsOpen.addListener(_rewardDialogsChanged);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final dir =
          widget.supportDirectory ?? await getApplicationSupportDirectory();
      final state = StateStore(File('${dir.path}/reading-state.json'));
      await state.load();
      final books = LibraryStore(
        Directory('${dir.path}/library'),
        parseCatalog(await rootBundle.loadString('assets/meta.json')),
      );
      await books.initialize();
      final tasks = BackgroundDownloads(books);
      await tasks.initialize();
      final account = AuthStore(ReaderApi());
      await account.initialize();
      final cloud = CloudSync(
        account,
        state,
        File('${dir.path}/reading-sync.json'),
      );
      await cloud.initialize();
      final habitFile = File('${dir.path}/habits.json');
      final habitStore = HabitStore(habitFile);
      await habitStore.load();
      final reminderService = ReadingReminders();
      unawaited(reminderService.sync(habitStore));
      final allowed = await reminderService.notificationsAllowed();
      if (!mounted) {
        tasks.dispose();
        cloud.dispose();
        account.api.dispose();
        account.dispose();
        habitStore.dispose();
        books.dispose();
        state.dispose();
        return;
      }
      library = books;
      reading = state;
      downloads = tasks;
      auth = account;
      sync = cloud;
      habits = habitStore;
      reminders = reminderService;
      notificationsAllowed = allowed;
      _lastAccount = account.userId;
      books.addListener(_refresh);
      state.addListener(_refresh);
      tasks.addListener(_refresh);
      account.addListener(_accountChanged);
      cloud.addListener(_refresh);
      habitStore.addListener(_habitChanged);
      setState(() {});
      // Freezes spent while the app was closed are announced now.
      _habitChanged();
      await _measure();
      _storageTimer = Timer.periodic(const Duration(seconds: 6), (_) {
        if (downloads?.busy == true) _measure();
      });
      unawaited(account.refresh());
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  void _accountChanged() {
    if (_lastAccount != auth!.userId) {
      _lastAccount = auth!.userId;
      unawaited(sync!.activate());
    }
    _refresh();
  }

  /// Habit activity records land here: surface celebrations in the UI and
  /// re-schedule reminders (today's reminder disappears once the goal is
  /// met). Cheap when nothing was celebrated.
  void _habitChanged() {
    final store = habits;
    if (store == null) return;
    final celebrations = store.consumeCelebrations();
    if (celebrations.isNotEmpty) {
      _notifyCelebrations(celebrations);
      unawaited(reminders?.postCelebrations(store, celebrations));
      unawaited(reminders?.sync(store));
    }
    _refresh();
  }

  /// Big moments (streak milestones and rescues) wait for the reader to
  /// close, then get a full celebration dialog on the home screen.
  final List<String> _pendingMilestones = [];

  void _notifyCelebrations(List<String> celebrations) {
    final parts = <String>[];
    for (final event in celebrations) {
      if (event == 'goal') {
        parts.add('Daily goal complete · mystery chest unlocked');
      } else if (event == 'quests') {
        parts.add('All daily quests done · +$questBonusXp XP');
      } else if (event.startsWith('streak-extended:')) {
        final n = int.tryParse(event.substring('streak-extended:'.length));
        if (n != null) {
          parts.add(n == 1 ? 'Streak started 🔥' : '$n-day streak 🔥');
        }
      } else if (event.startsWith('streak:') || event.startsWith('repaired:')) {
        _pendingMilestones.add(event);
      } else if (event.startsWith('freeze-used:')) {
        final n = int.tryParse(event.substring('freeze-used:'.length)) ?? 1;
        parts.add(
          n == 1
              ? 'A streak freeze covered your missed day'
              : '$n streak freezes covered your missed days',
        );
      } else if (event == 'freeze-earned') {
        parts.add('Streak freeze earned');
      } else if (event.startsWith('level:') ||
          event.startsWith('sequence:') ||
          event.startsWith('achievement:')) {
        _pendingMilestones.add(event);
      } else if (event == 'focus') {
        parts.add('Focus reached · +$focusBonusPct% XP this session');
      } else if (event.startsWith('weekly-ready:')) {
        final i = int.tryParse(event.substring('weekly-ready:'.length));
        if (i != null && i >= 0 && i < weeklyTiers.length) {
          parts.add('${weeklyTiers[i].name} weekly reward ready to claim');
        }
      }
    }
    if (parts.isNotEmpty) _notice(parts.join(' · '));
    if (_pendingMilestones.isNotEmpty &&
        !_reading &&
        rewardDialogsOpen.value == 0) {
      _showMilestones();
    }
  }

  bool _reading = false;

  bool _showingMilestones = false;

  /// Shows queued big moments one dialog at a time: streak milestones and
  /// rescues first, then the highest level reached (with any Sequence
  /// advance), then every newly unlocked achievement together.
  Future<void> _showMilestones() async {
    if (_showingMilestones) return;
    _showingMilestones = true;
    try {
      while (_pendingMilestones.isNotEmpty && mounted) {
        final batch = List<String>.from(_pendingMilestones);
        _pendingMilestones.clear();
        for (final event in batch) {
          if (!event.startsWith('streak:') && !event.startsWith('repaired:')) {
            continue;
          }
          final days = int.tryParse(event.substring(event.indexOf(':') + 1));
          if (days == null || !mounted) continue;
          await showDialog<void>(
            context: context,
            builder: (context) => StreakCelebrationDialog(
              days: days,
              repaired: event.startsWith('repaired:'),
            ),
          );
        }
        int? level;
        int? sequence;
        final unlocked = <Achievement>[];
        for (final event in batch) {
          final value = event.substring(event.indexOf(':') + 1);
          if (event.startsWith('level:')) {
            final n = int.tryParse(value);
            if (n != null && (level == null || n > level)) level = n;
          } else if (event.startsWith('sequence:')) {
            final n = int.tryParse(value);
            if (n != null && (sequence == null || n < sequence)) sequence = n;
          } else if (event.startsWith('achievement:')) {
            final a = achievementById(value);
            if (a != null) unlocked.add(a);
          }
        }
        if (level != null && mounted) {
          HapticFeedback.mediumImpact();
          await showDialog<void>(
            context: context,
            builder: (context) =>
                LevelUpDialog(level: level!, sequence: sequence),
          );
        }
        if (unlocked.isNotEmpty && mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) => AchievementsDialog(unlocked: unlocked),
          );
        }
      }
    } finally {
      _showingMilestones = false;
    }
  }

  void _rewardDialogsChanged() {
    if (rewardDialogsOpen.value == 0 &&
        _pendingMilestones.isNotEmpty &&
        !_reading) {
      unawaited(_showMilestones());
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _measure() async {
    if (_measuring || library == null) return;
    _measuring = true;
    try {
      final next = await StorageUsage.measure(library!.root);
      if (mounted) setState(() => usage = next);
    } catch (_) {
      /* A later refresh retries while checkpoints are being written. */
    } finally {
      _measuring = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      downloads?.refresh();
      _measure();
      auth?.refresh();
      sync?.synchronize();
      final store = habits;
      if (store != null) unawaited(reminders?.sync(store));
      reminders?.notificationsAllowed().then((allowed) {
        if (mounted && notificationsAllowed != allowed) {
          setState(() => notificationsAllowed = allowed);
        }
      });
    }
  }

  Future<void> _open(Edition edition, Chapter chapter) async {
    HapticFeedback.selectionClick();
    _reading = true;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ReaderScreen(
          library: library!,
          state: reading!,
          edition: edition,
          chapter: chapter,
          sync: sync,
          habits: habits,
        ),
      ),
    );
    _reading = false;
    _refresh();
    if (_pendingMilestones.isNotEmpty) unawaited(_showMilestones());
  }

  void _readEdition(Edition e) {
    final progress = reading!.progress[e.key];
    final slug = progress is Map ? progress['slug'] as int : 1;
    _open(e, e.chapter(slug) ?? e.chapters.first);
  }

  Future<void> _download(List<Edition> editions) async {
    try {
      HapticFeedback.lightImpact();
      await downloads!.start(editions);
      if (!downloads!.notificationsAllowed) {
        _notice(
          'Downloads will continue in the background. Enable notifications in Android settings to receive completion alerts.',
        );
      }
    } catch (e) {
      _notice('$e');
    }
  }

  void _all() {
    setState(() => tab = 3);
    _download(library!.editions);
  }

  Future<void> _verify(Edition e) async {
    try {
      _notice(
        await library!.verify(e)
            ? 'All downloaded files verified.'
            : 'This edition needs repair. Tap Resume.',
      );
    } catch (error) {
      _notice('Verification failed: $error');
    }
  }

  Future<void> _remove(Edition e) async {
    if (downloads!.busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove downloaded edition?'),
        content: Text(
          '${e.title}\n${e.language}\n\nYour progress, bookmarks, and notes will be kept. You can still read online.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await library!.remove(e);
      await _measure();
    }
  }

  Future<void> _export() async {
    try {
      final result = await files.invokeMethod<bool>('export', {
        'text': jsonEncode(reading!.data),
        'name': 'lotm-reading-backup.json',
      });
      if (result == true) _notice('Reading backup saved.');
    } catch (e) {
      _notice('Unable to save backup: $e');
    }
  }

  Future<void> _import() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore reading backup?'),
        content: const Text(
          'The selected backup will replace your progress, bookmarks, notes, and reader settings. Your account login and downloads stay on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Choose backup'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final text = await files.invokeMethod<String>('import');
      if (text != null) {
        await reading!.import(text);
        await reading!.switchProfile(auth!.userId ?? 'anonymous');
        _notice('Reading backup restored.');
      }
    } catch (e) {
      _notice('Unable to restore backup: $e');
    }
  }

  void _account() => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => AccountScreen(auth: auth!, sync: sync!),
    ),
  );

  static String _formatTime(String value) {
    final parts = value.split(':');
    final h = int.tryParse(parts.first) ?? 20;
    final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    final period = h >= 12 ? 'PM' : 'AM';
    final hour12 = h % 12 == 0 ? 12 : h % 12;
    return '$hour12:${m.toString().padLeft(2, '0')} $period';
  }

  Future<void> _setGoal(String goal) async {
    await habits?.setGoal(goal);
    if (habits != null) await reminders?.sync(habits!);
  }

  Future<void> _setReminders(bool enabled) async {
    await habits?.setRemindersEnabled(enabled);
    if (habits == null) return;
    if (enabled) {
      final allowed = await reminders?.requestPermission() ?? true;
      if (mounted) setState(() => notificationsAllowed = allowed);
      if (!allowed && mounted) {
        _notice(
          'Enable notifications in Android settings to receive reminders.',
        );
      }
    }
    await reminders?.sync(habits!);
  }

  Future<void> _setWinBack(bool enabled) async {
    await habits?.setWinBackEnabled(enabled);
    if (habits != null) await reminders?.sync(habits!);
  }

  Future<void> _chooseReminderTime() async {
    final current = habits?.reminderTime ?? defaultReminderTime;
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 20,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Daily reading reminder',
    );
    if (picked == null) return;
    final value =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    await habits?.setReminderTime(value);
    if (habits != null) await reminders?.sync(habits!);
  }

  Future<void> _requestNotificationPermission() async {
    final allowed = await reminders?.requestPermission() ?? true;
    if (mounted) setState(() => notificationsAllowed = allowed);
    if (allowed && habits != null) {
      await reminders?.sync(habits!);
    } else if (mounted) {
      _notice(
        'Notifications are still blocked. Enable them in Android settings.',
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    rewardDialogsOpen.removeListener(_rewardDialogsChanged);
    _storageTimer?.cancel();
    library?.removeListener(_refresh);
    reading?.removeListener(_refresh);
    downloads?.removeListener(_refresh);
    auth?.removeListener(_accountChanged);
    sync?.removeListener(_refresh);
    habits?.removeListener(_habitChanged);
    downloads?.dispose();
    sync?.dispose();
    habits?.dispose();
    auth?.api.dispose();
    auth?.dispose();
    library?.dispose();
    reading?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (library == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/brand/seer.webp', width: 80, height: 80),
                const SizedBox(height: 26),
                if (error == null)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Unable to open the library.\n$error'),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    final titles = [
      'Library',
      'Progress',
      'Bookmarks',
      'Downloads',
      'Settings',
    ];
    final rewards = habits?.rewardsWaiting() ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/brand/seer.webp', width: 30, height: 30),
            const SizedBox(width: 12),
            Text(
              titles[tab],
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          if (habits != null) ...[
            Tooltip(
              message: 'Reading streak — open Progress',
              child: InkWell(
                borderRadius: BorderRadius.circular(50),
                onTap: () => setState(() => tab = 1),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: gold.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.local_fire_department,
                        size: 16,
                        color: habits!.currentStreak() > 0
                            ? streakTier(habits!.currentStreak()).color
                            : muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${habits!.currentStreak()}',
                        style: const TextStyle(
                          color: gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            tooltip: auth!.user == null
                ? 'Sign in to sync reading'
                : 'Reader account',
            onPressed: _account,
            icon: auth!.user == null
                ? const Icon(Icons.account_circle_outlined)
                : CircleAvatar(
                    radius: 14,
                    backgroundColor: gold.withValues(alpha: .16),
                    child: Text(
                      auth!.email!.substring(0, 1).toUpperCase(),
                      style: const TextStyle(fontSize: 12, color: gold),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 240),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(.025, 0),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: KeyedSubtree(
            key: ValueKey(tab),
            child: switch (tab) {
              0 => _library(),
              1 =>
                habits != null
                    ? ProgressScreen(
                        habits: habits!,
                        editions: library!.editions,
                        onOpenSettings: () => setState(() => tab = 4),
                      )
                    : const SizedBox.shrink(),
              2 => _bookmarks(),
              3 => _downloads(),
              _ => _settings(),
            },
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (value) {
          HapticFeedback.selectionClick();
          setState(() => tab = value);
          if (value == 3 || value == 4) _measure();
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: rewards > 0,
              label: Text('$rewards'),
              child: const Icon(Icons.local_fire_department_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: rewards > 0,
              label: Text('$rewards'),
              child: const Icon(Icons.local_fire_department),
            ),
            label: 'Progress',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bookmark_border),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Bookmarks',
          ),
          const NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: 'Downloads',
          ),
          const NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _library() => ListView(
    key: const PageStorageKey('library'),
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    children: [
      MotionEntry(
        child: ReaderPanel(
          accent: true,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BEYOND THE GRAY FOG',
                style: TextStyle(
                  color: gold,
                  fontSize: 10,
                  letterSpacing: 2.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Another chapter.\nAnother world.',
                style: TextStyle(
                  fontSize: 34,
                  height: 1.15,
                  letterSpacing: -1.1,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Read online, wherever the story takes you.\nSave an edition for the moments without a signal.',
                style: TextStyle(color: muted, height: 1.6, fontSize: 13),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const StatusPill('2 novels', icon: Icons.menu_book_outlined),
                  const StatusPill('5 editions', icon: Icons.translate),
                  StatusPill(
                    '${library!.editions.where((e) => library!.status(e).complete).length} saved',
                    icon: Icons.offline_pin_outlined,
                    ready: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      if (habits != null)
        MotionEntry(
          delay: 40,
          child: ReaderPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: InkWell(
              onTap: () => setState(() => tab = 1),
              borderRadius: BorderRadius.circular(16),
              child: Row(
                children: [
                  Icon(
                    Icons.local_fire_department,
                    size: 26,
                    color: streakTier(habits!.currentStreak()).color,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${habits!.currentStreak()}-day streak',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${habits!.todayXp}/${habits!.goalTargetXp} XP today',
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        GlowBar(
                          value: habits!.todayGoalProgress,
                          height: 4,
                          colors: const [Color(0xffb89a5c), Color(0xffffe2a3)],
                        ),
                        if (habits!.rewardsWaiting() > 0) ...[
                          const SizedBox(height: 8),
                          Text(
                            habits!.chestAvailable()
                                ? 'Your mystery chest is ready to open'
                                : 'A weekly reward is ready to claim',
                            style: const TextStyle(
                              color: gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (habits!.rewardsWaiting() > 0)
                    const Pulse(
                      radius: 50,
                      child: Icon(Icons.redeem_rounded, size: 22, color: gold),
                    )
                  else
                    const Icon(Icons.chevron_right, size: 20, color: muted),
                ],
              ),
            ),
          ),
        ),
      const SectionLabel('Your novels'),
      for (final book in ['lotm', 'coi'])
        MotionEntry(
          key: ValueKey(book),
          delay: book == 'lotm' ? 70 : 140,
          child: _book(book),
        ),
      if (downloads!.busy)
        MotionEntry(
          child: ReaderPanel(
            accent: true,
            child: InkWell(
              onTap: () => setState(() => tab = 3),
              borderRadius: BorderRadius.circular(16),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Your library is downloading\nYou can keep reading while it saves.',
                      style: TextStyle(fontSize: 13, height: 1.5),
                    ),
                  ),
                  const Icon(Icons.arrow_forward, size: 20),
                ],
              ),
            ),
          ),
        ),
    ],
  );

  Widget _book(String book) {
    final editions = library!.editions.where((e) => e.book == book).toList();
    return ReaderPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 65,
                height: 88,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: book == 'lotm'
                        ? [const Color(0xff384449), const Color(0xff152229)]
                        : [const Color(0xff4e3540), const Color(0xff241c29)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: gold.withValues(alpha: .3)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      book == 'lotm'
                          ? Icons.visibility_outlined
                          : Icons.hourglass_bottom,
                      size: 27,
                      color: gold,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      book == 'lotm' ? 'I' : 'II',
                      style: const TextStyle(color: gold, fontSize: 18),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book == 'lotm'
                          ? 'Lord of the\nMysteries'
                          : 'Circle of\nInevitability',
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                        letterSpacing: -.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Cuttlefish That Loves Diving',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < editions.length; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1, color: Color(0xff29353f)),
              ),
            _edition(editions[i]),
          ],
        ],
      ),
    );
  }

  Widget _edition(Edition e) {
    final s = library!.status(e);
    final progress = reading!.progress[e.key];
    final slug = progress is Map ? progress['slug'] as int : 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                e.language,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (!s.complete)
              IconButton(
                color: gold,
                tooltip: s.done > 0 ? 'Resume download' : 'Download edition',
                onPressed: downloads!.busy ? null : () => _download([e]),
                icon: const Icon(Icons.download_outlined, size: 21),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${e.chapters.length} chapters',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
            StatusPill(
              s.complete
                  ? 'Saved · ${formatBytes(s.bytes)}'
                  : s.active
                  ? 'Downloading'
                  : 'Online',
              icon: s.complete
                  ? Icons.offline_pin_outlined
                  : s.active
                  ? Icons.downloading
                  : Icons.public,
              ready: s.complete,
            ),
          ],
        ),
        if (progress is Map)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value:
                    ((slug - 1 + (progress['scrollRatio'] as num)) /
                            e.chapters.length)
                        .clamp(0, 1),
                minHeight: 3,
              ),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _readEdition(e),
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: Text(
                progress == null
                    ? s.complete
                          ? 'Read'
                          : 'Read online'
                    : 'Continue · $slug',
              ),
            ),
            OutlinedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ChapterList(
                    library: library!,
                    edition: e,
                    onOpen: (c) => _open(e, c),
                  ),
                ),
              ),
              child: const Text('Chapters'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _downloads() => ListView(
    key: const PageStorageKey('downloads'),
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    children: [
      MotionEntry(child: StorageCard(usage, onRefresh: _measure)),
      MotionEntry(
        delay: 50,
        child: ReaderPanel(
          accent: downloads!.busy,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    downloads!.busy
                        ? Icons.downloading
                        : Icons.cloud_download_outlined,
                    color: gold,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      downloads!.busy
                          ? 'Saving your offline library'
                          : 'Take the story with you',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Downloads keep running when you switch apps or lock the screen. Each edition includes all chapters and available illustrations. You’ll get an alert when it’s ready.',
                style: TextStyle(color: muted, fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 16),
              if (downloads!.busy)
                OutlinedButton.icon(
                  onPressed: downloads!.pause,
                  icon: const Icon(Icons.pause, size: 18),
                  label: const Text('Pause downloads'),
                )
              else
                FilledButton.tonalIcon(
                  onPressed: _all,
                  icon: const Icon(
                    Icons.download_for_offline_outlined,
                    size: 18,
                  ),
                  label: const Text('Download all editions'),
                ),
              if (!downloads!.notificationsAllowed)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Notifications are disabled. Enable them in Android settings for completion alerts.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SectionLabel('Editions'),
      for (final e in library!.editions)
        MotionEntry(
          key: ValueKey(e.key),
          child: DownloadCard(
            edition: e,
            status: library!.status(e),
            queued: downloads!.queued.contains(e.key),
            busy: downloads!.busy,
            onDownload: () => _download([e]),
            onRemove: () => _remove(e),
            onVerify: () => _verify(e),
            onRead: () => _readEdition(e),
          ),
        ),
    ],
  );

  Widget _bookmarks() {
    final entries = reading!.bookmarks.entries.toList()
      ..sort(
        (a, b) => ((b.value['updatedAt'] ?? 0) as num).compareTo(
          (a.value['updatedAt'] ?? 0) as num,
        ),
      );
    if (entries.isEmpty) {
      return Center(
        child: MotionEntry(
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: gold.withValues(alpha: .08),
                  ),
                  child: const Icon(
                    Icons.bookmark_border_rounded,
                    size: 42,
                    color: gold,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Keep the clues close.',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w300),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Bookmark a chapter and add a note while reading. Your saved moments will appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ListView(
      key: const PageStorageKey('bookmarks'),
      padding: const EdgeInsets.all(20),
      children: [
        SectionLabel('${entries.length} saved moments'),
        for (final b in entries)
          MotionEntry(
            key: ValueKey(b.key),
            child: ReaderPanel(
              padding: EdgeInsets.zero,
              child: ListTile(
                contentPadding: const EdgeInsets.all(20),
                leading: const Icon(Icons.bookmark, color: gold),
                title: Text(
                  b.value['title'] as String? ?? b.key,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '${b.key}\n${b.value['note']}',
                    style: const TextStyle(color: muted, height: 1.5),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  final p = b.key.split('/');
                  final e = library!.editions
                      .where((e) => e.key == '${p[0]}/${p[1]}')
                      .firstOrNull;
                  final c = e?.chapter(int.parse(p[2]));
                  if (e != null && c != null) _open(e, c);
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _settings() => ListView(
    key: const PageStorageKey('settings'),
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    children: [
      MotionEntry(
        child: ReaderPanel(
          accent: true,
          padding: EdgeInsets.zero,
          child: ListTile(
            contentPadding: const EdgeInsets.all(20),
            leading: const Icon(
              Icons.account_circle_outlined,
              color: gold,
              size: 30,
            ),
            title: Text(
              auth!.email ?? 'Your reader account',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              auth!.user == null
                  ? 'Google or email · sync with the website'
                  : sync!.syncing
                  ? 'Syncing…'
                  : sync!.error ?? 'Reading progress and activity',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _account,
          ),
        ),
      ),
      const SectionLabel('Your reader'),
      MotionEntry(
        delay: 70,
        child: ReaderPanel(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.palette_outlined, color: gold),
                title: Text('Appearance'),
                subtitle: Text(
                  'Open settings inside a chapter for themes, fonts, spacing, and text controls.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
              const Divider(indent: 64, endIndent: 20),
              ListTile(
                leading: const Icon(Icons.save_alt, color: gold),
                title: const Text('Export reading backup'),
                subtitle: const Text(
                  'Progress, bookmarks, notes, and settings',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _export,
              ),
              ListTile(
                leading: const Icon(Icons.restore, color: gold),
                title: const Text('Restore reading backup'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _import,
              ),
            ],
          ),
        ),
      ),
      if (habits != null) ...[
        const SectionLabel('Daily goal & reminders'),
        MotionEntry(
          delay: 90,
          child: ReaderPanel(
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  leading: Icon(Icons.local_fire_department, color: gold),
                  title: Text('Daily goal'),
                  subtitle: Text(
                    'Pick a pace you can keep. Pages earn 2 XP, chapters earn 25.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in dailyGoals.entries)
                        ChoiceChip(
                          label: Text(
                            '${entry.value.label} · ${entry.value.xp} XP',
                          ),
                          selected: habits!.goal == entry.key,
                          onSelected: (selected) {
                            if (selected) unawaited(_setGoal(entry.key));
                          },
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    dailyGoals[habits!.goal]!.hint,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ),
                const Divider(indent: 20, endIndent: 20),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.notifications_active_outlined,
                    color: gold,
                  ),
                  title: const Text('Daily reminder'),
                  subtitle: Text(
                    habits!.remindersEnabled
                        ? 'Every day at ${_formatTime(habits!.reminderTime)}'
                        : 'Off — enable to stay on track',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                  value: habits!.remindersEnabled,
                  onChanged: (value) => unawaited(_setReminders(value)),
                ),
                if (habits!.remindersEnabled)
                  ListTile(
                    leading: const Icon(Icons.schedule, color: gold),
                    title: const Text('Reminder time'),
                    subtitle: Text(
                      _formatTime(habits!.reminderTime),
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => unawaited(_chooseReminderTime()),
                  ),
                SwitchListTile(
                  secondary: const Icon(
                    Icons.mark_email_unread_outlined,
                    color: gold,
                  ),
                  title: const Text('Come-back nudge'),
                  subtitle: const Text(
                    'Remind me after 2 days away from the reader',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  value: habits!.winBackEnabled,
                  onChanged: (value) => unawaited(_setWinBack(value)),
                ),
                if (notificationsAllowed == false)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Android notifications are blocked for this app.',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              unawaited(_requestNotificationPermission()),
                          child: const Text('Enable'),
                        ),
                      ],
                    ),
                  ),
                SwitchListTile(
                  secondary: const Icon(Icons.bolt, color: gold),
                  title: const Text('XP popups while reading'),
                  subtitle: const Text(
                    'Show earned XP and goal progress briefly in the reader',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  value: habits!.readerHud,
                  onChanged: (value) => unawaited(habits!.setReaderHud(value)),
                ),
                const Divider(indent: 20, endIndent: 20),
                ListTile(
                  leading: const Icon(Icons.ac_unit, color: frost),
                  title: const Text('Streak freezes'),
                  subtitle: Text(
                    '${habits!.freezes} of $maxFreezes banked · earned every $freezeEveryStreak streak days and used automatically. '
                    'Missed too many? Earn $rescueGoalMultiplier× your goal the day you return to rescue the streak.',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      const SectionLabel('Storage'),
      MotionEntry(delay: 120, child: StorageCard(usage, onRefresh: _measure)),
      const SectionLabel('About'),
      ReaderPanel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            const ListTile(
              leading: Icon(Icons.public, color: gold),
              title: Text('Chapter source'),
              subtitle: Text(
                defaultSource,
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined, color: gold),
              title: const Text('License and credits'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final text = await rootBundle.loadString('assets/license.md');
                if (!mounted) return;
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('License and credits')),
                      body: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: SelectableText(text),
                      ),
                    ),
                  ),
                );
              },
            ),
            const ListTile(
              leading: Icon(Icons.info_outline, color: gold),
              title: Text('LOTM Reader · 1.1.0'),
              subtitle: Text(
                'Fan translations. Support the original author and licensed releases.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
