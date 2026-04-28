<script lang="ts">
  interface Props {
    children?: import("svelte").Snippet;
    maxWidth?: "full" | "7xl" | "6xl" | "5xl";
  }

  let { children, maxWidth = "7xl" }: Props = $props();

  const maxWidthClass = {
    full: "max-w-full",
    "7xl": "max-w-7xl",
    "6xl": "max-w-6xl",
    "5xl": "max-w-5xl",
  };
</script>

<main
  class="flex-1 w-full p-4 md:p-6 lg:p-8 fabric-pattern min-h-screen overflow-x-hidden transition-all duration-300"
>
  <div class="{maxWidthClass[maxWidth]} mx-auto w-full">
    {#if children}
      {@render children()}
    {/if}
  </div>
</main>
