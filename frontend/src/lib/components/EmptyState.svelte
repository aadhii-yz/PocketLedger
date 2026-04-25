<script lang="ts">
  import type { ComponentType } from "svelte";
  import type { Icon } from "lucide-svelte";

  interface Props {
    icon: ComponentType<Icon>;
    title: string;
    description?: string;
  }

  let { icon: IconComponent, title, description }: Props = $props();
</script>

<div class="flex flex-col items-center justify-center p-12 text-center">
  <div
    class="w-20 h-20 bg-muted rounded-full flex items-center justify-center mb-4"
  >
    <IconComponent class="w-10 h-10 text-muted-foreground opacity-50" />
  </div>
  <h3 class="text-muted-foreground mb-2">{title}</h3>
  {#if description}
    <p class="text-sm text-muted-foreground">{description}</p>
  {/if}
</div>
