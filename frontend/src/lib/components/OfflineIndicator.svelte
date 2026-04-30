<script lang="ts">
  let online = $state(true);

  $effect(() => {
    online = navigator.onLine;
    const setOnline = () => (online = true);
    const setOffline = () => (online = false);
    window.addEventListener('online', setOnline);
    window.addEventListener('offline', setOffline);
    return () => {
      window.removeEventListener('online', setOnline);
      window.removeEventListener('offline', setOffline);
    };
  });
</script>

{#if !online}
  <div class="fixed bottom-0 left-0 right-0 z-50 bg-yellow-500 px-4 py-2 text-center text-sm font-medium text-yellow-950">
    You are offline — showing cached data. Transactions are disabled.
  </div>
{/if}
