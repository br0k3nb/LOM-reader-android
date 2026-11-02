import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lotm_reader/auth_store.dart';
import 'package:lotm_reader/cloud_sync.dart';
import 'package:lotm_reader/reader_api.dart';
import 'package:lotm_reader/state_store.dart';

class AccountTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  AccountTestBinding();
  late Directory temp;
  late HttpServer source;
  late ReaderApi api;
  late AuthStore auth;
  late StateStore state;
  late CloudSync sync;
  late List<Map<String, dynamic>> uploads;
  late List<String> cookies;
  var remoteRatio = .15;
  var remoteUpdatedAt = 10;
  var expired = false;
  var currentUser = 'account-a';
  const googleCredential = 'fixture-id-token-never-persisted';

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('reader-account');
    source = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    uploads = [];
    cookies = [];
    expired = false;
    currentUser = 'account-a';
    remoteRatio = .15;
    remoteUpdatedAt = 10;
    source.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      final path = request.uri.path;
      final cookie = request.cookies
          .where((c) => c.name == 'lotm_reader_session')
          .firstOrNull;
      cookies.add(cookie?.value ?? '');
      dynamic body;
      if (request.method == 'POST') {
        body = jsonDecode(await utf8.decoder.bind(request).join());
      }
      if (path == '/api/auth/google' ||
          path == '/api/auth/login' ||
          path == '/api/auth/register') {
        if (path.endsWith('google')) {
          expect(body['credential'], googleCredential);
        }
        expect(
          request.headers.value('Origin'),
          'http://127.0.0.1:${source.port}',
        );
        request.response.cookies.add(
          Cookie('lotm_reader_session', 'opaque-$currentUser')..httpOnly = true,
        );
        request.response.write(
          jsonEncode({
            'user': {'id': currentUser, 'email': '$currentUser@example.com'},
          }),
        );
      } else if (path == '/api/auth/session') {
        request.response.write(
          jsonEncode({
            'user': expired
                ? null
                : {'id': currentUser, 'email': '$currentUser@example.com'},
          }),
        );
      } else if (path == '/api/auth/logout') {
        request.response.cookies.add(
          Cookie('lotm_reader_session', '')..maxAge = 0,
        );
        request.response.write('{}');
      } else if (path == '/api/reading/sync') {
        if (cookie == null || expired) {
          request.response.statusCode = 401;
          request.response.write('{"error":"Authentication required."}');
        } else {
          if (body is Map) uploads.add(Map<String, dynamic>.from(body));
          request.response.write(
            jsonEncode({
              'progress': [
                {
                  'book': 'lotm',
                  'tl': 'webnovel',
                  'slug': 1,
                  'scroll': 120,
                  'scrollRatio': remoteRatio,
                  'pageIndex': 0,
                  'updatedAt': remoteUpdatedAt,
                },
              ],
              'daily': {'2026-09-30': 7},
              'chapters': {'lotm\u0000webnovel': 2},
            }),
          );
        }
      } else {
        request.response.statusCode = 404;
        request.response.write('{}');
      }
      await request.response.close();
    });
    api = ReaderApi(source: 'http://127.0.0.1:${source.port}');
    auth = AuthStore(api);
    state = StateStore(File('${temp.path}/state.json'));
    await state.load();
    sync = CloudSync(auth, state, File('${temp.path}/sync.json'));
    await sync.initialize();
  });
  tearDown(() async {
    sync.dispose();
    auth.dispose();
    api.dispose();
    state.dispose();
    await source.close(force: true);
    await temp.delete(recursive: true);
  });

  Future<void> settleSync() async {
    for (var i = 0; i < 100 && sync.syncing; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(sync.syncing, false);
  }

  test(
    'Google exchange shares website session without persisting the Google token',
    () async {
      final googleAuth = AuthStore(
        api,
        googleTokenProvider: () async => googleCredential,
      );
      expect(await googleAuth.googleSignIn(), true);
      expect(googleAuth.userId, 'account-a');
      expect(api.session, 'opaque-account-a');
      await api.request('/api/auth/session');
      expect(cookies.last, 'opaque-account-a');
      final stored = await const FlutterSecureStorage().readAll();
      expect(stored['reader_account'], contains('opaque-account-a'));
      expect(jsonEncode(stored), isNot(contains(googleCredential)));
      expect(
        await state.file.readAsString().catchError((Object _) => ''),
        isNot(contains(googleCredential)),
      );
      googleAuth.dispose();
    },
  );

  test(
    'Google cancellation is visible and a second attempt can succeed',
    () async {
      var attempts = 0;
      final googleAuth = AuthStore(
        api,
        googleTokenProvider: () async {
          if (++attempts == 1) {
            throw const GoogleSignInException(
              code: GoogleSignInExceptionCode.canceled,
            );
          }
          return googleCredential;
        },
      );
      expect(await googleAuth.googleSignIn(), false);
      expect(googleAuth.error, contains('no account chooser opens'));
      expect(googleAuth.busy, false);
      expect(googleAuth.busyMessage, isNull);
      expect(api.session, isNull);
      expect(cookies, isEmpty);
      expect(await googleAuth.googleSignIn(), true);
      expect(googleAuth.error, isNull);
      expect(googleAuth.userId, 'account-a');
      googleAuth.dispose();
    },
  );

  test(
    'email session survives restart, retains identity offline, and signs out locally',
    () async {
      expect(
        await auth.emailSignIn('account-a@example.com', 'password-123'),
        true,
      );
      final reopenedApi = ReaderApi(source: api.source);
      final reopenedAuth = AuthStore(reopenedApi);
      await reopenedAuth.initialize();
      expect(reopenedAuth.userId, 'account-a');
      expect(reopenedApi.session, 'opaque-account-a');
      await source.close(force: true);
      await reopenedAuth.refresh();
      expect(reopenedAuth.userId, 'account-a');
      await reopenedAuth.signOut();
      expect(reopenedAuth.user, isNull);
      expect(
        await const FlutterSecureStorage().read(key: 'reader_account'),
        isNull,
      );
      reopenedAuth.dispose();
      reopenedApi.dispose();
    },
  );

  test(
    'offline page queue merges on sign-in and newer local progress wins',
    () async {
      await state.saveProgress('lotm/webnovel', 1, .75, scroll: 1600);
      await sync.record('lotm/webnovel', 1, 1600);
      await sync.record('lotm/webnovel', 1, 1600);
      expect(sync.pending, 3);
      expect(
        await auth.emailSignIn('account-a@example.com', 'password-123'),
        true,
      );
      await sync.activate();
      await settleSync();
      expect(sync.pending, 0);
      expect(state.progress['lotm/webnovel']['scrollRatio'], .75);
      expect(uploads.expand((p) => p['events'] as List), hasLength(3));
      expect(uploads.first['progress']['pageIndex'], 2);
      expect(sync.chapters.values, [2]);
      expect(sync.daily['2026-09-30'], 7);
      expect(sync.error, isNull);
    },
  );

  test(
    'remote newer positions merge; different accounts keep separate progress',
    () async {
      await auth.emailSignIn('account-a@example.com', 'password-123');
      await sync.activate();
      await settleSync();
      remoteUpdatedAt = DateTime.now().millisecondsSinceEpoch + 1000;
      remoteRatio = .9;
      await sync.synchronize();
      expect(state.progress['lotm/webnovel']['scrollRatio'], .9);
      await auth.signOut();
      await sync.activate();
      expect(state.owner, 'anonymous');
      expect(state.progress, isEmpty);
      currentUser = 'account-b';
      remoteRatio = .2;
      await auth.emailSignIn('account-b@example.com', 'password-123');
      await sync.activate();
      await settleSync();
      expect(state.owner, 'account-b');
      expect(state.progress['lotm/webnovel']['scrollRatio'], .2);
      expect(
        state.data['profiles']['account-a']['lotm/webnovel']['scrollRatio'],
        .9,
      );
      expect(jsonEncode(state.data), isNot(contains('opaque-')));
    },
  );
}
