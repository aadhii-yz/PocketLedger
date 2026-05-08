<script lang="ts">
  interface Props {
    id?: string;
    label?: string;
    type?: string;
    placeholder?: string;
    value: string;
    onchange?: (value: string) => void;
    icon?: import("svelte").Snippet;
    required?: boolean;
    disabled?: boolean;
    list?: string;
  }

  let {
    id = `input-${Math.random().toString(36).substring(2, 9)}`,
    label,
    type = "text",
    placeholder = "",
    value = $bindable(),
    onchange,
    icon,
    required = false,
    disabled = false,
    list,
  }: Props = $props();

  let focused = $state(false);
  let hasValue = $derived(value && value.length > 0);
  let isActive = $derived(focused || hasValue);

  function handleInput(e: Event) {
    const target = e.target as HTMLInputElement;
    value = target.value;
    if (onchange) {
      onchange(value);
    }
  }
</script>

<div class="relative w-full mb-6">
  <div class="relative">
    {#if icon}
      <div
        class="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground transition-all z-10 {isActive
          ? 'opacity-50'
          : 'opacity-100'}"
      >
        {@render icon()}
      </div>
    {/if}
    <input
      {id}
      {type}
      {value}
      oninput={handleInput}
      onfocus={() => (focused = true)}
      onblur={() => (focused = false)}
      placeholder={isActive ? placeholder : ""}
      {required}
      {disabled}
      {list}
      class="w-full px-4 {icon
        ? 'pl-10'
        : ''} pt-6 pb-2 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all disabled:opacity-50 disabled:cursor-not-allowed"
    />
    {#if label}
      <label
        for={id}
        class="absolute {icon
          ? 'left-10'
          : 'left-4'} pointer-events-none origin-left z-20 transition-all duration-200 {isActive
          ? 'text-primary'
          : 'text-muted-foreground'}"
        style="top: {isActive
          ? '0.5rem'
          : '50%'}; transform: translateY({isActive
          ? '0%'
          : '-50%'}); font-size: {isActive ? '0.75rem' : '1rem'};"
      >
        {label}
        {#if required}<span class="text-destructive">*</span>{/if}
      </label>
    {/if}
  </div>
</div>
