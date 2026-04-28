<script lang="ts">
  import type { ComponentType } from "svelte";
  import type { Icon } from "lucide-svelte";
  import { fly } from "svelte/transition";

  interface Props {
    title: string;
    value: string | number;
    change?: string;
    icon: ComponentType<Icon>;
    trend?: "up" | "down" | "neutral";
    delay?: number;
  }

  let {
    title,
    value,
    change,
    icon: IconComponent,
    trend = "neutral",
    delay = 0,
  }: Props = $props();

  const trendColors = {
    up: "text-green-600",
    down: "text-red-600",
    neutral: "text-muted-foreground",
  };
</script>

<div
  in:fly={{ y: 20, duration: 300, delay: delay * 1000 }}
  class="bg-card rounded-xl p-6 shadow-sm border border-border cursor-pointer transition-transform hover:-translate-y-1"
>
  <div class="flex items-start justify-between mb-4">
    <div class="flex-1">
      <p class="text-sm text-muted-foreground mb-1">{title}</p>
      <h3 class="text-3xl">{value}</h3>
    </div>
    <div
      class="w-12 h-12 bg-primary/10 rounded-lg flex items-center justify-center"
    >
      <IconComponent class="w-6 h-6 text-primary" />
    </div>
  </div>
  {#if change}
    <p class="text-sm {trendColors[trend]}">
      {#if trend === "up"}↑
      {/if}
      {#if trend === "down"}↓
      {/if}
      {change}
    </p>
  {/if}
</div>
