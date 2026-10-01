<script lang="ts">
  import icons from './icons.json';
  let { icon, ...rest } = $props();
  const data = $derived((icons as any)[icon]);
</script>
{#if data}
  <svg xmlns="http://www.w3.org/2000/svg" width="1em" height="1em" viewBox="0 0 {data.width} {data.height}" aria-hidden="true" {...rest}>{@html data.body}</svg>
{/if}
