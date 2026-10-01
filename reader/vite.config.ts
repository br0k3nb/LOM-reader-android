import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';
import tailwindcss from '@tailwindcss/vite';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';
import { fileURLToPath } from 'node:url';
const here = (path: string) => fileURLToPath(new URL(path, import.meta.url));
export default defineConfig({
  root: here('./'),
  plugins: [tailwindcss(), svelte({ configFile: false, preprocess: vitePreprocess() })],
  resolve: { alias: [
    { find: '@iconify/svelte', replacement: here('./OfflineIcon.svelte') },
    { find: '$app/environment', replacement: here('./shims/environment.ts') },
    { find: '$app/state', replacement: here('./shims/state.svelte.ts') },
    { find: '$app/navigation', replacement: here('./shims/navigation.ts') },
    { find: '$lib/reading-sync', replacement: here('./shims/reading.ts') },
    { find: '$lib', replacement: here('./source/lib') },
  ] },
  build: { outDir: here('../assets/reader'), emptyOutDir: true, assetsInlineLimit: 0 },
});
