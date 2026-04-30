<script lang="ts">
  import "./layout.css";
  import favicon from "$lib/assets/favicon.svg";
  import OfflineIndicator from "$lib/components/OfflineIndicator.svelte";

  let { children } = $props();
</script>

<svelte:head><link rel="icon" href={favicon} /></svelte:head>
{@render children()}
<OfflineIndicator />
