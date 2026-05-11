<script lang="ts">
  import "./layout.css";
  import favicon from "$lib/assets/favicon.svg";
  import OfflineIndicator from "$lib/components/OfflineIndicator.svelte";
  import { onMount } from "svelte";

  let { children } = $props();

  onMount(() => {
    if (new URL(window.location.href).searchParams.has('companion')) {
      sessionStorage.setItem('companion_mode', '1');
    }
  });
</script>

<svelte:head><link rel="icon" href={favicon} /></svelte:head>
{@render children()}
<OfflineIndicator />
