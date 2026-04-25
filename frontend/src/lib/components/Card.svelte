<script lang="ts">
  import type { ComponentType } from 'svelte';
  import type { Icon } from 'lucide-svelte';
  import { fly } from 'svelte/transition';

  interface Props {
    title?: string;
    value?: string | number;
    subtitle?: string;
    icon?: ComponentType<Icon>;
    iconColor?: string;
    children?: import('svelte').Snippet;
    class?: string;
  }

  let {
    title,
    value,
    subtitle,
    icon: IconComponent,
    iconColor,
    children,
    class: className = ''
  }: Props = $props();
</script>

<div
  in:fly={{ y: 20, duration: 300 }}
  class="bg-card rounded-xl p-6 shadow-sm border border-border {className}"
>
  {#if IconComponent}
    <div class="w-12 h-12 rounded-lg flex items-center justify-center mb-4 {iconColor || 'bg-primary/10'}">
      <IconComponent class="w-6 h-6 {iconColor ? 'text-primary' : 'text-primary'}" />
    </div>
  {/if}
  {#if title}
    <h3 class="text-muted-foreground mb-1">{title}</h3>
  {/if}
  {#if value}
    <div class="text-3xl mb-1">{value}</div>
  {/if}
  {#if subtitle}
    <p class="text-sm text-muted-foreground">{subtitle}</p>
  {/if}
  {#if children}
    {@render children()}
  {/if}
</div>
