# Reader source provenance

This directory contains a self-contained snapshot of the LOTM-Reader chapter renderer, styles, fonts, and catalog.

- Upstream source: https://github.com/br0k3nb/LOTM-Reader
- Upstream checkout revision: `982d342bcf26791ee9ef899d141abe8cd80e0aae`
- Public chapter source: https://lotmreader.vercel.app
- Snapshot captured: 2026-09-30

The snapshot includes the app's offline flag, local navigation and progress adapters, accessibility labels, footnote cleanup, and explicit Tailwind source paths. The route layout was moved into `lib/reader/ReaderLayout.svelte` so the Flutter renderer can compile it independently. These app adaptations are owned by this repository; the website checkout is not required or modified by its build.

Chapters and illustrations are downloaded by the installed app. They are not part of this source snapshot. The catalog and fonts are included so the initial app and downloaded chapters render locally.

Original code, content, artwork, and font rights are described in [the preserved license and credits](../../LICENSE.md).
