import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lotm_reader/auth_store.dart';
import 'package:lotm_reader/habit_store.dart';
import 'package:lotm_reader/habit_sync.dart';
import 'package:lotm_reader/reader_api.dart';

class HabitSyncTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

/// Recursively sorted JSON, so equal documents compare equal as strings.
String canon(Object? value) {
  Object? sort(Object? v) => v is Map
      ? {
          for (final key in v.keys.map((k) => '$k').toList()..sort())
            key: sort(v[key]),
        }
      : v is List
      ? [for (final item in v) sort(item)]
      : v;
  return jsonEncode(sort(value));
}

Map<String, dynamic> asMap(Object? value) =>
    Map<String, dynamic>.from(value as Map);

void main() {
  HabitSyncTestBinding();

  // ------------------------------------------------------------------
  // The website generates these vectors from its TypeScript merge
  // (npm run test:habits -- --write-vectors); both sides must agree.
  group('website merge vectors', () {
    final vectors = asMap(
      jsonDecode(
        File('test/fixtures/habit_sync_vectors.json').readAsStringSync(),
      ),
    );

    for (final raw in vectors['apply'] as List) {
      final v = asMap(raw);
      test('apply: ${v['name']}', () {
        final now = DateTime.parse(v['now'] as String);
        final result = applyDelta(asMap(v['doc']), asMap(v['delta']), now);
        expect(canon(result), canon(v['expected']));
        expect(canon(validateDoc(v['expected'], now)), canon(v['expected']));
      });
    }

    for (final raw in vectors['diff'] as List) {
      final v = asMap(raw);
      test('diff: ${v['name']}', () {
        expect(
          canon(diffDocs(asMap(v['local']), asMap(v['base']))),
          canon(v['expected']),
        );
      });
    }

    test('daily quests and chests are chosen identically', () async {
      final temp = await Directory.systemTemp.createTemp('habit-vectors');
      addTearDown(() => temp.delete(recursive: true));
      final store = HabitStore(File('${temp.path}/habits.json'));
      await store.load();
      for (final entry in asMap(vectors['quests']).entries) {
        expect(
          [for (final q in store.questsFor(entry.key)) '${q.id}:${q.target}'],
          entry.value,
          reason: entry.key,
        );
      }
      for (final entry in asMap(vectors['chests']).entries) {
        final chest = store.chestFor(entry.key);
        expect(
          {'rarity': chest.rarity, 'xp': chest.xp, 'freeze': chest.freeze},
          entry.value,
          reason: entry.key,
        );
      }
      store.dispose();
    });
  });

  // ------------------------------------------------------------------
  group('HabitSync with a website fixture', () {
    late Directory temp;
    late HttpServer server;
    late ReaderApi api;
    late AuthStore auth;
    late HabitStore habits;
    late HabitSync sync;
    late Map<String, dynamic> remote;
    late List<String> applied;
    late List<Map<String, dynamic>> uploads;
    var dropNextResponse = false;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      temp = await Directory.systemTemp.createTemp('habit-sync');
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      remote = freshDoc();
      applied = [];
      uploads = [];
      dropNextResponse = false;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        final path = request.uri.path;
        dynamic body;
        if (request.method == 'POST') {
          body = jsonDecode(await utf8.decoder.bind(request).join());
        }
        if (path == '/api/auth/login') {
          request.response.cookies.add(
            Cookie('lotm_reader_session', 'opaque')..httpOnly = true,
          );
          request.response.write(
            jsonEncode({
              'user': {'id': 'account-a', 'email': 'a@example.com'},
            }),
          );
        } else if (path == '/api/auth/logout') {
          request.response.write('{}');
        } else if (path == '/api/reading/habits') {
          if (body is Map) {
            uploads.add(asMap(body));
            expect(body['version'], habitSyncVersion);
            final id = body['id'] as String;
            // The server applies each id once, like reader_habits.applied.
            if (!applied.contains(id)) {
              remote = applyDelta(remote, asMap(body['delta']));
              applied.add(id);
            }
          }
          if (dropNextResponse) {
            dropNextResponse = false;
            request.response.statusCode = 503;
            request.response.write('{"error":"temporarily unavailable"}');
          } else {
            request.response.write(jsonEncode({'habits': remote}));
          }
        } else {
          request.response.statusCode = 404;
          request.response.write('{}');
        }
        await request.response.close();
      });
      api = ReaderApi(source: 'http://127.0.0.1:${server.port}');
      auth = AuthStore(api);
      habits = HabitStore(File('${temp.path}/habits.json'));
      await habits.load();
      sync = HabitSync(auth, habits, temp);
      await sync.initialize();
    });

    tearDown(() async {
      sync.dispose();
      habits.dispose();
      auth.dispose();
      api.dispose();
      await server.close(force: true);
      await temp.delete(recursive: true);
    });

    Future<void> signIn() async {
      expect(await auth.emailSignIn('a@example.com', 'password'), isTrue);
      await sync.activate();
      await sync.synchronize();
    }

    Future<void> read(int slug, int pages, {num? ratio}) =>
        habits.recordReading(
          edition: 'lotm/webnovel',
          slug: slug,
          scroll: (pages - 1) * 800,
          ratio: ratio,
        );

    test('signing in moves this phone\'s habits into the account', () async {
      await read(1, 10);
      expect(habits.totalPages, 10);
      await signIn();
      expect(habits.file.path, endsWith('habits-account-a.json'));
      expect(remote['totalPages'], 10);
      expect(habits.totalPages, 10);
      final anonymous = jsonDecode(
        await File('${temp.path}/habits.json').readAsString(),
      );
      expect(anonymous['totalPages'], 0, reason: 'anonymous profile reset');
    });

    test('reading on the website adds up with the phone', () async {
      await signIn();
      await read(1, 12);
      await sync.synchronize();
      expect(remote['totalPages'], 12);
      // Another device (the website) uploads its own reading for today.
      final today = dateKey(DateTime.now());
      remote = applyDelta(remote, {
        'add': {'totalPages': 20, 'totalXp': 40},
        'days': {
          today: {'pages': 20, 'xp': 40},
        },
      });
      await sync.synchronize();
      expect(habits.totalPages, 32);
      expect(habits.todayPages, 32);
      expect(habits.totalXp, remote['totalXp']);
      // 24 XP on the phone + 40 on the web meets the 50 XP goal together.
      expect(habits.goalMetToday, isTrue);
      await read(1, 20); // 8 more pages on the phone
      await sync.synchronize();
      expect(remote['totalPages'], 40);
      expect(canon(toDoc(habits.data)), canon(remote));
    });

    test('a lost response is retried with the same id, never twice', () async {
      await signIn();
      await read(2, 6);
      dropNextResponse = true;
      await sync.synchronize();
      expect(sync.error, isNotNull);
      expect(remote['totalPages'], 6, reason: 'server applied it once');
      await sync.synchronize();
      expect(sync.error, isNull);
      expect(remote['totalPages'], 6, reason: 'retry did not double count');
      expect(
        uploads[uploads.length - 1]['id'],
        uploads[uploads.length - 2]['id'],
      );
      expect(habits.totalPages, 6);
    });

    test('goal changes travel last-writer-wins', () async {
      await signIn();
      await habits.setGoal('intense');
      await sync.synchronize();
      expect(remote['goal'], 'intense');
      remote = applyDelta(remote, {
        'goal': {
          'value': 'casual',
          'at': DateTime.now().millisecondsSinceEpoch + 1000,
        },
      });
      await sync.synchronize();
      expect(habits.goal, 'casual');
    });

    test('signing out returns to this phone\'s own profile', () async {
      await signIn();
      await read(3, 5);
      await sync.synchronize();
      await auth.signOut();
      await sync.activate();
      expect(habits.file.path, endsWith('habits.json'));
      expect(habits.totalPages, 0);
      expect(auth.userId, isNull);
    });
  });
}
