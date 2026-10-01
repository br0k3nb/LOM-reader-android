<script lang="ts">
  import { onMount } from "svelte";
  import Icon from "@iconify/svelte";
  import {
    authState,
    register,
    signIn,
    signInWithGoogle,
    signOut,
    startAuth,
  } from "$lib/auth.svelte";
  import {
    readingSyncState,
    startReadingSync,
  } from "$lib/reading-sync";

  type GoogleCredentialResponse = { credential?: string };
  type GoogleIdentityApi = {
    accounts: {
      id: {
        initialize: (options: {
          client_id: string;
          callback: (response: GoogleCredentialResponse) => void;
          ux_mode: "popup";
        }) => void;
        renderButton: (
          element: HTMLElement,
          options: Record<string, string | number>,
        ) => void;
      };
    };
  };
  type GoogleWindow = Window & { google?: GoogleIdentityApi };

  const googleClientId = (
    import.meta.env.VITE_GOOGLE_CLIENT_ID as string | undefined
  )?.trim();

  let accountDialog: HTMLDialogElement;
  let googleButton: HTMLDivElement;
  let mode: "signin" | "register" = "signin";
  let email = "";
  let password = "";
  let passwordConfirmation = "";
  let localError = "";
  let googleLoadError = false;

  $: user = $authState.user;
  $: busy = $authState.busy;
  $: todayPages = $readingSyncState.todayPages;
  $: recentDays = Object.entries($readingSyncState.daily)
    .sort(([a], [b]) => b.localeCompare(a))
    .slice(0, 7);
  $: pendingPages = $readingSyncState.todayPending;
  $: syncError = $readingSyncState.error;
  export let scope: { book: string; tl: string } | null = null;
  $: chapterKey = scope ? `${scope.book}\u0000${scope.tl}` : null;
  $: chaptersRead = chapterKey
    ? Number($readingSyncState.chapters[chapterKey] || 0)
    : Object.values($readingSyncState.chapters).reduce(
        (total, count) => total + Number(count || 0),
        0,
      );

  function initializeGoogle() {
    const google = (window as GoogleWindow).google;
    if (!google || !googleClientId || !googleButton) return;

    google.accounts.id.initialize({
      client_id: googleClientId,
      ux_mode: "popup",
      callback: (response) => void handleGoogleCredential(response),
    });
    google.accounts.id.renderButton(googleButton, {
      theme: "outline",
      size: "large",
      shape: "rectangular",
      text: "continue_with",
      width: Math.min(360, Math.max(240, googleButton.clientWidth || 320)),
    });
  }

  async function handleGoogleCredential(response: GoogleCredentialResponse) {
    if (!response.credential) return;
    localError = "";
    const result = await signInWithGoogle(response.credential);
    if (!result) return;
    await startReadingSync();
    closeAccount();
  }

  onMount(() => {
    startAuth();
    void startReadingSync();

    if (!googleClientId) return;
    const existing = document.getElementById("google-identity-services") as HTMLScriptElement | null;
    const googleWindow = window as GoogleWindow;
    if (googleWindow.google) {
      initializeGoogle();
      return;
    }

    const script = existing || document.createElement("script");
    const onLoad = () => initializeGoogle();
    const onError = () => (googleLoadError = true);
    script.addEventListener("load", onLoad);
    script.addEventListener("error", onError);
    if (!existing) {
      script.id = "google-identity-services";
      script.src = "https://accounts.google.com/gsi/client";
      script.async = true;
      script.defer = true;
      document.head.appendChild(script);
    }

    return () => {
      script.removeEventListener("load", onLoad);
      script.removeEventListener("error", onError);
    };
  });

  function openAccount() {
    localError = "";
    accountDialog?.showModal();
  }

  function closeAccount() {
    accountDialog?.close();
  }

  function switchMode(next: "signin" | "register") {
    mode = next;
    localError = "";
  }

  async function submit(event: SubmitEvent) {
    event.preventDefault();
    localError = "";

    if (mode === "register" && password !== passwordConfirmation) {
      localError = "The passwords do not match.";
      return;
    }

    const result =
      mode === "signin"
        ? await signIn(email, password)
        : await register(email, password);
    if (!result) return;

    await startReadingSync();
    closeAccount();
    password = "";
    passwordConfirmation = "";
  }

  async function logout() {
    await signOut();
    localError = "";
  }
</script>

<div class="tooltip tooltip-bottom" data-tip={user ? "Account" : "Sign in to sync"}>
  <button
    type="button"
    onclick={openAccount}
    class="btn btn-ghost btn-sm btn-square rounded-btn"
    aria-label={user ? "Open account" : "Sign in to sync reading"}
  >
    {#if user}
      <span class="flex size-6 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-content">
        {user.email.slice(0, 1).toUpperCase()}
      </span>
    {:else}
      <Icon icon="material-symbols:account-circle-outline-rounded" class="size-6" />
    {/if}
  </button>
</div>

<dialog bind:this={accountDialog} class="modal modal-bottom sm:modal-middle">
  <div class="modal-box bg-base-100 rounded-box max-w-md">
    <form method="dialog">
      <button class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2" aria-label="Close">✕</button>
    </form>

    {#if user}
      <div class="space-y-5">
        <div>
          <p class="text-xs font-bold uppercase tracking-widest opacity-50">Signed in</p>
          <h2 class="mt-1 break-all text-xl font-bold">{user.email}</h2>
        </div>

        <div class="stats stats-vertical w-full bg-base-200 shadow-sm sm:stats-horizontal">
          <div class="stat px-5 py-4">
            <div class="stat-title">Pages today</div>
            <div class="stat-value text-3xl text-primary">{todayPages}</div>
            <div class="stat-desc">
              {#if pendingPages > 0}
                {pendingPages} waiting to sync
              {:else if $readingSyncState.syncing}
                Syncing…
              {:else}
                Synced across your devices
              {/if}
            </div>
          </div>
          <div class="stat px-5 py-4">
            <div class="stat-title">Chapters read</div>
            <div class="stat-value text-3xl text-secondary">{chaptersRead}</div>
            <div class="stat-desc">
              {#if scope}
                Unique chapters in this book and translation
              {:else}
                Unique chapters across all books and translations
              {/if}
            </div>
          </div>
        </div>

        {#if recentDays.length > 0}
          <div class="rounded-box bg-base-200/70 p-3">
            <div class="mb-2 flex items-center justify-between">
              <span class="text-xs font-bold uppercase tracking-wider opacity-60">Recent days</span>
              <span class="text-[11px] opacity-50">Logical pages</span>
            </div>
            <div class="space-y-1">
              {#each recentDays as [date, pages]}
                <div class="flex items-center justify-between text-sm">
                  <span class="opacity-70">{date}</span>
                  <span class="font-mono font-semibold">{pages}</span>
                </div>
              {/each}
            </div>
          </div>
        {/if}

        {#if syncError}
          <div class="alert alert-warning text-sm">{syncError}. Your local progress is safe and will retry later.</div>
        {/if}

        <button type="button" class="btn btn-outline btn-error w-full" onclick={logout} disabled={busy}>
          {#if busy}<span class="loading loading-spinner loading-sm"></span>{/if}
          Sign out
        </button>
      </div>
    {:else}
      <div class="space-y-5">
        <div>
          <p class="text-xs font-bold uppercase tracking-widest text-primary">Reader account</p>
          <h2 class="mt-1 text-2xl font-bold">
            {mode === "signin" ? "Sign in to sync" : "Create an account"}
          </h2>
          <p class="mt-2 text-sm opacity-70">
            Keep your last chapter, chapters read, and daily page count available on every device.
          </p>
        </div>

        <div role="tablist" class="tabs tabs-boxed grid grid-cols-2">
          <button
            type="button"
            role="tab"
            aria-selected={mode === "signin"}
            class={`tab ${mode === "signin" ? "tab-active" : ""}`}
            onclick={() => switchMode("signin")}
          >Sign in</button>
          <button
            type="button"
            role="tab"
            aria-selected={mode === "register"}
            class={`tab ${mode === "register" ? "tab-active" : ""}`}
            onclick={() => switchMode("register")}
          >Create account</button>
        </div>

        <form class="space-y-3" onsubmit={submit}>
          {#if googleClientId}
            <div class="divider my-0 text-xs opacity-60">or continue with</div>
            <div
              bind:this={googleButton}
              class="flex min-h-[44px] w-full justify-center overflow-hidden rounded-btn"
              aria-label="Google sign-in"
            ></div>
            {#if googleLoadError}
              <p class="text-center text-xs text-error">Google sign-in could not load. Try email sign-in.</p>
            {/if}
          {/if}

          <label class="form-control w-full">
            <span class="label-text mb-1 block text-sm font-medium">Email</span>
            <input
              bind:value={email}
              type="email"
              autocomplete="email"
              required
              class="input input-bordered w-full"
              placeholder="you@example.com"
            />
          </label>
          <label class="form-control w-full">
            <span class="label-text mb-1 block text-sm font-medium">Password</span>
            <input
              bind:value={password}
              type="password"
              autocomplete={mode === "signin" ? "current-password" : "new-password"}
              minlength="8"
              maxlength="256"
              required
              class="input input-bordered w-full"
              placeholder="At least 8 characters"
            />
          </label>
          {#if mode === "register"}
            <label class="form-control w-full">
              <span class="label-text mb-1 block text-sm font-medium">Confirm password</span>
              <input
                bind:value={passwordConfirmation}
                type="password"
                autocomplete="new-password"
                minlength="8"
                maxlength="256"
                required
                class="input input-bordered w-full"
                placeholder="Repeat your password"
              />
            </label>
          {/if}

          {#if localError || $authState.error}
            <div class="alert alert-error py-2 text-sm" role="alert">
              {localError || $authState.error}
            </div>
          {/if}

          <button type="submit" class="btn btn-primary w-full" disabled={busy}>
            {#if busy}<span class="loading loading-spinner loading-sm"></span>{/if}
            {mode === "signin" ? "Sign in" : "Create account"}
          </button>
        </form>

        <p class="text-center text-xs opacity-60">
          Reading still works without an account. Signing in uploads the current device's pending progress.
        </p>
      </div>
    {/if}
  </div>
  <form method="dialog" class="modal-backdrop"><button>close</button></form>
</dialog>
