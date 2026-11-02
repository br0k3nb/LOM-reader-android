# LOTM Reader for Android

A standalone Flutter app with online reading and downloadable offline editions of **Lord of the Mysteries** and **Circle of Inevitability**. The source is `https://lotmreader.vercel.app`.

## Reading and downloads

1. Install the APK and open **Library**.
2. Tap **Read online**, **Continue**, or any chapter in **Chapters** to read immediately. Every book and all five editions support online reading without downloading first. Chapter navigation and switching translations also work online. Online reading fetches only the opened chapter and its illustrations, without saving an edition.
3. For offline reading, tap **Download edition** or use **Downloads**. Each download includes the entire edition and every illustration available on the source website. **Download all editions** queues the five editions.
4. Wait for **Available offline**. Completed editions automatically use their saved chapters and illustrations without internet. Partial editions remain readable online; they require a completed download before reading offline.

Downloads run in a separate Android foreground service, so you can lock the screen, switch apps, or dismiss the reader activity. The ongoing notification shows chapter progress, saved bytes, and a time estimate, with a **Pause** action. A separate completion notification appears when each edition is ready. Allow notification permission when prompted to receive alerts. Four chapter requests run concurrently; illustrations follow the chapters.

If the connection fails, Android force-stops the app, or the phone restarts, successful chapters and illustrations remain saved; **Resume** continues from those checkpoints. Force-stop and reboot require reopening the app and resuming. Android 15+ limits background `dataSync` services to six hours per 24-hour period; a system timeout safely pauses the queue. Bringing the app to the foreground resets Android's quota. Manufacturer battery restrictions may also interrupt a service.

The **Downloads** and **Settings** pages show storage in decimal GB: installed APK files plus private app data and cache, downloaded files, other app data, and free device space. This measures disk storage, not RAM; Android's Storage settings may also include optimized runtime files. Sizes refresh while downloading. Download cards show saved bytes, transfer speed, an estimated chapter size, and time to finish the current phase. Chapter estimates exclude illustrations until that phase begins, when estimates update from actual illustration sizes and completion times.

Downloads live in Android's persistent app data, outside WebView caches. Closing the app, restarting the phone, and disabling internet do not remove them. Uninstalling the app or clearing its storage removes downloads and reading data. **Remove download** retains your progress and bookmarks. **Verify files** checks SHA-256 hashes and enables repair when a damaged file is found.

Illustrations returning HTTP 404 on the source website are reported as unavailable. Their original HTML remains intact; the offline renderer preserves the unavailable image instead of replacing it. Other download failures prevent completion and can be retried.

The app includes chapter and volume browsing, title/number search, search inside downloaded text, saved position, bookmarks with notes, and JSON export/import through Android's file picker. Reading backups include appearance settings, but do not contain downloaded novels.

## Accounts and Google sign-in

Open the account button in the toolbar or **Settings → Your reader account**. Google sign-in, email sign-in, and account registration use the original website's `/api/auth/*` endpoints. Google returns a native ID token; the existing website verifies it and creates the same reader account/session as the web version. No Firebase backend is introduced.

The opaque website session is stored with Android Keystore-backed secure storage. Google ID tokens and passwords are never saved or included in reading backups. Last chapter, scroll position, daily page totals, and chapters reached sync through `/api/reading/sync`. Offline reading activity has a durable per-account queue and uploads on reconnection. Newer positions win during merging, and switching accounts keeps separate reading positions. Notes, bookmarks, appearance settings, and downloaded novels remain local; the website's current API does not sync them.

**Google requires a one-time Android OAuth registration in the same Google Cloud project as the website.** This repository includes the deployed site's public web client ID, but Android's package and signing certificate must also be registered. Exact settings, this APK's SHA fingerprints, distribution-key instructions, and primary documentation are in [GOOGLE_SIGN_IN.md](GOOGLE_SIGN_IN.md). Email sign-in uses the deployed server directly and does not need Android OAuth registration.

## Streaks, goals and reminders

The app includes a Duolingo-style reading habit system that rewards steady reading.

- **XP**: one logical page (800px, the same unit account sync uses) earns 2 XP. Finishing a chapter earns 25 XP, once per chapter. Opening a chapter counts its first page.
- **Daily goal**: Casual 20 XP, Regular 50 XP (default), Serious 100 XP, or Intense 200 XP. Change it in **Settings → Daily goal & reminders**.
- **Streaks**: a day counts once you read at least one page. Missed days are bridged automatically by a **streak freeze** — new readers start with one, earn one more every 10 streak days, and bank at most two. Freezes are never spent on gaps larger than what you have banked.
- **Levels**: XP costs grow linearly per level, from Newcomer to Mystic and beyond.
- **Achievements**: 16 badges for XP, chapters, streaks, and freezes.
- **Progress tab**: a flame streak hero with your freeze count, today's goal ring, level progress bar, a weekly XP chart, a five-week calendar (gold = read, ice = freeze used, empty = missed), and the achievements grid. The Library tab shows your streak and today's goal in a compact strip, and the app bar shows your current streak.
- **Notifications**: a daily reminder at a time you choose (default 8:00 PM), scheduled seven days ahead as inexact alarms (no exact-alarm permission needed) and skipped for today once your goal is met; a **come-back nudge** after two days away (on by default); and celebration alerts when you complete the daily goal, level up, or unlock an achievement. Reminders and nudges are opt-out toggles in **Settings → Daily goal & reminders**, where you can also change the reminder time. On Android 13+ the toggle requests notification permission; if alerts are blocked, that section offers an **Enable** button.
- Habit data is **local to the device**, like bookmarks and reader settings: it is not included in reading backups and does not sync between accounts. Progress that seals chapters offline counts exactly the same as online reading, because it is measured from the same reading position stream.
- Activity is persisted atomically in `habits.json` (corruption-safe: an unreadable file is backed up and reset instead of blocking the app). Reminders use the device's IANA timezone; alarms are rescheduled on every launch and resume.

## Independent repository and rendering

This repository is independent of the website repository. It includes its own Flutter project, Android integration, renderer source, fonts, catalog, JavaScript dependency lockfile, tests, and CI workflow. Building it does not require a sibling website checkout, symlink, submodule, or website deployment.

Flutter provides the library, downloads, storage, and navigation. Its WebView compiles a vendored snapshot of the online Svelte reader layout, chapter page, and settings controls from `reader/source/`, preserving the tested chapter rendering.

- Chapter HTML is extracted verbatim from the source site's rendered `<article class="chapter-content">`.
- The website CSS, DaisyUI themes, prose styles, fonts, images, captions, and littlefoot footnotes are reused.
- The existing reader settings format is persisted in Flutter.
- A loopback server on the device serves the bundled renderer and illustrations. Native HTTP requests fetch online chapters and images from the selected source. The WebView resource policy blocks direct remote requests in both modes. Reading requires no deployed server after download.
- Icons and fonts are included in the APK. Comments, sign-in, and community banners are hidden in the app reader. External references open in the browser.

The launcher uses the original website's `seer.webp` icon, including an adaptive Android icon. Native pages use animated tab and route transitions, staggered card entrances, smooth progress updates, and animated account forms. Entrance and progress animations honor Android's reduced-motion preference. The chapter renderer preserves its website layout.

The vendored reader includes the offline adaptations and explicit Tailwind source paths needed to preserve its layout utilities. See [source provenance](reader/source/PROVENANCE.md).

## Build

Prerequisites: Flutter **3.47.5** / Dart **3.13**, Node.js **22+**, Android SDK platform 36, and Java **17+**. A modern Android System WebView is needed for the website's Tailwind 4 and DaisyUI 5 CSS. Minimum Android SDK: 24.

From this repository's root:

```sh
npm ci
bash tools/build_reader.sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`. Fonts, metadata, credits, and the web reader are generated from this repository's vendored source into the ignored `assets/` directory. Run `build_reader.sh` after changing the reader, metadata, fonts, or CSS.

Regenerate launcher icons after changing the original branding asset: `dart run flutter_launcher_icons`.

For this workspace's tools:

```sh
JAVA_HOME=/home/rodrigo/development/jdk \
PATH=/home/rodrigo/development/jdk/bin:$PATH \
/home/rodrigo/development/flutter/bin/flutter build apk --release --no-pub
```

The default release APK uses the development signing key for installation/testing. To use your distribution key, set `LOTM_KEYSTORE`, `LOTM_STORE_PASSWORD`, `LOTM_KEY_ALIAS`, and `LOTM_KEY_PASSWORD`. Do not commit keys; use the same key for upgrades that preserve app data.

`.github/workflows/android.yml` tests and builds the APK as a workflow artifact. No website deployment, account, or database is required: downloads use the existing public chapter pages.

## Tests

`test/offline_test.dart` tests online reading for every edition without downloaded files, online retries, reading while downloads are paused, online illustration proxying, exact downloaded HTML, pause/resume, reopening with the source stopped, local text search, missing illustrations, corruption repair, atomic state writes, and backup validation. It uses a local HTTP fixture.

`test/background_test.dart` runs the actual Dart download task with mocked Android plugin channels and a local HTTP source: UI disposal, durable completion, completion alerts, notification Pause, and restarting from saved checkpoints. `test/account_test.dart` checks website session exchange, secure session restoration, offline identity, local sign-out, page deduplication, account separation, and newer-position merging. `test/ui_test.dart` checks phone/tablet layouts with enlarged text, reduced motion, and storage accounting; it exports local previews under `build/ui-preview/`. `test/habit_test.dart` checks XP awarding with per-day page floors, chapter-completion bonuses, level math and titles, daily-goal detection with a once-per-day celebration, streak computation, automatic streak freezes (including gaps larger than the bank), milestone freeze awards, achievements, persistence round trips, corruption recovery, reminder scheduling plans for the next seven days, the 48-hour come-back nudge, and a widget smoke test of the Progress screen.

An optional browser comparison checks typography, margins, image dimensions, and rendered height against the actual website at phone and tablet widths. It also checks settings, footnotes, restored position, and zero remote requests:

```sh
python3 tools/fetch_reader_fixture.py
npx playwright install chromium
npm run test:reader
```

Fixtures and screenshots are generated under `build/`. Only the fixture-fetching step needs internet.

Refresh vendored icons with `python3 tools/update_icons.py`. They come from the [Iconify icon sets](https://github.com/iconify/icon-sets), under their upstream licenses: Material Symbols Apache 2.0, Lucide ISC, and the other included sets MIT. Novel, translation, illustration, and font rights remain as stated in the repository's [license and credits](LICENSE.md).
