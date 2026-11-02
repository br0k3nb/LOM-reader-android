import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'library_store.dart';
import 'models.dart';
import 'storage_usage.dart';

Future<void> writeJson(File file, Object value) async {
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.tmp');
  await temporary.writeAsString(jsonEncode(value), flush: true);
  await temporary.rename(file.path);
}

/// A separate Flutter engine owns downloads. Closing the activity never owns or
/// disposes its HTTP client. Queue and checkpoints survive service restarts.
class BackgroundDownloads extends ChangeNotifier {
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  BackgroundDownloads(this.library);
  final LibraryStore library;
  List<String> queued = [];
  bool running = false;
  bool starting = false;
  bool notificationsAllowed = true;
  Timer? _poll;
  bool _refreshing = false;
  bool _loaded = false;
  bool _disposed = false;
  File get _snapshot => File('${library.root.path}/download-status.json');
  File get _queue => File('${library.root.path}/download-queue.json');
  bool get busy => running || starting;

  Future<void> initialize() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'reader_downloads',
        channelName: 'Book downloads',
        channelDescription: 'Background download progress',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        allowWakeLock: true,
        allowWifiLock: false,
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
    FlutterForegroundTask.addTaskDataCallback(_receive);
    await refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
  }

  void _receive(Object data) {
    if (data is! Map) return;
    _apply(Map<String, dynamic>.from(data));
  }

  void _apply(Map<String, dynamic> data) {
    if (_disposed) return;
    queued = List<String>.from(data['queue'] as List? ?? []);
    final statuses = data['statuses'];
    if (statuses is Map) {
      library.applyDownloadSnapshot(statuses);
    }
    _notify();
  }

  Future<void> refresh() async {
    if (_refreshing || _disposed) return;
    _refreshing = true;
    try {
      final wasRunning = running;
      running = await FlutterForegroundTask.isRunningService;
      if (_disposed) return;
      if (running && await _snapshot.exists()) {
        _apply(
          jsonDecode(await _snapshot.readAsString()) as Map<String, dynamic>,
        );
      } else if (!running && (wasRunning || !_loaded)) {
        _loaded = true;
        if (wasRunning && await _snapshot.exists()) {
          _apply(
            jsonDecode(await _snapshot.readAsString()) as Map<String, dynamic>,
          );
        }
        for (final s in library.statuses.values) {
          s.active = false;
        }
        if (await _queue.exists()) {
          final saved = jsonDecode(await _queue.readAsString()) as Map;
          queued = List<String>.from(saved['editions'] as List? ?? []);
        }
        // The manifest is authoritative after the worker stops; never restore a
        // stale snapshot after a user removes or repairs a downloaded edition.
        await library.initialize();
        _notify();
      }
    } catch (_) {
      /* A service transition is retried on the next tick. */
    } finally {
      _refreshing = false;
    }
  }

  Future<void> start(List<Edition> editions) async {
    if (busy) throw StateError('Pause the current download first.');
    final keys = editions
        .where((e) => !library.status(e).complete)
        .map((e) => e.key)
        .toList();
    if (keys.isEmpty) return;
    starting = true;
    _notify();
    try {
      var permission =
          await FlutterForegroundTask.checkNotificationPermission();
      if (permission != NotificationPermission.granted) {
        permission =
            await FlutterForegroundTask.requestNotificationPermission();
      }
      notificationsAllowed = permission == NotificationPermission.granted;
      queued = keys;
      await writeJson(_queue, {'editions': keys, 'paused': false});
      if (await _snapshot.exists()) await _snapshot.delete();
      await FlutterForegroundTask.saveData(
        key: 'libraryRoot',
        value: library.root.path,
      );
      await FlutterForegroundTask.saveData(
        key: 'chapterSource',
        value: library.source,
      );
      final result = await FlutterForegroundTask.startService(
        serviceId: 8201,
        serviceTypes: [ForegroundServiceTypes.dataSync],
        notificationTitle: 'Preparing your offline library',
        notificationText: '${keys.length} edition(s) queued',
        notificationIcon: const NotificationIcon(
          metaDataName: 'dev.lotm.reader.notification_icon',
        ),
        notificationButtons: [
          const NotificationButton(id: 'pause', text: 'Pause'),
        ],
        callback: downloadServiceCallback,
      );
      if (result is ServiceRequestFailure) {
        throw StateError(
          'Unable to start background downloads: ${result.error}',
        );
      }
      running = true;
    } finally {
      starting = false;
      _notify();
    }
  }

  void pause() {
    if (running) FlutterForegroundTask.sendDataToTask({'action': 'pause'});
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    FlutterForegroundTask.removeTaskDataCallback(_receive);
    super.dispose();
  }
}

@pragma('vm:entry-point')
void downloadServiceCallback() {
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(BookDownloadTask());
}

class BookDownloadTask extends TaskHandler {
  LibraryStore? _library;
  List<String> _queue = [];
  bool _paused = false;
  Future<void> _pendingPublish = Future.value();
  bool _finished = false;
  final _notifications = FlutterLocalNotificationsPlugin();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    unawaited(_run()); // Return promptly so the service can receive Pause.
  }

  Future<void> _run() async {
    try {
      final path = await FlutterForegroundTask.getData<String>(
        key: 'libraryRoot',
      );
      final source = await FlutterForegroundTask.getData<String>(
        key: 'chapterSource',
      );
      if (path == null) throw StateError('Missing library location');
      final queueFile = File('$path/download-queue.json');
      final saved = jsonDecode(await queueFile.readAsString()) as Map;
      _queue = List<String>.from(saved['editions'] as List);
      if (saved['paused'] == true) return;
      final library = _library = LibraryStore(
        Directory(path),
        parseCatalog(await rootBundle.loadString('assets/meta.json')),
        source: source ?? defaultSource,
      );
      await library.initialize();
      try {
        await _notifications.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('ic_notification'),
          ),
        );
      } catch (_) {
        /* Downloading does not depend on notification permission. */
      }
      while (!_paused && _queue.isNotEmpty) {
        final key = _queue.first;
        final edition = library.editions.where((e) => e.key == key).first;
        await _publish();
        if (!library.status(edition).complete) await library.download(edition);
        if (!library.status(edition).complete) break;
        _queue.removeAt(0);
        await writeJson(queueFile, {'editions': _queue, 'paused': _paused});
        await _publish();
        // Failure to post an alert never interrupts the download queue.
        try {
          await _notifications.show(
            id: 8300 + library.editions.indexOf(edition),
            title: 'Ready to read offline',
            body:
                '${edition.title} · ${edition.language}\n${edition.chapters.length} chapters · ${formatBytes(library.status(edition).bytes)} saved',
            notificationDetails: const NotificationDetails(
              android: AndroidNotificationDetails(
                'reader_completed',
                'Completed downloads',
                channelDescription: 'Alerts when a book is ready offline',
                importance: Importance.high,
                priority: Priority.high,
                icon: 'ic_notification',
                autoCancel: true,
              ),
            ),
            payload: edition.key,
          );
        } catch (_) {
          /* Notifications may be disabled in Android settings. */
        }
      }
      await writeJson(queueFile, {'editions': _queue, 'paused': true});
      await _publish();
    } catch (error) {
      final library = _library;
      if (library != null && _queue.isNotEmpty) {
        final e = library.editions
            .where((e) => e.key == _queue.first)
            .firstOrNull;
        if (e != null) library.status(e).error = '$error';
        await _publish();
      }
    } finally {
      _finished = true;
      await FlutterForegroundTask.stopService();
    }
  }

  Future<void> _publish() {
    _pendingPublish = _pendingPublish
        .catchError((Object _) {})
        .then((_) => _publishNow());
    return _pendingPublish;
  }

  Future<void> _publishNow() async {
    final library = _library;
    if (library == null || _finished) return;
    final data = {
      'queue': _queue,
      'statuses': {
        for (final e in library.editions) e.key: library.status(e).toJson(),
      },
    };
    await writeJson(File('${library.root.path}/download-status.json'), data);
    FlutterForegroundTask.sendDataToMain(data);
    if (_queue.isNotEmpty) {
      final e = library.editions.where((e) => e.key == _queue.first).first;
      final s = library.status(e);
      await FlutterForegroundTask.updateService(
        notificationTitle: e.title,
        notificationText:
            '${s.phase} · ${s.done}/${s.total} chapters · ${formatBytes(s.bytes)} · ${formatEta(s.etaSeconds)}',
      );
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_publish());
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map && data['action'] == 'pause') {
      _paused = true;
      _library?.pause();
    }
  }

  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'pause') onReceiveData({'action': 'pause'});
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _paused = true;
    _library?.pause();
    if (!_finished && _library != null) {
      await writeJson(File('${_library!.root.path}/download-queue.json'), {
        'editions': _queue,
        'paused': true,
      });
    }
    _library?.dispose();
  }
}
