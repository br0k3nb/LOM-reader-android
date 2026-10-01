<script lang="ts">
  import Icon from "@iconify/svelte";
  import { page } from "$app/state";
  import { readerState } from "$lib/reader.svelte";
  import AccountMenu from "$lib/reader/AccountMenu.svelte";

  let { prefs, bookSlug, bookData, navState = $bindable(), offline = false } = $props();

  // State
  let modals = $state({
    chapter: null as HTMLDialogElement | null,
    settings: null as HTMLDialogElement | null,
    edit: null as HTMLDialogElement | null,
  });

  // --- Constants: Themes ---
  const PRIORITY_THEMES = [
    "sunset",
    "light",
    "retro",
    "night",
    "business",
    "cupcake",
    "black",
  ];
  const ALL_THEMES = [
    "sunset",
    "light",
    "dark",
    "cupcake",
    "bumblebee",
    "emerald",
    "corporate",
    "synthwave",
    "retro",
    "cyberpunk",
    "valentine",
    "halloween",
    "garden",
    "forest",
    "aqua",
    "lofi",
    "pastel",
    "fantasy",
    "wireframe",
    "black",
    "luxury",
    "dracula",
    "cmyk",
    "autumn",
    "business",
    "acid",
    "lemonade",
    "night",
    "coffee",
    "winter",
    "dim",
    "nord",
  ];
  const MISC_THEMES = ALL_THEMES.filter((t) => !PRIORITY_THEMES.includes(t));

  // --- Constants: Fonts ---
  const BOOK_FONTS = [
    "Alegreya",
    "Bookerly",
    "Roboto",
    "monospace",
    "Merriweather",
  ];

  const SYSTEM_FONTS = [
    "EB Garamond",
    "Crimson Pro",
    "Georgia",
    "Verdana",
    "Arial",
    "sans-serif",
    "Times New Roman",
    "serif",
    "Helvetica",
    "Tahoma",
    "system-ui",
    "Trebuchet MS",
    "Courier New",
  ];

  // Helpers: friendly TL labels (multi-language support)
  const tlLabels: Record<string, string> = {
    webnovel: "EN — Webnovel",
    oldtl: "EN — Old TL",
    "pt-br": "PT-BR",
    pt_br: "PT-BR",
    pt: "PT-BR",
  };
  function tlLabel(tl: string) {
    return tlLabels[tl] ?? tl.toUpperCase();
  }

  // --- Language switcher (multi-language support: EN <-> PT-BR) ---
  const PT_TLS = ["pt-br", "pt_br", "pt"];
  // Derive from URL (works in SSR; navState only syncs after hydration)
  const urlTl = $derived(
    page.url.pathname.split("/").filter(Boolean)[2] ?? navState.selectedTL
  );
  const isPt = $derived(PT_TLS.includes(urlTl));
  const hasPtBr = $derived(
    Object.keys(bookData[bookSlug] || {}).some((tl) => PT_TLS.includes(tl))
  );
  const enTl = $derived(
    Object.keys(bookData[bookSlug] || {}).find((tl) => !PT_TLS.includes(tl)) || "webnovel"
  );
  const ptTl = $derived(
    Object.keys(bookData[bookSlug] || {}).find((tl) => PT_TLS.includes(tl)) || "pt-br"
  );
  // Same chapter in the other language; fall back to ch.1 if not translated yet
  // (slug from URL: authoritative in SSR, unlike readerState which fills in later)
  const urlSlug = $derived(
    Number(page.url.pathname.split("/").filter(Boolean)[3]) ||
      Number(readerState.ch_meta.slug) ||
      1
  );
  const switchTarget = $derived.by(() => {
    const targetTl = isPt ? enTl : ptTl;
    const chapters = bookData[bookSlug]?.[targetTl] || [];
    const exists = chapters.some((ch: any) => Number(ch.slug) === urlSlug);
    return { tl: targetTl, slug: exists ? urlSlug : 1 };
  });

  // Logic
  const chapterList = $derived.by(() => {
    const chapters = bookData[bookSlug]?.[navState.selectedTL] || [];
    const q = navState.searchQuery.toLowerCase();
    return chapters.filter(
      (ch: any) =>
        ch.title.toLowerCase().includes(q) || ch.slug.toString().includes(q),
    );
  });

  function toggleFullscreen() {
    if (offline) {
      modals.chapter?.close();
      modals.settings?.close();
      window.dispatchEvent(new CustomEvent("reader-fullscreen"));
      return;
    }
    if (!document.fullscreenElement) {
      modals.chapter?.close();
      modals.settings?.close();
      modals.edit?.close();
      document.documentElement.requestFullscreen().catch(console.error);
    } else {
      document.exitFullscreen();
    }
  }

  // Exports
  export const openTOC = () => {
    modals.chapter?.showModal();
    setTimeout(() => {
      modals.chapter
        ?.querySelector(".btn-primary")
        ?.scrollIntoView({ block: "center" });
    }, 0);
  };
  export const openSettings = () => modals.settings?.showModal();
  export const openEdit = () => modals.edit?.showModal();
</script>

{#if prefs.config.navbarVisible}
  <nav
    class="flex w-full items-center justify-center gap-5 bg-base-100 border-b border-base-content/10 p-3 z-50 {prefs
      .config.navbarSticky
      ? 'sticky top-0'
      : 'relative'}"
  >
    <div class="tooltip tooltip-bottom" data-tip="Home (H)">
      <a
        href="/book/{bookSlug}"
        aria-label="Library"
        class="btn btn-ghost btn-sm btn-square rounded-btn"
      >
        <Icon icon="material-symbols:home-outline-rounded" class="size-6" />
      </a>
    </div>

    {#if !offline}
    <div class="tooltip tooltip-bottom" data-tip="Comments (C)">
      <button
        onclick={() => {
          if (typeof window !== "undefined") {
            window.dispatchEvent(new CustomEvent("open-comments"));
          }
          document
            .getElementById("comments")
            ?.scrollIntoView({ behavior: "smooth" });
        }}
        class="btn btn-ghost btn-sm btn-square rounded-btn"
      >
        <Icon icon="iconamoon:comment" class="size-6" />
      </button>
    </div>

    {/if}
    <div class="tooltip tooltip-bottom" data-tip="Table of Contents (T)">
      <button onclick={openTOC} aria-label="Table of contents" class="btn btn-outline btn-sm rounded-btn">
        <Icon icon="lucide:table-of-contents" class="size-5" />
        <span class="hidden sm:inline">Contents</span>
      </button>
    </div>

    {#if hasPtBr}
      <div
        class="tooltip tooltip-bottom"
        data-tip={isPt ? "Switch to English" : "Mudar para Português (BR)"}
      >
        <a
          href="/read/{bookSlug}/{switchTarget.tl}/{switchTarget.slug}"
          class="btn btn-outline btn-sm rounded-btn {isPt ? '' : 'btn-accent'}"
        >
          <Icon icon="material-symbols:translate-rounded" class="size-5" />
          <span class="hidden sm:inline font-bold">{isPt ? "EN" : "PT-BR"}</span>
        </a>
      </div>
    {/if}

    {#if !offline}
    <div class="tooltip tooltip-bottom" data-tip="Edit (E)">
      <button
        onclick={openEdit}
        class="btn btn-ghost btn-sm btn-square rounded-btn"
      >
        <Icon icon="material-symbols:edit-outline-rounded" class="size-6" />
      </button>
    </div>

    {/if}
    <div class="tooltip tooltip-bottom" data-tip="Settings (S)">
      <button
        onclick={openSettings}
        aria-label="Reader settings"
        class="btn btn-ghost btn-sm btn-square rounded-btn"
      >
        <Icon icon="material-symbols:settings-outline-rounded" class="size-6" />
      </button>
    </div>

    {#if !offline}<AccountMenu scope={{ book: bookSlug, tl: urlTl }} />{/if}
  </nav>
{:else}
  <div class="fixed top-3 right-3 z-50 flex items-center gap-1 rounded-btn bg-base-100/90 shadow-md">
    {#if !offline}<AccountMenu scope={{ book: bookSlug, tl: urlTl }} />{/if}
    <button
      class="btn btn-circle btn-ghost"
      onclick={() => (prefs.config.navbarVisible = true)}
      aria-label="Show navigation"
    >
      <Icon icon="material-symbols:menu-rounded" class="size-6" />
    </button>
  </div>
{/if}

<dialog bind:this={modals.chapter} class="modal modal-bottom sm:modal-middle">
  <div
    class="modal-box bg-base-100 p-0 rounded-t-2xl sm:rounded-box max-h-[80vh] flex flex-col"
  >
    <div
      class="sticky top-0 z-10 bg-base-100/95 backdrop-blur border-b border-base-content/10 p-4 space-y-3"
    >
      <div class="flex justify-between items-center">
        <h3 class="font-bold text-lg text-primary">Contents</h3>
        <form method="dialog">
          <button class="btn btn-sm btn-circle btn-ghost">✕</button>
        </form>
      </div>
      <div class="flex gap-2">
        <input
          type="search"
          bind:value={navState.searchQuery}
          placeholder="Search..."
          class="input input-bordered input-sm grow rounded-btn focus:input-primary"
        />
        <select
          class="select select-bordered select-sm rounded-btn focus:select-primary"
          bind:value={navState.selectedTL}
        >
          {#each Object.keys(bookData[bookSlug] || {}) as tl}
            <option value={tl}>{tlLabel(tl)}</option>
          {/each}
        </select>
      </div>
    </div>

    <div class="overflow-y-auto p-2">
      {#each chapterList as ch}
        <a
          href="/read/{bookSlug}/{navState.selectedTL}/{ch.slug}"
          class="btn btn-sm justify-start w-full font-normal border-none mb-1 rounded-btn {readerState
            .ch_meta.slug == ch.slug
            ? 'btn-primary btn-soft'
            : 'btn-ghost'}"
          onclick={() => modals.chapter?.close()}
        >
          <span class="w-10 font-mono text-xs opacity-50">#{ch.slug}</span>
          <span class="truncate">{ch.title}</span>
        </a>
      {/each}
    </div>
  </div>
  <form method="dialog" class="modal-backdrop"><button>close</button></form>
</dialog>

<dialog bind:this={modals.settings} class="modal sm:modal-middle modal-bottom">
  <div class="modal-box bg-base-100 rounded-box">
    <div
      class="flex justify-between items-center mb-6 border-b border-base-content/10 pb-4"
    >
      <h3 class="font-bold text-lg flex items-center gap-2 text-primary">
        <Icon icon="material-symbols:settings-outline-rounded" /> Settings
      </h3>
      <div class="flex gap-2">
        <button
          class="btn btn-xs btn-ghost text-error rounded-btn"
          onclick={() => prefs.reset()}>Reset</button
        >
        <form method="dialog">
          <button class="btn btn-sm btn-circle btn-ghost">✕</button>
        </form>
      </div>
    </div>

    <div class="grid md:grid-cols-2 gap-8">
      <div class="space-y-4">
        <h4 class="text-xs font-bold opacity-50 uppercase tracking-widest">
          Appearance
        </h4>

        <div class="form-control">
          <label for="reader-theme" class="label"><span class="label-text">Theme</span></label>
          <select
            id="reader-theme"
            class="select select-bordered select-sm w-full rounded-btn focus:select-primary"
            bind:value={prefs.config.theme}
          >
            <optgroup label="Recommended">
              {#each PRIORITY_THEMES as t}
                <option value={t}
                  >{t.charAt(0).toUpperCase() + t.slice(1)}</option
                >
              {/each}
            </optgroup>
            <optgroup label="Other Themes">
              {#each MISC_THEMES as t}
                <option value={t}
                  >{t.charAt(0).toUpperCase() + t.slice(1)}</option
                >
              {/each}
            </optgroup>
          </select>
        </div>

        <div class="form-control">
          <label for="reader-font" class="label"><span class="label-text">Font</span></label>
          <select
            id="reader-font"
            class="select select-bordered select-sm w-full rounded-btn focus:select-primary"
            bind:value={prefs.config.font}
          >
            <optgroup label="Book Fonts">
              {#each BOOK_FONTS as f}
                <option value={f} style="font-family: {f}">{f}</option>
              {/each}
            </optgroup>
            <optgroup label="System Fonts">
              {#each SYSTEM_FONTS as f}
                <option value={f} style="font-family: {f}">{f}</option>
              {/each}
            </optgroup>
          </select>
        </div>

        <div class="form-control">
          <label class="label cursor-pointer justify-start gap-3">
            <input
              type="checkbox"
              class="toggle toggle-primary toggle-sm"
              bind:checked={prefs.config.solidBackground}
            />
            <span class="label-text">Solid Background</span>
          </label>
        </div>
      </div>

      <div class="space-y-4">
        <h4 class="text-xs font-bold opacity-50 uppercase tracking-widest">
          Readability
        </h4>
        <div class="grid grid-cols-2 gap-4">
          <div class="form-control">
            <label for="reader-size" class="label text-xs">Size ({prefs.config.fontSize}px)</label
            >
            <input
              type="range"
              id="reader-size"
              min="12"
              max="32"
              class="range range-xs range-primary"
              bind:value={prefs.config.fontSize}
            />
          </div>
          <div class="form-control">
            <label for="reader-height" class="label text-xs"
              >Height ({prefs.config.lineHeight})</label
            >
            <input
              type="range"
              id="reader-height"
              min="1.2"
              max="2.5"
              step="0.1"
              class="range range-xs range-secondary"
              bind:value={prefs.config.lineHeight}
            />
          </div>
        </div>
        <div class="form-control">
          <label for="reader-weight" class="label text-xs">Weight ({prefs.config.fontWeight})</label
          >
          <input
            type="range"
            id="reader-weight"
            min="300"
            max="900"
            step="25"
            class="range range-xs range-accent"
            bind:value={prefs.config.fontWeight}
          />
        </div>
        <div class="join w-full">
          {#each ["left", "center", "right", "justify"] as align}
            <button
              class="join-item btn btn-xs grow {prefs.config.textAlign === align
                ? 'btn-primary'
                : 'btn-ghost bg-base-200'}"
              onclick={() => (prefs.config.textAlign = align)}
              aria-label="Align text {align}"
            >
              <Icon icon="material-symbols:format-align-{align}" />
            </button>
          {/each}
        </div>
        <div class="flex flex-col gap-1 pt-2">
          <div class="form-control">
            <label class="label cursor-pointer justify-start gap-3">
              <input
                type="checkbox"
                class="toggle toggle-primary toggle-sm"
                bind:checked={prefs.config.indent}
              />
              <span class="label-text">Indent Paragraphs</span>
            </label>
          </div>
          <div class="form-control">
            <label class="label cursor-pointer justify-start gap-3">
              <input
                type="checkbox"
                class="toggle toggle-secondary toggle-sm"
                bind:checked={prefs.config.hyphens}
              />
              <span class="label-text">Auto-Hyphenation</span>
            </label>
          </div>
        </div>

        <div class="divider my-2"></div>
        <h4 class="text-xs font-bold opacity-50 uppercase tracking-widest">
          Interface
        </h4>

        <button
          class="btn btn-outline btn-primary btn-sm w-full rounded-btn"
          onclick={toggleFullscreen}
        >
          <Icon icon="material-symbols:fullscreen" class="size-5" /> Toggle Fullscreen
        </button>

        <div class="flex flex-col gap-1">
          <div class="form-control">
            <label class="label cursor-pointer justify-start gap-3">
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-accent"
                bind:checked={prefs.config.navbarSticky}
              />
              <span class="label-text">Sticky Navbar</span>
            </label>
          </div>
          <div class="form-control">
            <label class="label cursor-pointer justify-start gap-3">
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-accent"
                bind:checked={prefs.config.navbarVisible}
              />
              <span class="label-text">Show Navbar</span>
            </label>
          </div>
          {#if !offline}
          <div class="form-control">
            <label class="label cursor-pointer justify-start gap-3">
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-accent"
                bind:checked={prefs.config.showBottomBanner}
              />
              <span class="label-text">Info Banner</span>
            </label>
          </div>
          <div class="form-control">
            <label class="label cursor-pointer justify-start gap-3">
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-accent"
                bind:checked={prefs.config.showComments}
              />
              <span class="label-text">Show Comments</span>
            </label>
          </div>
          {/if}
        </div>
      </div>
    </div>
  </div>
  <form method="dialog" class="modal-backdrop"><button>close</button></form>
</dialog>

<dialog bind:this={modals.edit} class="modal modal-bottom sm:modal-middle">
  <div class="modal-box bg-base-100 rounded-box">
    <form method="dialog">
      <button class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
        >✕</button
      >
    </form>
    <h3 class="font-bold text-lg mb-4 text-primary">Contribute</h3>
    <div class="flex flex-col gap-3">
      <a
        href="https://github.com/Bittu5134/LOTM-Reader/blob/main/contributing.md"
        target="_blank"
        class="btn btn-outline btn-primary w-full rounded-btn"
      >
        <Icon icon="mdi:book-open-page-variant" class="size-5 mr-2" /> Read Guide
      </a>
      <a
        href="https://github.com/Bittu5134/LOTM-Reader/blob/main/chapters/{bookSlug}/{navState.selectedTL}/{readerState.ch_meta.slug
          .toString()
          .padStart(4, '0')}.md"
        target="_blank"
        class="btn btn-secondary w-full rounded-btn"
      >
        <Icon icon="mdi:github" class="size-5 mr-2" /> Edit this chapter on Github
      </a>
    </div>
  </div>
  <form method="dialog" class="modal-backdrop"><button>close</button></form>
</dialog>
