<script lang="ts">
  import ImprovedSidebar from "$lib/components/ImprovedSidebar.svelte";
  import FluidLayout from "$lib/components/FluidLayout.svelte";
  import Card from "$lib/components/Card.svelte";
  import Button from "$lib/components/Button.svelte";
  import PageHeader from "$lib/components/PageHeader.svelte";
  import LoadingSpinner from "$lib/components/LoadingSpinner.svelte";
  import {
    Package,
    ShoppingBag,
    Warehouse,
    Store,
    ArrowLeftRight,
    Plus,
    X,
    CheckCircle,
    XCircle,
    AlertCircle,
    Trash2,
    TrendingUp,
    Receipt,
  } from "lucide-svelte";
  import { pb, customFetch } from "$lib/pb";
  import { onMount } from "svelte";
  import { slide } from "svelte/transition";

  const menuItems = [
    { label: "Product Management", icon: ShoppingBag, path: "/stock/products" },
    { label: "Stock Management", icon: Package, path: "/stock/inventory" },
    { label: "Warehouse", icon: Warehouse, path: "/stock/warehouse" },
    { label: "Shop Stock", icon: Store, path: "/stock/shops" },
    { label: "Transfers", icon: ArrowLeftRight, path: "/stock/transfers" },
    { label: "Shop Stats", icon: TrendingUp, path: "/stats/overview" },
  ];

  interface Location {
    id: string;
    name: string;
    type: string;
  }

  interface TransferItem {
    product_id: string;
    quantity: number;
    note: string;
  }

  interface Transfer {
    id: string;
    transfer_number: string;
    from_location: string;
    from_location_name: string;
    to_location: string;
    to_location_name: string;
    status: "pending" | "completed" | "cancelled";
    notes: string;
    created: string;
  }

  interface ProductOption {
    id: string;
    name: string;
    sku: string;
    barcode: string;
  }

  let transfers = $state<Transfer[]>([]);
  let locations = $state<Location[]>([]);
  let productOptions = $state<ProductOption[]>([]);
  let loading = $state(true);
  let errorMsg = $state("");
  let actionMsg = $state("");
  let showCreateForm = $state(false);
  let submitting = $state(false);
  let filterStatus = $state("");

  let formData = $state({
    from_location: "",
    to_location: "",
    notes: "",
  });
  let formItems = $state<TransferItem[]>([
    { product_id: "", quantity: 1, note: "" },
  ]);

  onMount(async () => {
    try {
      const [transferRecords, locationRecords, productRecords] =
        await Promise.all([
          customFetch("/transfers"),
          pb
            .collection("locations")
            .getFullList({ filter: "is_active = true", sort: "name" }),
          pb.collection("products").getFullList({ sort: "name" }),
        ]);
      transfers = transferRecords;
      locations = locationRecords.map((l: any) => ({
        id: l.id,
        name: l.name,
        type: l.type,
      }));
      productOptions = productRecords.map((p: any) => ({
        id: p.id,
        name: p.name,
        sku: p.sku || "",
        barcode: p.barcode || "",
      }));
    } catch (e: any) {
      errorMsg = e.message || "Failed to load transfers";
    } finally {
      loading = false;
    }
  });

  async function refreshTransfers() {
    const param = filterStatus ? `?status=${filterStatus}` : "";
    transfers = await customFetch(`/transfers${param}`);
  }

  function addItem() {
    formItems = [...formItems, { product_id: "", quantity: 1, note: "" }];
  }

  function removeItem(i: number) {
    formItems = formItems.filter((_, idx) => idx !== i);
  }

  async function handleCreateTransfer(e: SubmitEvent) {
    e.preventDefault();
    errorMsg = "";
    if (formData.from_location === formData.to_location) {
      errorMsg = "Source and destination locations must be different.";
      return;
    }
    if (formItems.some((item) => !item.product_id || item.quantity <= 0)) {
      errorMsg = "All items must have a product and a positive quantity.";
      return;
    }
    submitting = true;
    try {
      await customFetch("/transfers/create", {
        method: "POST",
        body: JSON.stringify({
          from_location: formData.from_location,
          to_location: formData.to_location,
          notes: formData.notes,
          items: formItems,
        }),
      });
      formData = { from_location: "", to_location: "", notes: "" };
      formItems = [{ product_id: "", quantity: 1, note: "" }];
      showCreateForm = false;
      actionMsg = "Transfer created successfully.";
      await refreshTransfers();
    } catch (e: any) {
      errorMsg = e.message || "Failed to create transfer";
    } finally {
      submitting = false;
    }
  }

  async function handleComplete(id: string) {
    errorMsg = "";
    actionMsg = "";
    try {
      await customFetch(`/transfers/${id}/complete`, { method: "POST" });
      actionMsg = "Transfer completed. Stock has been moved.";
      await refreshTransfers();
    } catch (e: any) {
      errorMsg = e.message || "Failed to complete transfer";
    }
  }

  async function handleCancel(id: string) {
    if (!confirm("Cancel this transfer? No stock will be changed.")) return;
    errorMsg = "";
    actionMsg = "";
    try {
      await customFetch(`/transfers/${id}/cancel`, { method: "POST" });
      actionMsg = "Transfer cancelled.";
      await refreshTransfers();
    } catch (e: any) {
      errorMsg = e.message || "Failed to cancel transfer";
    }
  }

  let filteredTransfers = $derived(
    filterStatus
      ? transfers.filter((t) => t.status === filterStatus)
      : transfers,
  );

  const statusColors: Record<string, string> = {
    pending: "bg-yellow-100 text-yellow-800 border-yellow-200",
    completed: "bg-green-100 text-green-800 border-green-200",
    cancelled: "bg-gray-100 text-gray-600 border-gray-200",
  };
</script>

<svelte:head>
  <title>Stock Transfers — My Garments</title>
</svelte:head>

<div class="flex min-h-screen bg-background">
  <ImprovedSidebar {menuItems} userRole="Manager" />

  {#snippet createBtn()}
    <Button
      icon={showCreateForm ? X : Plus}
      onclick={() => {
        showCreateForm = !showCreateForm;
        errorMsg = "";
      }}
    >
      {showCreateForm ? "Cancel" : "New Transfer"}
    </Button>
  {/snippet}

  <FluidLayout>
    <PageHeader
      title="Stock Transfers"
      subtitle="Move stock between warehouse and shops"
      icon={ArrowLeftRight}
      action={createBtn}
    />

    {#if errorMsg}
      <div
        class="mb-4 flex items-center gap-2 p-3 bg-destructive/10 border border-destructive/30 rounded-lg text-destructive text-sm"
      >
        <AlertCircle class="w-4 h-4" />{errorMsg}
      </div>
    {/if}
    {#if actionMsg}
      <div
        class="mb-4 p-3 bg-green-50 border border-green-200 rounded-lg text-green-800 text-sm"
      >
        {actionMsg}
      </div>
    {/if}

    {#if showCreateForm}
      <div transition:slide={{ duration: 300 }}>
        <Card class="mb-6">
          <h3 class="mb-4 text-lg">Create Transfer</h3>
          <form onsubmit={handleCreateTransfer} class="space-y-4">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label
                  class="block mb-2 text-sm text-muted-foreground"
                  for="fromLoc"
                >
                  From <span class="text-destructive">*</span>
                </label>
                <select
                  id="fromLoc"
                  bind:value={formData.from_location}
                  class="w-full px-4 py-3 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all"
                  required
                >
                  <option value="">Select source location</option>
                  {#each locations as loc}
                    <option value={loc.id}>{loc.name} ({loc.type})</option>
                  {/each}
                </select>
              </div>
              <div>
                <label
                  class="block mb-2 text-sm text-muted-foreground"
                  for="toLoc"
                >
                  To <span class="text-destructive">*</span>
                </label>
                <select
                  id="toLoc"
                  bind:value={formData.to_location}
                  class="w-full px-4 py-3 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all"
                  required
                >
                  <option value="">Select destination location</option>
                  {#each locations.filter((l) => l.id !== formData.from_location) as loc}
                    <option value={loc.id}>{loc.name} ({loc.type})</option>
                  {/each}
                </select>
              </div>
              <div class="md:col-span-2">
                <label
                  class="block mb-2 text-sm text-muted-foreground"
                  for="trNotes">Notes</label
                >
                <input
                  id="trNotes"
                  type="text"
                  bind:value={formData.notes}
                  class="w-full px-4 py-3 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all"
                  placeholder="Optional transfer notes"
                />
              </div>
            </div>

            <!-- Items -->
            <div>
              <div class="flex items-center justify-between mb-2">
                <h4 class="text-sm font-medium text-muted-foreground">
                  Transfer Items
                </h4>
                <button
                  type="button"
                  onclick={addItem}
                  class="flex items-center gap-1 text-xs text-primary hover:underline"
                >
                  <Plus class="w-3 h-3" /> Add Item
                </button>
              </div>
              <div class="space-y-3">
                {#each formItems as item, i (i)}
                  <div class="flex gap-2 items-start p-3 bg-muted rounded-lg">
                    <div class="flex-1 grid grid-cols-1 sm:grid-cols-3 gap-2">
                      <select
                        bind:value={item.product_id}
                        class="px-3 py-2 text-sm bg-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring"
                        required
                      >
                        <option value="">Choose product</option>
                        {#each productOptions as p}
                          <option value={p.id}
                            >{p.name} ({p.barcode || p.sku})</option
                          >
                        {/each}
                      </select>
                      <input
                        type="number"
                        bind:value={item.quantity}
                        min="0.01"
                        step="any"
                        placeholder="Qty"
                        class="px-3 py-2 text-sm bg-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring"
                        required
                      />
                      <input
                        type="text"
                        bind:value={item.note}
                        placeholder="Note (optional)"
                        class="px-3 py-2 text-sm bg-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring"
                      />
                    </div>
                    {#if formItems.length > 1}
                      <button
                        type="button"
                        onclick={() => removeItem(i)}
                        class="p-2 text-destructive hover:bg-destructive/10 rounded transition-colors"
                      >
                        <Trash2 class="w-4 h-4" />
                      </button>
                    {/if}
                  </div>
                {/each}
              </div>
            </div>

            <div class="flex gap-3">
              <Button type="submit" disabled={submitting}>
                {submitting ? "Creating…" : "Create Transfer"}
              </Button>
              <Button
                type="button"
                variant="outline"
                onclick={() => {
                  showCreateForm = false;
                  errorMsg = "";
                }}
              >
                Cancel
              </Button>
            </div>
          </form>
        </Card>
      </div>
    {/if}

    <!-- Filter + List -->
    <Card>
      <div
        class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-4"
      >
        <h3 class="text-lg">Transfers ({filteredTransfers.length})</h3>
        <select
          bind:value={filterStatus}
          onchange={() => refreshTransfers()}
          class="px-3 py-2 text-sm bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring"
        >
          <option value="">All statuses</option>
          <option value="pending">Pending</option>
          <option value="completed">Completed</option>
          <option value="cancelled">Cancelled</option>
        </select>
      </div>

      {#if loading}
        <LoadingSpinner />
      {:else if filteredTransfers.length === 0}
        <div class="text-center py-12 text-muted-foreground">
          <ArrowLeftRight class="w-10 h-10 mx-auto mb-3 opacity-30" />
          <p class="text-sm">No transfers found.</p>
        </div>
      {:else}
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-border">
                <th
                  class="text-left py-3 px-4 font-medium text-muted-foreground"
                  >Transfer #</th
                >
                <th
                  class="text-left py-3 px-4 font-medium text-muted-foreground"
                  >From</th
                >
                <th
                  class="text-left py-3 px-4 font-medium text-muted-foreground"
                  >To</th
                >
                <th
                  class="text-left py-3 px-4 font-medium text-muted-foreground"
                  >Status</th
                >
                <th
                  class="text-left py-3 px-4 font-medium text-muted-foreground"
                  >Created</th
                >
                <th
                  class="text-left py-3 px-4 font-medium text-muted-foreground"
                  >Actions</th
                >
              </tr>
            </thead>
            <tbody>
              {#each filteredTransfers as tr (tr.id)}
                <tr
                  class="border-b border-border hover:bg-muted/50 transition-colors"
                >
                  <td class="py-3 px-4 font-mono font-medium"
                    >{tr.transfer_number}</td
                  >
                  <td class="py-3 px-4">{tr.from_location_name}</td>
                  <td class="py-3 px-4">{tr.to_location_name}</td>
                  <td class="py-3 px-4">
                    <span
                      class="px-2 py-1 rounded-full text-xs font-medium border {statusColors[
                        tr.status
                      ] || ''}"
                    >
                      {tr.status}
                    </span>
                  </td>
                  <td class="py-3 px-4 text-muted-foreground">
                    {new Date(tr.created).toLocaleDateString("en-GB")}
                  </td>
                  <td class="py-3 px-4">
                    {#if tr.status === "pending"}
                      <div class="flex gap-2">
                        <button
                          onclick={() => handleComplete(tr.id)}
                          class="flex items-center gap-1 px-3 py-1.5 text-xs bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors"
                        >
                          <CheckCircle class="w-3.5 h-3.5" /> Complete
                        </button>
                        <button
                          onclick={() => handleCancel(tr.id)}
                          class="flex items-center gap-1 px-3 py-1.5 text-xs border border-border rounded-lg hover:bg-muted transition-colors text-muted-foreground"
                        >
                          <XCircle class="w-3.5 h-3.5" /> Cancel
                        </button>
                      </div>
                    {:else}
                      <span class="text-muted-foreground text-xs">—</span>
                    {/if}
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    </Card>
  </FluidLayout>
</div>
