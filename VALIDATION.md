# Validation

Verified on 2026-09-30 using Flutter 3.47.5, Dart 3.13.4, Android SDK 36, and the installed Java SDK.

Repository isolation: moved to `LOTM-Reader-Android`, initialized its own Git repository, installed JavaScript dependencies from its own lockfile, and rebuilt its renderer from the included source snapshot. No sibling checkout or external source symlink is used. The original website repository's tracked files were restored.

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub`: seven tests pass, covering verbatim downloaded HTML, pause/resume, reopening with the source stopped, local search, source illustrations returning 404, corrupt-file repair, path validation, durable state writes, and backup restore.
- Browser checks at **390 × 844** and **900 × 900**: chapter font, size, line height, weight, alignment, color, article width/height, paragraph height, and illustration dimensions exactly match the selected website's saved chapter. Its normal littlefoot enhancement is applied to both sides of the comparison.
- Browser checks also pass for changing/persisting reader settings, rendering interactive footnotes after chapter navigation, restoring saved position, and **zero remote requests** from the offline renderer.
- `git diff --check`: passes.

Generated browser screenshots: `build/reader-check/offline-390.png` and `build/reader-check/offline-900.png`.

No Android phone or emulator was connected, so installation, device-specific WebView behavior, immersive mode, and Android's document picker were not exercised on a device. The Android release build compiles the native integration and passes its release lint checks.

The independent renderer snapshot excludes the website-only build-time chapter template and enhanced-image routes. App builds and tests do not invoke the website build or require its repository.
