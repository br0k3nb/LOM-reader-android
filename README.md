# LOTM Reader for Android

A standalone Flutter app with downloadable offline editions of **Lord of the Mysteries** and **Circle of Inevitability**. The source is `https://lotmreader.vercel.app`.

## Reading and downloads

1. Install the APK and open **Library**.
2. Download the English Webnovel, English original translation, or Brazilian Portuguese edition you want. Each download includes the entire edition and every illustration available on the source website. **Download all editions** queues the five editions.
3. Wait for **Available offline**, then read. Partially downloaded editions cannot be opened.

Keep the app open during downloads. Pause and resume are supported. If Android closes the process or the connection fails, successful chapters and illustrations remain saved; **Resume** continues from those checkpoints. Four chapter requests run concurrently. Illustrations follow the chapters. Illustrated editions can be large.

Downloads live in Android's persistent app data, outside WebView caches. Closing the app, restarting the phone, and disabling internet do not remove them. Uninstalling the app or clearing its storage removes downloads and reading data. **Remove download** retains your progress and bookmarks. **Verify files** checks SHA-256 hashes and enables repair when a damaged file is found.

Illustrations returning HTTP 404 on the source website are reported as unavailable. Their original HTML remains intact; the offline renderer preserves the unavailable image instead of replacing it. Other download failures prevent completion and can be retried.

The app includes chapter and volume browsing, title/number search, search inside downloaded text, saved position, bookmarks with notes, and JSON export/import through Android's file picker. Reading backups include appearance settings, but do not contain downloaded novels.

## Independent repository and rendering

This repository is independent of the website repository. It includes its own Flutter project, Android integration, renderer source, fonts, catalog, JavaScript dependency lockfile, tests, and CI workflow. Building it does not require a sibling website checkout, symlink, submodule, or website deployment.

Flutter provides the library, downloads, storage, and navigation. Its WebView compiles a vendored snapshot of the online Svelte reader layout, chapter page, and settings controls from `reader/source/`, preserving the tested chapter rendering.

- Chapter HTML is extracted verbatim from the source site's rendered `<article class="chapter-content">`.
- The website CSS, DaisyUI themes, prose styles, fonts, images, captions, and littlefoot footnotes are reused.
- The existing reader settings format is persisted in Flutter.
- A loopback server on the device serves the saved files. The WebView resource policy blocks remote requests. Reading requires no deployed server after download.
- Icons and fonts are included in the APK. Comments, sign-in, and community banners are hidden in offline mode. External references open in the browser.

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

For this workspace's tools:

```sh
JAVA_HOME=/home/rodrigo/development/jdk \
PATH=/home/rodrigo/development/jdk/bin:$PATH \
/home/rodrigo/development/flutter/bin/flutter build apk --release --no-pub
```

The default release APK uses the development signing key for installation/testing. To use your distribution key, set `LOTM_KEYSTORE`, `LOTM_STORE_PASSWORD`, `LOTM_KEY_ALIAS`, and `LOTM_KEY_PASSWORD`. Do not commit keys; use the same key for upgrades that preserve app data.

`.github/workflows/android.yml` tests and builds the APK as a workflow artifact. No website deployment, account, or database is required: downloads use the existing public chapter pages.

## Tests

`test/offline_test.dart` tests exact downloaded HTML, pause/resume, reopening with the source stopped, local text search, missing illustrations, corruption repair, atomic state writes, and backup validation. It uses a local HTTP fixture.

An optional browser comparison checks typography, margins, image dimensions, and rendered height against the actual website at phone and tablet widths. It also checks settings, footnotes, restored position, and zero remote requests:

```sh
python3 tools/fetch_reader_fixture.py
npx playwright install chromium
npm run test:reader
```

Fixtures and screenshots are generated under `build/`. Only the fixture-fetching step needs internet.

Refresh vendored icons with `python3 tools/update_icons.py`. They come from the [Iconify icon sets](https://github.com/iconify/icon-sets), under their upstream licenses: Material Symbols Apache 2.0, Lucide ISC, and the other included sets MIT. Novel, translation, illustration, and font rights remain as stated in the repository's [license and credits](LICENSE.md).
