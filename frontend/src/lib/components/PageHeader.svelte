<script lang="ts">
  import type { ComponentType } from "svelte";
  import type { Icon } from "lucide-svelte";
  import { fly } from "svelte/transition";

  interface Props {
    title: string;
    subtitle?: string;
    icon?: ComponentType<Icon>;
    action?: import("svelte").Snippet;
  }

  let { title, subtitle, icon: IconComponent, action }: Props = $props();
</script>

<div
  in:fly={{ y: -20, duration: 300 }}
  class="flex items-center justify-between mb-8"
>
  <div class="flex items-center gap-4">
    {#if IconComponent}
      <div
        class="w-14 h-14 bg-primary/10 rounded-xl flex items-center justify-center"
      >
        <IconComponent class="w-7 h-7 text-primary" />
      </div>
    {/if}
    <div>
      <h1 class="mb-1">{title}</h1>
      {#if subtitle}
        <p class="text-muted-foreground">{subtitle}</p>
      {/if}
    </div>
  </div>
  {#if action}
    <div>
      {@render action()}
    </div>
  {/if}
</div>
