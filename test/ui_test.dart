import 'dart:io';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lotm_reader/account_screen.dart';
import 'package:lotm_reader/auth_store.dart';
import 'package:lotm_reader/cloud_sync.dart';
import 'package:lotm_reader/design.dart';
import 'package:lotm_reader/models.dart';
import 'package:lotm_reader/reader_api.dart';
import 'package:lotm_reader/state_store.dart';
import 'package:lotm_reader/storage_usage.dart';
import 'package:lotm_reader/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('ReaderRoboto')
      ..addFont(rootBundle.load('assets/brand/Roboto.ttf'));
    await fonts.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  Future<void> screenshot(
    WidgetTester tester,
    GlobalKey key,
    String name,
  ) async {
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/ui-preview/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final width in [360.0, 600.0]) {
    testWidgets(
      'download metrics and account controls fit at $width with enlarged text',
      (tester) async {
        tester.view.physicalSize = Size(width, 940);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final key = GlobalKey();
        final status = DownloadStatus()
          ..total = 1435
          ..done = 410
          ..bytes = 45678900
          ..estimatedBytes = 159876500
          ..etaSeconds = 735
          ..bytesPerSecond = 145000
          ..active = true
          ..phase = 'Downloading chapters';
        Widget app(Widget child) => MaterialApp(
          theme: readerTheme().copyWith(
            textTheme: readerTheme().textTheme.apply(
              fontFamily: 'ReaderRoboto',
            ),
            primaryTextTheme: readerTheme().primaryTextTheme.apply(
              fontFamily: 'ReaderRoboto',
            ),
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.25)),
            child: child!,
          ),
          home: RepaintBoundary(key: key, child: child),
        );
        await tester.pumpWidget(
          app(
            Scaffold(
              appBar: AppBar(title: const Text('Downloads')),
              body: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const StorageCard(
                    StorageUsage(
                      downloads: 45000000,
                      app: 56800000,
                      data: 46000000,
                      free: 12700000000,
                    ),
                  ),
                  const SectionLabel('Editions'),
                  DownloadCard(
                    edition: const Edition('lotm', 'oldtl', []),
                    status: status,
                    queued: true,
                    busy: true,
                    onDownload: () {},
                    onRemove: () {},
                    onVerify: () {},
                    onRead: () {},
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Chapters remaining'), findsOneWidget);
        await screenshot(tester, key, 'downloads-${width.toInt()}');
        final api = ReaderApi();
        final auth = AuthStore(api);
        final state = StateStore(File('build/ui-preview/unused-state.json'));
        final sync = CloudSync(
          auth,
          state,
          File('build/ui-preview/unused-sync.json'),
        );
        await tester.pumpWidget(app(AccountScreen(auth: auth, sync: sync)));
        await tester.runAsync(() async {
          await precacheImage(
            const AssetImage('assets/brand/seer.webp'),
            key.currentContext!,
          );
          await precacheImage(
            const AssetImage('assets/brand/google_g.png'),
            key.currentContext!,
          );
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await screenshot(tester, key, 'account-${width.toInt()}');
        await tester.tap(find.text('Create account').first);
        await tester.pumpAndSettle();
        expect(find.text('Confirm password'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        sync.dispose();
        state.dispose();
        auth.dispose();
        api.dispose();
      },
    );
  }
  testWidgets('entrance animation respects reduced motion', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MotionEntry(delay: 500, child: Text('Ready')),
        ),
      ),
    );
    final fade = tester.widget<FadeTransition>(
      find
          .descendant(
            of: find.byType(MotionEntry),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Google tap shows progress and exposes silent cancellation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final chooser = Completer<String>();
    var attempts = 0;
    final api = ReaderApi();
    final auth = AuthStore(
      api,
      googleTokenProvider: () {
        attempts++;
        return chooser.future;
      },
    );
    final state = StateStore(File('build/ui-preview/unused-state.json'));
    final sync = CloudSync(
      auth,
      state,
      File('build/ui-preview/unused-sync.json'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: readerTheme(),
        home: AccountScreen(auth: auth, sync: sync),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    expect(attempts, 1);
    expect(find.text('Opening Google…'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Continue with Google'),
    );
    expect(button.onPressed, isNull);
    chooser.completeError(
      const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SnackBar),
        matching: find.text(auth.error!),
      ),
      findsOneWidget,
    );
    expect(auth.busy, false);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    sync.dispose();
    state.dispose();
    auth.dispose();
    api.dispose();
  });
  testWidgets(
    'library initializes, browses chapters, and switches tabs without a device',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('reader-library-ui'),
      ))!;
      addTearDown(
        () => tester.runAsync(() => directory.delete(recursive: true)),
      );
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter_foreground_task/methods'),
        (call) async => call.method == 'isRunningService' ? false : null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('dev.lotm.reader/storage'),
        (call) async => {
          'appBytes': 56800000,
          'dataBytes': 0,
          'freeBytes': 12700000000,
        },
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('flutter_foreground_task/methods'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('dev.lotm.reader/storage'),
          null,
        );
      });
      tester.view.physicalSize = const Size(360, 940);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: readerTheme(),
          home: RepaintBoundary(
            key: key,
            child: LibraryHome(supportDirectory: directory),
          ),
        ),
      );
      for (
        var i = 0;
        i < 100 &&
            find.text('Another chapter.\nAnother world.').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
      }
      expect(find.text('Another chapter.\nAnother world.'), findsOneWidget);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 10),
      );
      expect(find.text('Read online'), findsWidgets);
      expect(tester.takeException(), isNull);
      await screenshot(tester, key, 'library-360');
      await tester.tap(find.text('Chapters').first);
      await tester.pumpAndSettle();
      expect(find.text('1435 chapters'), findsOneWidget);
      expect(
        find.text('Download the entire edition before reading.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Downloads').last);
      await tester.pumpAndSettle();
      expect(find.text('Download all editions'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    },
  );
  test('storage uses decimal GB and sums actual persistent files', () async {
    final directory = await Directory.systemTemp.createTemp('reader-storage');
    addTearDown(() => directory.delete(recursive: true));
    await File(
      '${directory.path}/chapter.html',
    ).writeAsBytes(List.filled(1024, 1));
    final sub = Directory('${directory.path}/images');
    await sub.create();
    await File('${sub.path}/cover.webp').writeAsBytes(List.filled(2048, 2));
    expect(await directoryBytes(directory), 3072);
    expect(formatBytes(1500000000), '1.500 GB');
    expect(formatBytes(45000000, gb: true), '0.045 GB');
    expect(formatEta(735), '~13 min');
  });
}
