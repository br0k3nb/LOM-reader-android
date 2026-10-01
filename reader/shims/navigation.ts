import { onMount } from 'svelte';
export const hooks = new Set<(event: any) => void>();
export function goto(path: string) {
  (window as any).NativeReader?.postMessage(JSON.stringify({ type: 'navigate', path }));
}
export function afterNavigate(callback: (event: any) => void) {
  onMount(() => { hooks.add(callback); return () => hooks.delete(callback); });
}
