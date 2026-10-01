import { browser } from "$app/environment";
import { writable } from "svelte/store";
import type { AuthUser } from "$lib/auth-types";

export type AuthState = {
  user: AuthUser | null;
  ready: boolean;
  busy: boolean;
  error: string | null;
};

export const authState = writable<AuthState>({
  user: null,
  ready: false,
  busy: false,
  error: null,
});

let refreshPromise: Promise<void> | null = null;
let started = false;

function messageFromResponse(data: unknown, fallback: string): string {
  if (data && typeof data === "object" && "error" in data && typeof data.error === "string") {
    return data.error;
  }
  return fallback;
}

async function readJson(response: Response): Promise<unknown> {
  try {
    return await response.json();
  } catch {
    return null;
  }
}

export async function refreshAuth(): Promise<void> {
  if (!browser) return;
  if (refreshPromise) return refreshPromise;

  refreshPromise = (async () => {
    try {
      const response = await fetch("/api/auth/session", {
        credentials: "same-origin",
        cache: "no-store",
        headers: { accept: "application/json" },
      });
      const data = await readJson(response);
      const user =
        response.ok && data && typeof data === "object" && "user" in data
          ? ((data as { user: AuthUser | null }).user ?? null)
          : null;
      authState.update((state) => ({
        ...state,
        user,
        ready: true,
        error: response.ok ? null : "Unable to reach the sign-in service.",
      }));
    } catch {
      // The reader remains usable offline. A later focus/online event retries.
      authState.update((state) => ({ ...state, ready: true, error: "Unable to reach the sign-in service." }));
    } finally {
      refreshPromise = null;
    }
  })();

  return refreshPromise;
}

export async function signIn(email: string, password: string): Promise<AuthUser | null> {
  authState.update((state) => ({ ...state, busy: true, error: null }));
  try {
    const response = await fetch("/api/auth/login", {
      method: "POST",
      credentials: "same-origin",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ email, password }),
    });
    const data = await readJson(response);
    if (!response.ok) {
      authState.update((state) => ({
        ...state,
        busy: false,
        error: messageFromResponse(data, "Unable to sign in."),
      }));
      return null;
    }
    const user = (data as { user: AuthUser }).user;
    authState.set({ user, ready: true, busy: false, error: null });
    return user;
  } catch {
    authState.update((state) => ({
      ...state,
      busy: false,
      error: "Unable to reach the sign-in service.",
    }));
    return null;
  }
}

export async function signInWithGoogle(credential: string): Promise<AuthUser | null> {
  authState.update((state) => ({ ...state, busy: true, error: null }));
  try {
    const response = await fetch("/api/auth/google", {
      method: "POST",
      credentials: "same-origin",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ credential }),
    });
    const data = await readJson(response);
    if (!response.ok) {
      authState.update((state) => ({
        ...state,
        busy: false,
        error: messageFromResponse(data, "Unable to sign in with Google."),
      }));
      return null;
    }
    const user = (data as { user: AuthUser }).user;
    authState.set({ user, ready: true, busy: false, error: null });
    return user;
  } catch {
    authState.update((state) => ({
      ...state,
      busy: false,
      error: "Unable to reach the Google sign-in service.",
    }));
    return null;
  }
}

export async function register(email: string, password: string): Promise<AuthUser | null> {
  authState.update((state) => ({ ...state, busy: true, error: null }));
  try {
    const response = await fetch("/api/auth/register", {
      method: "POST",
      credentials: "same-origin",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ email, password }),
    });
    const data = await readJson(response);
    if (!response.ok) {
      authState.update((state) => ({
        ...state,
        busy: false,
        error: messageFromResponse(data, "Unable to create the account."),
      }));
      return null;
    }
    const user = (data as { user: AuthUser }).user;
    authState.set({ user, ready: true, busy: false, error: null });
    return user;
  } catch {
    authState.update((state) => ({
      ...state,
      busy: false,
      error: "Unable to reach the account service.",
    }));
    return null;
  }
}

export async function signOut(): Promise<void> {
  authState.update((state) => ({ ...state, busy: true, error: null }));
  try {
    await fetch("/api/auth/logout", {
      method: "POST",
      credentials: "same-origin",
      headers: { accept: "application/json" },
    });
  } catch {
    // Clear the client state even when the network request fails. The cookie
    // remains HttpOnly and will be discarded by the browser/server when it can.
  } finally {
    authState.set({ user: null, ready: true, busy: false, error: null });
  }
}

export function startAuth(): void {
  if (!browser || started) return;
  started = true;
  void refreshAuth();
  window.addEventListener("focus", () => void refreshAuth());
  window.addEventListener("online", () => void refreshAuth());
}
