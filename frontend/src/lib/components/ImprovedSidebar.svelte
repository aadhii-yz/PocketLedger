<script lang="ts">
  import type { ComponentType } from "svelte";
  import type { Icon } from "lucide-svelte";
  import { ShoppingBag, Menu, ChevronLeft, LogOut } from "lucide-svelte";
  import { goto } from "$app/navigation";
  import { page } from "$app/stores";
  import { onMount } from "svelte";
  import { pb } from "$lib/pb";
  import { slide } from "svelte/transition";

  interface MenuItem {
    label: string;
    icon: ComponentType<Icon>;
    path: string;
    onclick?: () => void;
  }

  interface Props {
    menuItems: MenuItem[];
    userRole: string;
  }

  let { menuItems, userRole }: Props = $props();

  let isCollapsed = $state(false);
  let isMobile = $state(false);

  function checkMobile() {
    isMobile = window.innerWidth < 1024;
    if (isMobile) isCollapsed = true;
  }

  onMount(() => {
    checkMobile();
    window.addEventListener("resize", checkMobile);
    return () => window.removeEventListener("resize", checkMobile);
  });

  function toggleSidebar() {
    isCollapsed = !isCollapsed;
  }

  function handleLogout() {
    pb.authStore.clear();
    goto("/");
  }
</script>

<!-- Toggle button -->
<button
  onclick={toggleSidebar}
  class="fixed top-4 left-4 z-50 p-3 bg-sidebar text-sidebar-foreground rounded-xl shadow-lg hover:shadow-xl transition-all hover:scale-105 active:scale-95"
  title={isCollapsed ? "Expand sidebar" : "Collapse sidebar"}
>
  {#if isCollapsed}
    <Menu class="w-6 h-6" />
  {:else}
    <ChevronLeft class="w-6 h-6" />
  {/if}
</button>

<!-- Sidebar -->
<aside
  class="fixed left-0 top-0 h-screen bg-sidebar text-sidebar-foreground border-r border-sidebar-border z-40 overflow-hidden transition-all duration-300 ease-in-out"
  style="width: {isCollapsed ? '80px' : '260px'};"
>
  <div class="flex flex-col h-full pt-20 pb-6">
    <!-- Logo/Brand -->
    <div class="px-4 mb-8">
      <div class="flex items-center gap-3">
        <div
          class="w-10 h-10 bg-sidebar-primary rounded-lg flex items-center justify-center shrink-0"
        >
          <ShoppingBag class="w-6 h-6 text-sidebar-primary-foreground" />
        </div>
        {#if !isCollapsed}
          <div
            transition:slide={{ axis: "x", duration: 200 }}
            class="overflow-hidden"
          >
            <h1 class="text-lg font-semibold whitespace-nowrap">My Garments</h1>
            <p
              class="text-xs text-sidebar-foreground/60 capitalize whitespace-nowrap"
            >
              {userRole}
            </p>
          </div>
        {/if}
      </div>
    </div>

    <!-- Navigation -->
    <nav class="flex-1 px-3 space-y-1 overflow-y-auto">
      {#each menuItems as item}
        {@const isActive = !item.onclick && $page.url.pathname === item.path}
        <button
          onclick={() => item.onclick ? item.onclick() : goto(item.path)}
          class="w-full flex items-center gap-3 px-3 py-3 rounded-lg transition-all hover:translate-x-0.5 {isActive
            ? 'bg-sidebar-accent text-sidebar-accent-foreground shadow-sm'
            : 'hover:bg-sidebar-accent/50 text-sidebar-foreground'} {isCollapsed
            ? 'justify-center'
            : ''}"
          title={isCollapsed ? item.label : undefined}
        >
          <item.icon class="w-5 h-5 shrink-0" />
          {#if !isCollapsed}
            <span
              transition:slide={{ axis: "x", duration: 200 }}
              class="overflow-hidden whitespace-nowrap"
            >
              {item.label}
            </span>
          {/if}
        </button>
      {/each}
    </nav>

    <!-- Logout -->
    <div class="px-3 mt-auto">
      <button
        onclick={handleLogout}
        class="w-full flex items-center gap-3 px-3 py-3 rounded-lg bg-destructive text-destructive-foreground hover:opacity-90 transition-all hover:scale-[1.02] {isCollapsed
          ? 'justify-center'
          : ''}"
        title={isCollapsed ? "Logout" : undefined}
      >
        <LogOut class="w-5 h-5 shrink-0" />
        {#if !isCollapsed}
          <span
            transition:slide={{ axis: "x", duration: 200 }}
            class="overflow-hidden whitespace-nowrap"
          >
            Logout
          </span>
        {/if}
      </button>
    </div>
  </div>
</aside>

<!-- Spacer -->
<div
  class="shrink-0 transition-all duration-300 ease-in-out"
  style="width: {isCollapsed ? '80px' : '260px'};"
></div>
