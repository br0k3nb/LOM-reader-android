import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lotm_reader/background_downloads.dart';
import 'package:lotm_reader/library_store.dart';
import 'package:lotm_reader/models.dart';

class ServiceTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  final binding = ServiceTestBinding();
  late Directory temp;
  late HttpServer source;
  late Completer<void> stopped;
  late Map<String, int> requests;
  late List<MethodCall> alerts;
  var serviceRunning = true;
  BookDownloadTask? task;
  var pauseOnRequest = false;
  const article =
      '<h1>Chapter</h1><p>Exact content.</p><img src="/assets/images/lotm/test.webp">';
  final catalog = jsonEncode({
    'lotm': {
      'webnovel': [
        for (var i = 1; i <= 8; i++)
          {
            'slug': i,
            'title': 'Chapter $i',
            'category': 'Volume 1',
            'index': i,
          },
      ],
    },
  });
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    temp = await Directory.systemTemp.createTemp('reader-background');
    source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    stopped = Completer<void>();
    alerts = [];
    requests = {};
    serviceRunning = true;
    pauseOnRequest = false;
    SharedPreferences.setMockInitialValues({});
    await FlutterForegroundTask.saveData(
      key: 'libraryRoot',
      value: '${temp.path}/library',
    );
    await FlutterForegroundTask.saveData(
      key: 'chapterSource',
      value: 'http://127.0.0.1:${source.port}',
    );
    await writeJson(File('${temp.path}/library/download-queue.json'), {
      'editions': ['lotm/webnovel'],
      'paused': false,
    });
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      if (utf8.decode(message!.buffer.asUint8List()) == 'assets/meta.json') {
        return ByteData.sublistView(utf8.encode(catalog));
      }
      return null;
    });
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_foreground_task/methods'),
      (call) async {
        if (call.method == 'isRunningService') return serviceRunning;
        if (call.method == 'stopService') {
          serviceRunning = false;
          if (!stopped.isCompleted) stopped.complete();
        }
        return null;
      },
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async {
        if (call.method == 'show') alerts.add(call);
        return true;
      },
    );
    source.listen((request) async {
      final path = request.uri.path;
      requests[path] = (requests[path] ?? 0) + 1;
      if (pauseOnRequest && path.startsWith('/read/')) {
        pauseOnRequest = false;
        task!.onNotificationButtonPressed('pause');
      }
      if (path.startsWith('/read/')) {
        request.response.write(
          '<article class="chapter-content">$article</article>',
        );
      } else {
        request.response.add([
          ...ascii.encode('RIFF'),
          0,
          0,
          0,
          0,
          ...ascii.encode('WEBP'),
          0,
        ]);
      }
      await request.response.close();
    });
  });
  tearDown(() async {
    await source.close(force: true);
    await temp.delete(recursive: true);
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('flutter_foreground_task/methods'),
      null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      null,
    );
  });

  test(
    'worker finishes after UI disposal, persists readiness, and posts completion alert',
    () async {
      final ui = LibraryStore(
        Directory('${temp.path}/library'),
        parseCatalog(catalog),
      );
      await ui.initialize();
      task = BookDownloadTask();
      await task!.onStart(DateTime.now(), TaskStarter.developer);
      ui.dispose();
      await stopped.future.timeout(const Duration(seconds: 10));
      final manifest =
          jsonDecode(
                await File(
                  '${temp.path}/library/lotm/webnovel/complete.json',
                ).readAsString(),
              )
              as Map;
      expect(manifest['chapters'], 8);
      expect(requests['/assets/images/lotm/test.webp'], 1);
      expect(
        await File(
          '${temp.path}/library/lotm/webnovel/chapters/1.html',
        ).readAsString(),
        article,
      );
      final status =
          jsonDecode(
                await File(
                  '${temp.path}/library/download-status.json',
                ).readAsString(),
              )
              as Map;
      final saved = status['statuses']['lotm/webnovel'] as Map;
      expect(saved['complete'], true);
      expect(saved['bytes'], greaterThan(0));
      expect(saved['etaSeconds'], 0);
      expect(alerts, hasLength(1));
      expect(alerts.single.arguments['title'], 'Ready to read offline');
      expect(alerts.single.arguments['payload'], 'lotm/webnovel');
    },
  );

  test(
    'notification Pause checkpoints safely and a restarted worker resumes',
    () async {
      final checkpoint = File(
        '${temp.path}/library/lotm/webnovel/chapters/1.html',
      );
      await checkpoint.parent.create(recursive: true);
      await checkpoint.writeAsString(article);
      pauseOnRequest = true;
      task = BookDownloadTask();
      await task!.onStart(DateTime.now(), TaskStarter.developer);
      await stopped.future.timeout(const Duration(seconds: 10));
      expect(
        await File('${temp.path}/library/lotm/webnovel/complete.json').exists(),
        false,
      );
      expect(alerts, isEmpty);
      final queue =
          jsonDecode(
                await File(
                  '${temp.path}/library/download-queue.json',
                ).readAsString(),
              )
              as Map;
      expect(queue['paused'], true);
      expect(queue['editions'], ['lotm/webnovel']);
      await writeJson(File('${temp.path}/library/download-queue.json'), {
        'editions': queue['editions'],
        'paused': false,
      });
      serviceRunning = true;
      stopped = Completer<void>();
      task = BookDownloadTask();
      await task!.onStart(DateTime.now(), TaskStarter.system);
      await stopped.future.timeout(const Duration(seconds: 10));
      expect(
        await File('${temp.path}/library/lotm/webnovel/complete.json').exists(),
        true,
      );
      expect(requests['/read/lotm/webnovel/1'], isNull);
      expect(await checkpoint.readAsString(), article);
      expect(alerts, hasLength(1));
    },
  );
}
