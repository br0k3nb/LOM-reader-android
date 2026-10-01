<script lang="ts">
  import css from "../../../../reader.css?url";
  import { readerState } from "$lib/reader.svelte";

  let { data } = $props();

  // Same component instance is reused across chapter navigations,
  // so sync metadata reactively (static pages did this once at init).
  $effect(() => {
    readerState.ch_meta = {
      title: data.chapter.title,
      slug: data.chapter.slug,
      category: data.chapter.category,
      index: data.chapter.idx,
      section: data.chapter.section,
      discussion: data.chapter.discussion,
      description: "",
    };
  });
</script>

<svelte:head>
  <link rel="stylesheet" href={css} />
</svelte:head>

{@html data.chapter.html}
