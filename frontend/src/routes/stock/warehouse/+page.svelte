<script lang="ts">
  import ImprovedSidebar from "$lib/components/ImprovedSidebar.svelte";
  import FluidLayout from "$lib/components/FluidLayout.svelte";
  import Card from "$lib/components/Card.svelte";
  import StatCard from "$lib/components/StatCard.svelte";
  import Button from "$lib/components/Button.svelte";
  import DataTable from "$lib/components/DataTable.svelte";
  import PageHeader from "$lib/components/PageHeader.svelte";
  import LoadingSpinner from "$lib/components/LoadingSpinner.svelte";
  import {
    Package,
    ShoppingBag,
    Plus,
    Warehouse,
    AlertTriangle,
    DollarSign,
    X,
    Store,
    ArrowLeftRight,
    AlertCircle,
    Search,
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
  ];

  interface WarehouseStock {
    stockId: string;
    productId: string;
    name: string;
    sku: string;
    barcode: string;
    category: string;
    sellingPrice: number;
    quantity: number;
    lowStockThreshold: number;
  }

  let warehouseId = $state("");
  let warehouseName = $state("Warehouse");
  let stock = $state<WarehouseStock[]>([]);
  let products = $state<
    { id: string; name: string; sku: string; barcode: string }[]
  >([]);
  let loading = $state(true);
  let errorMsg = $state("");
  let showAddForm = $state(false);
  let saving = $state(false);
  let searchQuery = $state("");

  let formData = $state({
    productId: "",
    quantity: "",
    type: "purchase",
    note: "",
  });

  async function loadData() {
    try {
      loading = true;
      const locations = await pb.collection("locations").getFullList({
        filter: "type = 'warehouse' && is_active = true",
      });
      if (locations.length === 0) {
        errorMsg = "No warehouse location found. Create one first.";
        return;
      }
      const wh = locations[0] as any;
      warehouseId = wh.id;
      warehouseName = wh.name;

      const [stockRecords, productRecords] = await Promise.all([
        pb.collection("stock").getFullList({
          filter: `location = "${warehouseId}"`,
          expand: "product,product.category",
        }),
        pb.collection("products").getFullList({ sort: "name" }),
      ]);

      products = productRecords.map((p: any) => ({
        id: p.id,
        name: p.name,
        sku: p.sku || "",
        barcode: p.barcode || "",
      }));

      stock = stockRecords.map((s: any) => ({
        stockId: s.id,
        productId: s.product,
        name: s.expand?.product?.name || "Unknown",
        sku: s.expand?.product?.sku || "",
        barcode: s.expand?.product?.barcode || "",
        category: s.expand?.product?.expand?.category?.name || "",
        sellingPrice: s.expand?.product?.selling_price || 0,
        quantity: s.quantity as number,
        lowStockThreshold: s.low_stock_threshold as number,
      }));
    } catch (e: any) {
      errorMsg = e.message || "Failed to load warehouse data";
    } finally {
      loading = false;
    }
  }

  onMount(() => {
    loadData();
  });

  function resetForm() {
    formData = { productId: "", quantity: "", type: "purchase", note: "" };
    showAddForm = false;
    errorMsg = "";
  }

  async function handleSubmit(e: SubmitEvent) {
    e.preventDefault();
    saving = true;
    errorMsg = "";
    try {
      await customFetch("/stock/adjust", {
        method: "POST",
        body: JSON.stringify({
          product_id: formData.productId,
          location_id: warehouseId,
          quantity: Number(formData.quantity),
          type: formData.type,
          note: formData.note || `${formData.type} entry`,
        }),
      });
      await loadData();
      resetForm();
    } catch (e: any) {
      errorMsg = e.message || "Failed to adjust stock";
    } finally {
      saving = false;
    }
  }

  let totalValue = $derived(
    stock.reduce((s, r) => s + r.sellingPrice * r.quantity, 0),
  );
  let lowStockCount = $derived(
    stock.filter(
      (r) => r.lowStockThreshold > 0 && r.quantity <= r.lowStockThreshold,
    ).length,
  );
  let filteredStock = $derived.by(() => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return stock;
    return stock.filter(
      (r) =>
        r.name.toLowerCase().includes(q) ||
        r.sku.toLowerCase().includes(q) ||
        r.barcode.toLowerCase().includes(q),
    );
  });

  const columns: any[] = [
    { header: "Product", accessor: "name" },
    { header: "Category", accessor: "category" },
    { header: "SKU", accessor: "sku" },
    { header: "Stock", accessor: "quantity" },
    { header: "Price", accessor: "sellingPrice" },
  ];
</script>

<svelte:head>
  <title>Warehouse — My Garments</title>
</svelte:head>

<div class="flex min-h-screen bg-background">
  <ImprovedSidebar {menuItems} userRole="Stock Manager" />

  {#snippet addBtn()}
    <Button
      icon={showAddForm ? X : Plus}
      onclick={() => {
        if (showAddForm) {
          resetForm();
        } else {
          showAddForm = true;
        }
      }}
    >
      {showAddForm ? "Cancel" : "Add Stock"}
    </Button>
  {/snippet}

  <FluidLayout>
    <PageHeader
      title={warehouseName}
      subtitle="Warehouse stock levels and entry"
      icon={Warehouse}
      action={addBtn}
    />

    {#if errorMsg}
      <div
        class="mb-4 flex items-center gap-2 p-3 bg-destructive/10 border border-destructive/30 rounded-lg text-destructive text-sm"
      >
        <AlertCircle class="w-4 h-4" />
        {errorMsg}
      </div>
    {/if}

    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 md:gap-6 mb-6">
      <StatCard
        title="Products in Warehouse"
        value={stock.length}
        change="Distinct products"
        icon={Package}
        trend="neutral"
        delay={0}
      />
      <StatCard
        title="Stock Value"
        value={`₹${(totalValue / 1000).toFixed(0)}K`}
        change="Total value"
        icon={DollarSign}
        trend="up"
        delay={0.1}
      />
      <StatCard
        title="Low Stock Items"
        value={lowStockCount}
        change="Need reorder"
        icon={AlertTriangle}
        trend="down"
        delay={0.2}
      />
    </div>

    {#if showAddForm}
      <div transition:slide={{ duration: 300 }}>
        <Card class="mb-6">
          <h3 class="mb-4 text-lg">Add Warehouse Stock</h3>
          <form onsubmit={handleSubmit} class="space-y-4">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label
                  class="block mb-2 text-sm text-muted-foreground"
                  for="whProduct"
                >
                  Product <span class="text-destructive">*</span>
                </label>
                <select
                  id="whProduct"
                  bind:value={formData.productId}
                  class="w-full px-4 py-3 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all"
                  required
                >
                  <option value="">Choose a product</option>
                  {#each products as p}
                    <option value={p.id}>{p.name} ({p.barcode || p.sku})</option
                    >
                  {/each}
                </select>
              </div>
              <div>
                <label
                  class="block mb-2 text-sm text-muted-foreground"
                  for="whType"
                  >Type <span class="text-destructive">*</span></label
                >
                <select
                  id="whType"
                  bind:value={formData.type}
                  class="w-full px-4 py-3 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all"
                  required
                >
                  <option value="purchase">Purchase</option>
                  <option value="return">Return</option>
                  <option value="adjustment">Adjustment</option>
                </select>
              </div>
              <div>
                <label
                  class="block mb-2 text-sm text-muted-foreground"
                  for="whQty"
                >
                  Quantity <span class="text-destructive">*</span>
                </label>
                <input
                  id="whQty"
                  type="number"
                  bind:value={formData.quantity}
                  class="w-full px-4 py-3 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all"
                  placeholder="Positive to add, negative to remove"
                  required
                />
              </div>
              <div>
                <label
                  class="block mb-2 text-sm text-muted-foreground"
                  for="whNote">Note</label
                >
                <input
                  id="whNote"
                  type="text"
                  bind:value={formData.note}
                  class="w-full px-4 py-3 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all"
                  placeholder="Optional note"
                />
              </div>
            </div>
            <div class="flex gap-3">
              <Button type="submit" disabled={saving}
                >{saving ? "Saving…" : "Add Stock"}</Button
              >
              <Button type="button" variant="outline" onclick={resetForm}
                >Cancel</Button
              >
            </div>
          </form>
        </Card>
      </div>
    {/if}

    <Card>
      <div
        class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-4"
      >
        <h3 class="text-lg">Current Stock ({filteredStock.length})</h3>
        <div class="relative w-full sm:w-64">
          <Search
            class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground pointer-events-none"
          />
          <input
            type="text"
            bind:value={searchQuery}
            placeholder="Search products…"
            class="w-full pl-9 pr-4 py-2 text-sm border border-border rounded-full bg-muted/40 outline-none focus:ring-2 focus:ring-ring transition-all"
          />
        </div>
      </div>

      {#if loading}
        <LoadingSpinner />
      {:else if filteredStock.length === 0}
        <div class="text-center py-12 text-muted-foreground">
          <Package class="w-10 h-10 mx-auto mb-3 opacity-30" />
          <p class="text-sm">
            {searchQuery
              ? `No products match "${searchQuery}"`
              : "No stock in warehouse yet."}
          </p>
        </div>
      {:else}
        {#snippet cell(row: any, column: any)}
          {#if column.header === "Category"}
            <span class="px-2 py-1 bg-muted rounded text-sm"
              >{row.category}</span
            >
          {:else if column.header === "SKU"}
            <span class="font-mono text-sm">{row.sku}</span>
          {:else if column.header === "Stock"}
            <div class="flex items-center gap-2">
              <span
                class="font-medium {row.quantity === 0
                  ? 'text-destructive'
                  : row.lowStockThreshold > 0 &&
                      row.quantity <= row.lowStockThreshold
                    ? 'text-yellow-600'
                    : 'text-green-600'}"
              >
                {row.quantity}
              </span>
              {#if row.lowStockThreshold > 0 && row.quantity <= row.lowStockThreshold}
                <AlertTriangle class="w-4 h-4 text-yellow-500" />
              {/if}
            </div>
          {:else if column.header === "Price"}
            <span>₹{row.sellingPrice.toLocaleString()}</span>
          {:else}
            {row[column.accessor]}
          {/if}
        {/snippet}
        <DataTable data={filteredStock} {columns} {cell} />
      {/if}
    </Card>
  </FluidLayout>
</div>
