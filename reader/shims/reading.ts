import { writable } from 'svelte/store';
export const readingSyncState = writable({ daily: {}, chapters: {}, todayPages: 0, todayPending: 0, error: null });
let latest: any = null;
let restoring = false;
let timer: ReturnType<typeof setTimeout>;
export function setRestoring(value: boolean) { restoring = value; }
export function recordReadingProgress(input: any) {
  if (restoring) return latest;
  const max = Math.max(0, input.documentHeight - input.viewportHeight);
  latest = { ...input, scrollRatio: max ? Math.min(1, input.scroll / max) : 0, updatedAt: Date.now() };
  clearTimeout(timer);
  timer = setTimeout(flushReadingSync, 250);
  return latest;
}
export function flushReadingSync() {
  if (latest) (window as any).NativeReader?.postMessage(JSON.stringify({ type: 'progress', ...latest }));
}
export async function startReadingSync() {}
export function getCurrentLocalProgress() { return null; }
export async function getBestProgress() { return null; }
