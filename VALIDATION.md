# Validation

Verified on 2026-10-01 using Flutter 3.47.5, Dart 3.13.4, Android SDK 36, and the installed Java SDK.

Repository isolation: moved to `LOTM-Reader-Android`, initialized its own Git repository, installed JavaScript dependencies from its own lockfile, and rebuilt its renderer from the included source snapshot. No sibling checkout or external source symlink is used. The original website repository's tracked files were restored.

- `flutter analyze --no-pub`: no issues.
- Local Flutter suite: 23 tests pass (the 12 unchanged offline/background tests plus 11 account/UI tests). Coverage includes online reading across all five editions without downloads, exact offline HTML, illustration proxying, pause/resume, source-disconnected reading, corruption repair, state/backup persistence, background task completion after UI disposal, completion notifications, notification Pause and worker restart, secure account-session restoration, offline page queues, account separation, newer-position merging, storage accounting, reduced motion, and native layouts. Google regression tests cover token exchange through AuthStore, token exclusion from secure persistence, immediate tap feedback, visible cancellation, and a successful retry.
- Browser checks at **390 × 844** and **900 × 900**: chapter font, size, line height, weight, alignment, color, article width/height, paragraph height, and illustration dimensions exactly match the selected website's saved chapter. Its normal littlefoot enhancement is applied to both sides of the comparison.
- Browser checks also pass for changing/persisting reader settings, rendering interactive footnotes after chapter navigation, restoring saved position, and **zero remote requests** from the offline renderer.
- `git diff --check`: passes.

Generated browser screenshots: `build/reader-check/offline-390.png` and `build/reader-check/offline-900.png`.

The earlier online-reading build was installed on the connected SM-S731B and opened LOTM chapters 1 and 2, including the cover and Portuguese translation switching. **Version 1.1.0 was not installed or tested on the phone, as requested.** Its Android release build compiles the foreground service, notification integration, Google sign-in, secure storage, native storage reporting, and adaptive launcher icon.

Background-service and notification tests execute the actual Dart task against a local HTTP fixture with mocked Android plugin channels; they do not verify a physical device’s battery manager or notification UI. Account tests use local API fixtures and injected identity-token outcomes, without creating accounts or signing into a real Google identity. The user confirmed the Android OAuth client has not been registered. Google's external registration remains a deployment prerequisite documented in `GOOGLE_SIGN_IN.md`; real Google sign-in has not been verified.

Native previews are generated locally at 360 and 600 pixels wide, with enlarged text, under `build/ui-preview/`. The library startup, chapter browser, and tab navigation also pass a local widget integration test. The original Seer asset is reused unchanged; native Roboto copies are valid TrueType conversions of the website’s WOFF2 data. Chapter renderer fonts and styles remain unchanged.

The independent renderer snapshot excludes the website-only build-time chapter template and enhanced-image routes. App builds and tests do not invoke the website build or require its repository.
