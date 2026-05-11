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
    Search,
  } from "lucide-svelte";
  import BarcodeScanner from "$lib/components/BarcodeScanner.svelte";
  import { pb, customFetch } from "$lib/pb";
  import { TransferFormSchema, type Location, firstError } from "$lib/schemas";
  import { onMount } from "svelte";
  import { slide } from "svelte/transition";
  import { isCompanionMode, companionMenuItem } from "$lib/companion";

  const baseMenuItems = [
    { label: "Product Management", icon: ShoppingBag, path: "/stock/products" },
    { label: "Stock Management", icon: Package, path: "/stock/inventory" },
    { label: "Warehouse", icon: Warehouse, path: "/stock/warehouse" },
    { label: "Shop Stock", icon: Store, path: "/stock/shops" },
    { label: "Transfers", icon: ArrowLeftRight, path: "/stock/transfers" },
  ];
  const menuItems = isCompanionMode() ? [...baseMenuItems, companionMenuItem] : baseMenuItems;

  interface TransferItem {
    product_id: string;
    productSearch: string;
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
    { product_id: "", productSearch: "", quantity: 1, note: "" },
  ]);
  let openItemDropdown = $state(-1);

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
    formItems = [...formItems, { product_id: "", productSearch: "", quantity: 1, note: "" }];
  }

  function removeItem(i: number) {
    formItems = formItems.filter((_, idx) => idx !== i);
    if (openItemDropdown === i) openItemDropdown = -1;
    else if (openItemDropdown > i) openItemDropdown--;
  }

  function selectProductForItem(i: number, p: ProductOption) {
    formItems[i].product_id = p.id;
    formItems[i].productSearch = p.name;
    openItemDropdown = -1;
  }

  function handleItemKeydown(i: number, e: KeyboardEvent) {
    if (e.key === "Escape") { openItemDropdown = -1; return; }
    if (e.key !== "Enter") return;
    e.preventDefault();
    const q = formItems[i].productSearch.trim();
    if (!q) return;
    const exact = productOptions.find((p) => p.barcode === q || p.sku === q);
    if (exact) { selectProductForItem(i, exact); return; }
    const filtered = productOptions.filter((p) => {
      const ql = q.toLowerCase();
      return (
        p.name.toLowerCase().includes(ql) ||
        p.sku.toLowerCase().includes(ql) ||
        p.barcode.toLowerCase().includes(ql)
      );
    });
    if (filtered.length === 1) selectProductForItem(i, filtered[0]);
  }

  function handleItemBarcodeScan(i: number, barcode: string) {
    const exact = productOptions.find((p) => p.barcode === barcode || p.sku === barcode);
    if (exact) {
      selectProductForItem(i, exact);
    } else {
      formItems[i].productSearch = barcode;
      openItemDropdown = i;
    }
  }

  async function handleCreateTransfer(e: SubmitEvent) {
    e.preventDefault();
    errorMsg = "";
    const parsed = TransferFormSchema.safeParse({
      from_location: formData.from_location,
      to_location: formData.to_location,
      notes: formData.notes || undefined,
      items: formItems.map((item) => ({
        product_id: item.product_id,
        quantity: item.quantity,
        note: item.note || undefined,
      })),
    });
    if (!parsed.success) {
      errorMsg = firstError(parsed.error);
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
      formItems = [{ product_id: "", productSearch: "", quantity: 1, note: "" }];
      openItemDropdown = -1;
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
                      <div class="flex gap-1.5 items-center">
                        <div class="relative flex-1">
                          {#if item.product_id}
                            <div class="flex items-center gap-1.5 px-3 py-2 text-sm bg-background border border-border rounded-lg">
                              <span class="flex-1 truncate font-medium">{item.productSearch}</span>
                              <button
                                type="button"
                                onclick={() => { formItems[i].product_id = ""; formItems[i].productSearch = ""; }}
                                class="text-muted-foreground hover:text-foreground transition-colors shrink-0"
                                aria-label="Clear product"
                              >
                                <X class="w-3.5 h-3.5" />
                              </button>
                            </div>
                          {:else}
                            <Search class="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-muted-foreground pointer-events-none" />
                            <input
                              type="text"
                              bind:value={item.productSearch}
                              onkeydown={(e) => handleItemKeydown(i, e)}
                              oninput={() => (openItemDropdown = i)}
                              onfocus={() => { if (item.productSearch.trim()) openItemDropdown = i; }}
                              onblur={() => setTimeout(() => { if (openItemDropdown === i) openItemDropdown = -1; }, 150)}
                              placeholder="Search product…"
                              class="w-full pl-8 pr-3 py-2 text-sm bg-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring"
                            />
                            {#if openItemDropdown === i}
                              {@const q = item.productSearch.trim().toLowerCase()}
                              {@const opts = q ? productOptions.filter((p) => p.name.toLowerCase().includes(q) || p.sku.toLowerCase().includes(q) || p.barcode.toLowerCase().includes(q)) : []}
                              {#if opts.length > 0}
                                <div class="absolute z-20 top-full left-0 right-0 mt-1 max-h-40 overflow-y-auto bg-background border border-border rounded-lg shadow-lg">
                                  {#each opts.slice(0, 15) as p (p.id)}
                                    <button
                                      type="button"
                                      onmousedown={() => selectProductForItem(i, p)}
                                      class="w-full text-left px-3 py-2 text-sm hover:bg-muted transition-colors border-b border-border last:border-0"
                                    >
                                      <span class="font-medium">{p.name}</span>
                                      <span class="text-xs text-muted-foreground ml-1">{p.sku}{p.sku && p.barcode ? " • " : ""}{p.barcode}</span>
                                    </button>
                                  {/each}
                                </div>
                              {/if}
                            {/if}
                          {/if}
                        </div>
                        {#if !item.product_id}
                          <BarcodeScanner
                            onScan={(barcode) => handleItemBarcodeScan(i, barcode)}
                            class="p-2 bg-muted border border-border rounded-lg hover:bg-primary/10 hover:border-primary transition-colors"
                          />
                        {/if}
                      </div>
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
