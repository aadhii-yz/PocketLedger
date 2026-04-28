<script lang="ts">
  import ImprovedSidebar from "$lib/components/ImprovedSidebar.svelte";
  import FluidLayout from "$lib/components/FluidLayout.svelte";
  import Card from "$lib/components/Card.svelte";
  import PageHeader from "$lib/components/PageHeader.svelte";
  import LoadingSpinner from "$lib/components/LoadingSpinner.svelte";
  import {
    Users,
    Activity,
    Search,
    ChevronRight,
    RotateCw,
  } from "lucide-svelte";
  import { pb } from "$lib/pb";
  import { onMount } from "svelte";
  import { fade } from "svelte/transition";

  const menuItems = [
    { label: "Users", icon: Users, path: "/admin/users" },
    { label: "System Logs", icon: Activity, path: "/admin/logs" },
  ];

  interface ActivityLog {
    id: string;
    level: "INFO" | "ERROR" | "WARNING";
    message: string;
    statusCode: number;
    details?: string;
    createdAt: string;
    source: string;
  }

  let logs = $state<ActivityLog[]>([]);
  let loading = $state(true);
  let searchTerm = $state("");
  // Using an array for selected logs in Svelte is simpler, or we can use Set via state proxy.
  // We'll use a Set, but we need to reassign to trigger reactivity.
  let selectedLogs = $state<Set<string>>(new Set());
  let expandedLog = $state<string | null>(null);

  async function loadLogs() {
    try {
      loading = true;
      const records = await pb
        .collection("system_logs")
        .getList(1, 200, { sort: "-created" });
      const mapped: ActivityLog[] = records.items.map((r: any) => ({
        id: r.id,
        level: (r.level as ActivityLog["level"]) || "INFO",
        message: r.message || "",
        statusCode: r.status_code || 0,
        details: r.details || "",
        createdAt: r.created || "",
        source: r.source || "system",
      }));
      logs = mapped;
    } catch (e) {
      console.error("Failed to load logs", e);
    } finally {
      loading = false;
    }
  }

  onMount(() => {
    loadLogs();
  });

  let filteredLogs = $derived(
    logs.filter((log) => {
      const q = searchTerm.toLowerCase();
      return (
        log.message.toLowerCase().includes(q) ||
        log.level.toLowerCase().includes(q) ||
        (log.details || "").toLowerCase().includes(q)
      );
    }),
  );

  function toggleLogSelection(id: string) {
    const newSelected = new Set(selectedLogs);
    if (newSelected.has(id)) newSelected.delete(id);
    else newSelected.add(id);
    selectedLogs = newSelected;
  }

  function toggleAllLogs() {
    if (selectedLogs.size === filteredLogs.length && filteredLogs.length > 0) {
      selectedLogs = new Set();
    } else {
      selectedLogs = new Set(filteredLogs.map((log) => log.id));
    }
  }

  function getLevelBadgeColor(level: ActivityLog["level"]) {
    switch (level) {
      case "INFO":
        return "bg-green-100 text-green-700 border-green-200";
      case "ERROR":
        return "bg-red-100 text-red-700 border-red-200";
      case "WARNING":
        return "bg-yellow-100 text-yellow-700 border-yellow-200";
      default:
        return "bg-gray-100 text-gray-700 border-gray-200";
    }
  }

  function getRowBg(level: ActivityLog["level"]) {
    switch (level) {
      case "ERROR":
        return "bg-red-50 hover:bg-red-100";
      case "WARNING":
        return "bg-yellow-50 hover:bg-yellow-100";
      default:
        return "bg-white hover:bg-muted/50";
    }
  }
</script>

<svelte:head>
  <title>Activity Logs - My Garments</title>
</svelte:head>

<div class="flex min-h-screen bg-background">
  <ImprovedSidebar {menuItems} userRole="Admin" />

  {#snippet actionButton()}
    <button
      onclick={loadLogs}
      class="p-2 hover:bg-muted rounded-lg transition-colors"
      title="Refresh"
    >
      <RotateCw class="w-5 h-5 text-muted-foreground" />
    </button>
  {/snippet}

  <FluidLayout>
    <PageHeader
      title="Activity Logs"
      subtitle="Recent billing and stock operations"
      icon={Activity}
      action={actionButton}
    />

    <Card class="mb-6">
      <div class="relative">
        <Search
          class="w-5 h-5 absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground"
        />
        <input
          type="text"
          placeholder="Search logs…"
          bind:value={searchTerm}
          class="w-full pl-10 pr-4 py-2.5 bg-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all"
        />
      </div>
    </Card>

    <Card class="overflow-hidden">
      {#if loading}
        <LoadingSpinner />
      {:else}
        <div class="overflow-x-auto">
          <table class="w-full">
            <thead class="bg-muted/50 border-b border-border">
              <tr>
                <th class="px-4 py-3 text-left w-12">
                  <input
                    type="checkbox"
                    checked={selectedLogs.size === filteredLogs.length &&
                      filteredLogs.length > 0}
                    onchange={toggleAllLogs}
                    class="w-4 h-4 rounded border-border"
                  />
                </th>
                <th class="px-4 py-3 text-left">Level</th>
                <th class="px-4 py-3 text-left">Message</th>
                <th class="px-4 py-3 text-left w-24">Status</th>
                <th class="px-4 py-3 text-left w-52">Created</th>
                <th class="px-4 py-3 w-12"></th>
              </tr>
            </thead>
            <tbody>
              {#each filteredLogs as log (log.id)}
                <!-- Main Row -->
                <tr
                  class="border-b border-border transition-colors cursor-pointer {getRowBg(
                    log.level,
                  )}"
                  onclick={() =>
                    (expandedLog = expandedLog === log.id ? null : log.id)}
                  transition:fade={{ duration: 150 }}
                >
                  <td class="px-4 py-3" onclick={(e) => e.stopPropagation()}>
                    <input
                      type="checkbox"
                      checked={selectedLogs.has(log.id)}
                      onchange={() => toggleLogSelection(log.id)}
                      class="w-4 h-4 rounded border-border"
                    />
                  </td>
                  <td class="px-4 py-3">
                    <span
                      class="inline-flex items-center gap-1 px-2 py-1 rounded text-xs font-medium border {getLevelBadgeColor(
                        log.level,
                      )}"
                    >
                      <span class="w-1.5 h-1.5 rounded-full bg-current"></span>
                      {log.level}
                    </span>
                  </td>
                  <td class="px-4 py-3">
                    <div class="font-mono text-sm">{log.message}</div>
                    {#if log.details}
                      <div class="text-xs text-muted-foreground mt-1">
                        {log.details}
                      </div>
                    {/if}
                  </td>
                  <td class="px-4 py-3">
                    <span
                      class="font-mono text-sm px-2 py-1 rounded {log.statusCode <
                      300
                        ? 'bg-green-100 text-green-700'
                        : 'bg-red-100 text-red-700'}"
                    >
                      {log.statusCode}
                    </span>
                  </td>
                  <td class="px-4 py-3">
                    <div class="text-sm">
                      <div>{log.createdAt.split(" ")[0]}</div>
                      <div class="text-muted-foreground font-mono text-xs">
                        {log.createdAt.split(" ")[1]}
                      </div>
                    </div>
                  </td>
                  <td class="px-4 py-3">
                    <ChevronRight
                      class="w-4 h-4 text-muted-foreground transition-transform {expandedLog ===
                      log.id
                        ? 'rotate-90'
                        : ''}"
                    />
                  </td>
                </tr>

                <!-- Expanded Details -->
                {#if expandedLog === log.id}
                  <tr
                    transition:fade={{ duration: 150 }}
                    class={getRowBg(log.level)}
                  >
                    <td colspan="6" class="px-4 py-4 border-b border-border">
                      <div class="bg-muted/50 rounded-lg p-4 font-mono text-sm">
                        <div class="grid grid-cols-2 gap-4">
                          <div>
                            <span class="text-muted-foreground"
                              >Full Message:</span
                            >
                            <div class="mt-1">{log.message}</div>
                          </div>
                          <div>
                            <span class="text-muted-foreground">Details:</span>
                            <div class="mt-1">
                              {log.details || "No additional details"}
                            </div>
                          </div>
                          <div>
                            <span class="text-muted-foreground"
                              >Status Code:</span
                            >
                            <div class="mt-1">{log.statusCode}</div>
                          </div>
                          <div>
                            <span class="text-muted-foreground">Source:</span>
                            <div class="mt-1 capitalize">{log.source}</div>
                          </div>
                        </div>
                      </div>
                    </td>
                  </tr>
                {/if}
              {/each}
            </tbody>
          </table>
        </div>

        <div
          class="flex items-center justify-between px-6 py-4 border-t border-border"
        >
          <div class="text-sm text-muted-foreground">
            Showing {filteredLogs.length} of {logs.length} logs
          </div>
        </div>
      {/if}
    </Card>
  </FluidLayout>
</div>
