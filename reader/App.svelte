<script lang="ts">
  import { onMount, tick } from 'svelte';
  // Use the vendored online reader layout and chapter page to preserve rendering.
  import ReaderLayout from './source/lib/reader/ReaderLayout.svelte';
  import ChapterPage from './source/routes/(reader)/read/[book]/[tl]/[slug]/+page.svelte';
  import { page } from './shims/state.svelte';
  import { hooks } from './shims/navigation';
  import { flushReadingSync, setRestoring } from './shims/reading';
  let chapter = $state<any>(null);
  let renderKey = $state(0);
  let navigationGeneration = 0;

  onMount(() => {
    const fullscreen = () => (window as any).NativeReader?.postMessage(JSON.stringify({ type: 'fullscreen' }));
    window.addEventListener('reader-fullscreen', fullscreen);
    (window as any).openChapter = async (data: any) => {
      const generation = ++navigationGeneration;
      flushReadingSync();
      setRestoring(true);
      const previous = page.url;
      // Remount restores the same littlefoot setup and reader lifecycle as a full online load.
      chapter = null;
      await tick();
      if (generation !== navigationGeneration) return;
      if (data.settings) localStorage.setItem('readerSettings', JSON.stringify(data.settings));
      page.url = new URL(`/read/${data.book}/${data.tl}/${data.slug}`, location.origin);
      chapter = data;
      renderKey++;
      await tick();
      if (generation !== navigationGeneration) return;
      await document.fonts.ready;
      for (const hook of hooks) await hook({ from: { url: previous }, to: { url: page.url } });
      // The shared reader schedules its chapter reset in requestAnimationFrame.
      // Let that reset finish before applying the durable offline position.
      await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
      await Promise.all([...document.images].map(img => img.complete ? Promise.resolve() : new Promise(resolve => {
        img.onload = img.onerror = resolve;
      })));
      if (generation !== navigationGeneration) return;
      window.scrollTo(0, (data.scrollRatio || 0) * Math.max(0, document.documentElement.scrollHeight - innerHeight));
      setRestoring(false);
      window.dispatchEvent(new Event('scroll'));
      (window as any).NativeReader?.postMessage(JSON.stringify({ type: 'opened' }));
    };
    // Persist the same settings format used on the website in Flutter's durable state.
    const setItem = Storage.prototype.setItem;
    Storage.prototype.setItem = function(key, value) {
      setItem.call(this, key, value);
      if (key === 'readerSettings') (window as any).NativeReader?.postMessage(JSON.stringify({ type: 'settings', settings: JSON.parse(value) }));
    };
    document.addEventListener('click', event => {
      const anchor = (event.target as HTMLElement).closest('a');
      const href = anchor?.getAttribute('href');
      if (!href || href.startsWith('#')) return;
      event.preventDefault();
      (window as any).NativeReader?.postMessage(JSON.stringify({ type: 'navigate', path: href }));
    });
    (window as any).NativeReader?.postMessage(JSON.stringify({ type: 'ready' }));
    return () => { Storage.prototype.setItem = setItem; window.removeEventListener('reader-fullscreen', fullscreen); };
  });
</script>

{#if chapter}
  {#key renderKey}
    <ReaderLayout offline={true}>
      <ChapterPage data={{ chapter }} />
    </ReaderLayout>
  {/key}
{/if}
