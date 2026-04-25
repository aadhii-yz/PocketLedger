<script lang="ts">
  import type { ComponentType } from "svelte";
  import type { Icon } from "lucide-svelte";

  interface Props {
    children?: import("svelte").Snippet;
    onclick?: (e: MouseEvent) => void;
    variant?: "primary" | "secondary" | "outline" | "ghost";
    icon?: ComponentType<Icon>;
    type?: "button" | "submit" | "reset";
    class?: string;
    disabled?: boolean;
  }

  let {
    children,
    onclick,
    variant = "primary",
    icon: IconComponent,
    type = "button",
    class: className = "",
    disabled = false,
  }: Props = $props();

  const baseStyles =
    "px-6 py-2.5 rounded-lg transition-all duration-200 flex items-center gap-2 justify-center disabled:opacity-50 disabled:cursor-not-allowed hover:scale-[1.02] active:scale-[0.98]";

  const variants = {
    primary: "bg-primary text-primary-foreground hover:opacity-90",
    secondary: "bg-secondary text-secondary-foreground hover:opacity-90",
    outline:
      "border-2 border-primary text-primary hover:bg-primary hover:text-primary-foreground",
    ghost: "hover:bg-muted text-foreground",
  };
</script>

<button
  class="{baseStyles} {variants[variant]} {className}"
  {type}
  {disabled}
  {onclick}
>
  {#if IconComponent}
    <IconComponent class="w-5 h-5" />
  {/if}
  {#if children}
    {@render children()}
  {/if}
</button>
