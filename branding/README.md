# Branding assets

- `seer.webp`: unchanged original LOTM Reader favicon from `website/static/assets/seer.webp`. Copied into this independent repository for the Android launcher and native interface; original credits apply.
- `google_g.png`: official Google G asset from `https://developers.google.com/identity/images/g-logo.png`, used in the Google sign-in button. Google branding rights remain with Google.
- `Roboto.ttf` and `Roboto-Italic.ttf`: the original reader's Roboto fonts decoded from WOFF2 to TrueType for Flutter's native font loader. The website's misleading `.ttf` filenames contain WOFF2 data; `fontTools.ttLib.TTFont` with `flavor=None` was used to package these copies. Glyphs and original font licensing are retained. The web reader still uses its unchanged WOFF2 assets.

`tools/build_reader.sh` copies these assets into the generated Flutter bundle. `dart run flutter_launcher_icons` packages the Seer asset at Android launcher resolutions and produces its adaptive icon.
