import assert from 'node:assert/strict';
import http from 'node:http';
import { readFile, readdir, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const mobile = fileURLToPath(new URL('../', import.meta.url));
const fixture = path.join(mobile, 'build/reader-fixture');
const chapters = JSON.parse(await readFile(path.join(fixture, 'chapters.json'), 'utf8'));
const footnoteModule = (await readdir(path.join(mobile, 'assets/reader/assets'))).find(name => name.startsWith('littlefoot-') && name.endsWith('.js'));
const types = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.webp': 'image/webp', '.woff2': 'font/woff2', '.woff': 'font/woff' };
const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    const relative = url.pathname === '/' ? 'index.html' : url.pathname.slice(1);
    if (relative.includes('..')) { res.writeHead(400).end(); return; }
    const root = relative === 'baseline.html' || relative.startsWith('_app/') || relative.startsWith('assets/images/') ? fixture
      : relative.startsWith('fonts/') ? path.join(mobile, 'assets') : path.join(mobile, 'assets/reader');
    const content = await readFile(path.join(root, relative));
    res.setHeader('Content-Type', types[path.extname(relative)] || 'application/octet-stream');
    res.setHeader('Content-Security-Policy', "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-src 'none'");
    res.end(content);
  } catch { res.writeHead(404).end(); }
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ headless: true });
try {
  for (const viewport of [{ width: 390, height: 844 }, { width: 900, height: 900 }]) {
    const context = await browser.newContext({ viewport });
    const remote = [];
    await context.route('**/*', route => {
      if (route.request().url().startsWith(origin)) return route.continue();
      remote.push(route.request().url()); return route.abort();
    });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => {
      window.readerMessages = [];
      window.NativeReader = { postMessage: message => window.readerMessages.push(JSON.parse(message)) };
    });
    await page.goto(origin);
    await page.waitForFunction(() => typeof window.openChapter === 'function');
    await page.evaluate(data => window.openChapter(data), { book: 'lotm', tl: 'webnovel', slug: 1, title: 'Crimson', idx: 1, category: 'Volume 1', html: chapters['1'] });
    await page.waitForFunction(() => window.readerMessages.some(m => m.type === 'opened'));
    assert.deepEqual(errors, [], 'Reader must initialize without runtime errors');
    const metrics = async p => p.locator('.chapter-content').evaluate(element => {
      const style = getComputedStyle(element);
      const rect = element.getBoundingClientRect();
      const first = element.querySelector('p');
      const image = element.querySelector('img');
      return { font: style.fontFamily, size: style.fontSize, lineHeight: style.lineHeight, weight: style.fontWeight,
        align: style.textAlign, color: style.color, width: rect.width, height: rect.height,
        pHeight: first.getBoundingClientRect().height, imageWidth: image.getBoundingClientRect().width, imageHeight: image.getBoundingClientRect().height };
    });
    const online = await context.newPage();
    await online.goto(`${origin}/baseline.html`);
    // Apply the online reader's own footnote enhancement to its saved SSR page.
    await online.evaluate(async url => {
      const { littlefoot } = await import(url);
      littlefoot({ activateOnHover: true, hoverDelay: 50, dismissOnUnhover: true,
        buttonTemplate: '<button aria-label="Footnote <% number %>" class="relative btn btn-xs btn-info px-3 py-2 h-3 text-sm mx-1 font-mono"><% number %></button>' });
    }, `${origin}/assets/${footnoteModule}`);
    await online.evaluate(async () => { await document.fonts.ready; await Promise.all([...document.images].map(image => image.complete ? null : new Promise(resolve => { image.onload = image.onerror = resolve; }))); });
    const offlineMetrics = await metrics(page);
    const onlineMetrics = await metrics(online);
    if (JSON.stringify(offlineMetrics) !== JSON.stringify(onlineMetrics)) {
      const children = async p => p.locator('.chapter-content').evaluate(element => [...element.children].map(child => {
        const s = getComputedStyle(child); return { tag: child.tagName, text: child.textContent.slice(0, 40), height: child.getBoundingClientRect().height,
          font: s.fontFamily, weight: s.fontWeight, size: s.fontSize, lh: s.lineHeight, mt: s.marginTop, mb: s.marginBottom, letter: s.letterSpacing };
      }));
      const a = await children(page), b = await children(online);
      console.log('Rendering differences:', a.map((x, i) => JSON.stringify(x) === JSON.stringify(b[i]) ? null : { offline: x, online: b[i] }).filter(Boolean).slice(0, 12));
    }
    assert.deepEqual(offlineMetrics, onlineMetrics, `Chapter rendering differs at ${viewport.width}px`);
    assert.deepEqual(remote, [], 'Offline reader must make zero remote requests');
    await mkdir(path.join(mobile, 'build/reader-check'), { recursive: true });
    await page.screenshot({ path: path.join(mobile, `build/reader-check/offline-${viewport.width}.png`) });
    await page.locator('[data-tip="Settings (S)"] button').click();
    await page.locator('dialog[open] select').first().selectOption('light');
    await page.waitForFunction(() => document.documentElement.dataset.theme === 'light');
    assert.ok(await page.evaluate(() => window.readerMessages.some(m => m.type === 'settings' && m.settings.theme === 'light')));
    await page.locator('dialog[open] button').first().click();
    await page.evaluate(data => window.openChapter(data), { book: 'lotm', tl: 'webnovel', slug: 67, title: 'A Friend', idx: 67, category: 'Volume 1', html: chapters['67'], settings: { theme: 'sunset' }, scrollRatio: .4 });
    await page.waitForFunction(() => document.querySelectorAll('[data-footnote-button]').length > 0);
    assert.ok(await page.evaluate(() => scrollY > 0), 'Saved scroll position must restore');
    await page.locator('[data-footnote-button]').first().click();
    await page.waitForFunction(() => document.querySelector('.littlefoot__popover') !== null);
    assert.deepEqual(remote, []);
    console.log(`PASS ${viewport.width}px: exact chapter metrics, no remote requests, reader settings, footnotes, and position restore`);
    await context.close();
  }
} finally { await browser.close(); await new Promise(resolve => server.close(resolve)); }
