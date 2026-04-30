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
    TrendingUp,
    AlertTriangle,
    DollarSign,
    Search,
    X,
    AlertCircle,
  } from "lucide-svelte";
  import { pb, customFetch } from "$lib/pb";
  import { onMount } from "svelte";
  import { slide } from "svelte/transition";

  import { ArrowLeftRight, Store, Warehouse, Receipt } from "lucide-svelte";

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

  interface StockProduct {
    id: string;
    stockId: string;
    name: string;
    sku: string;
    barcode: string;
    category: string;
    locationId: string;
    locationName: string;
    sellingPrice: number;
    quantity: number;
    lowStockThreshold: number;
  }

  interface StockEntry {
    productId: string;
    productName: string;
    quantity: number;
    note: string;
    date: string;
  }

  // ── State ──────────────────────────────────────────────────────────────────
  let products = $state<StockProduct[]>([]);
  let loading = $state(true);
  let stockEntries = $state<StockEntry[]>([]);
  let showAddForm = $state(false);
  let searchQuery = $state("");
  let saving = $state(false);
  let errorMsg = $state("");

  let locations = $state<Location[]>([]);

  let formData = $state({
    productId: "",
    locationId: "",
    quantity: "",
    note: "",
    type: "purchase",
  });

  // ── Data Loading ───────────────────────────────────────────────────────────
  async function loadData() {
    try {
      loading = true;
      const [productRecords, stockRecords, locationRecords] =
        await Promise.all([
          pb
            .collection("products")
            .getFullList({ expand: "category", sort: "name" }),
          pb.collection("stock").getFullList({ expand: "product,location" }),
          pb.collection("locations").getFullList({ sort: "name" }),
        ]);

      locations = locationRecords.map((l: any) => ({
        id: l.id,
        name: l.name,
        type: l.type,
      }));

      const locationMap = new Map(locations.map((l) => [l.id, l.name]));

      // Build one row per (product, location) combination.
      products = stockRecords.map((s: any) => {
        const p = s.expand?.product;
        return {
          id: p?.id || s.product,
          stockId: s.id,
          name: p?.name || "Unknown",
          sku: p?.sku || "",
          barcode: p?.barcode || "",
          category: p?.expand?.category?.name || "",
          locationId: s.location,
          locationName: locationMap.get(s.location) || s.location,
          sellingPrice: p?.selling_price || 0,
          quantity: s.quantity as number,
          lowStockThreshold: s.low_stock_threshold as number,
        };
      });

      // Also include products with no stock record at any location.
      const stockedProductIds = new Set(products.map((p) => p.id));
      for (const p of productRecords) {
        if (!stockedProductIds.has(p.id)) {
          products.push({
            id: p.id,
            stockId: "",
            name: p.name,
            sku: p.sku || "",
            barcode: p.barcode || "",
            category: p.expand?.category?.name || "",
            locationId: "",
            locationName: "—",
            sellingPrice: p.selling_price || 0,
            quantity: 0,
            lowStockThreshold: 0,
          });
        }
      }

    } catch {
      errorMsg = "Failed to load stock data";
    } finally {
      loading = false;
    }
  }

  onMount(() => {
    loadData();
  });

  // ── Form Helpers ───────────────────────────────────────────────────────────
  function resetForm() {
    formData = {
      productId: "",
      locationId: "",
      quantity: "",
      note: "",
      type: "purchase",
    };
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
          location_id: formData.locationId,
          quantity: Number(formData.quantity),
          type: formData.type,
          note: formData.note || `${formData.type} entry`,
        }),
      });

      const product = products.find((p) => p.id === formData.productId);
      const newEntry: StockEntry = {
        productId: formData.productId,
        productName: product?.name || "",
        quantity: Number(formData.quantity),
        note: formData.note || `${formData.type} entry`,
        date: new Date().toISOString().split("T")[0],
      };

      stockEntries = [newEntry, ...stockEntries];
      products = products.map((p) =>
        p.id === formData.productId
          ? { ...p, quantity: p.quantity + Number(formData.quantity) }
          : p,
      );
      resetForm();
    } catch (e: any) {
      errorMsg = e.message || "Failed to adjust stock";
    } finally {
      saving = false;
    }
  }

  // ── Derived ────────────────────────────────────────────────────────────────
  let totalStockValue = $derived(
    products.reduce((sum, p) => sum + p.sellingPrice * p.quantity, 0),
  );

  let lowStockCount = $derived(
    products.filter(
      (p) => p.lowStockThreshold > 0 && p.quantity <= p.lowStockThreshold,
    ).length,
  );

  let filteredProducts = $derived.by(() => {
    const q = searchQuery.trim().toLowerCase();
    if (!q) return products;
    return products.filter(
      (p) =>
        p.name.toLowerCase().includes(q) ||
        p.category.toLowerCase().includes(q) ||
        p.barcode.toLowerCase().includes(q) ||
        p.sku.toLowerCase().includes(q),
    );
  });

  let selectedProduct = $derived(
    products.find((p) => p.id === formData.productId),
  );

  // ── Table columns ──────────────────────────────────────────────────────────
  const columns: any[] = [
    { header: "Product Name", accessor: "name" },
    { header: "Location", accessor: "locationName" },
    { header: "Category", accessor: "category" },
    { header: "Barcode/SKU", accessor: "barcode" },
    { header: "Stock", accessor: "quantity" },
    { header: "Price", accessor: "sellingPrice" },
  ];
</script>

<svelte:head>
  <title>Stock Management - My Garments</title>
</svelte:head>

<div class="flex min-h-screen bg-background">
  <ImprovedSidebar {menuItems} userRole="Stock Manager" />

  {#snippet addStockBtn()}
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
      title="Stock Management"
      subtitle="Manage inventory quantities"
      icon={Package}
      action={addStockBtn}
    />

    {#if errorMsg}
      <div
        class="mb-4 flex items-center gap-2 p-3 bg-destructive/10 border border-destructive/30 rounded-lg text-destructive text-sm"
      >
        <AlertCircle class="w-4 h-4" />
        {errorMsg}
      </div>
    {/if}

    <!-- Summary Cards -->
    <div
      class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 md:gap-6 mb-6 md:mb-8"
    >
      <StatCard
        title="Total Products"
        value={products.length}
        change="In catalog"
        icon={Package}
        trend="neutral"
        delay={0}
      />
      <StatCard
        title="Stock Value"
        value={`₹${(totalStockValue / 1000).toFixed(0)}K`}
        change="Total inventory"
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
      <StatCard
        title="Stock Entries"
        value={stockEntries.length}
        change="This session"
        icon={TrendingUp}
        trend="neutral"
        delay={0.3}
      />
    </div>

    <!-- Add Stock Form -->
    {#if showAddForm}
      <div transition:slide={{ duration: 300 }}>
        <Card class="mb-6 md:mb-8">
          <h3 class="mb-6 text-lg md:text-xl">Add Stock Entry</h3>
          <form onsubmit={handleSubmit} class="space-y-4">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <!-- Product Select -->
              <div class="relative w-full mb-6">
                <label
                  class="block mb-2 text-sm text-muted-foreground"
                  for="productSelect"
                >
                  Select Product <span class="text-destructive">*</span>
                </label>
                <select
                  id="productSelect"
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

              <!-- Location Select -->
              <div class="relative w-full mb-6">
                <label
                  class="block mb-2 text-sm text-muted-foreground"
                  for="locationSelect"
                >
                  Location <span class="text-destructive">*</span>
                </label>
                <select
                  id="locationSelect"
                  bind:value={formData.locationId}
                  class="w-full px-4 py-3 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all"
                  required
                >
                  <option value="">Choose a location</option>
                  {#each locations as loc}
                    <option value={loc.id}>{loc.name} ({loc.type})</option>
                  {/each}
                </select>
              </div>

              <!-- Type Select -->
              <div class="relative w-full mb-6">
                <label
                  class="block mb-2 text-sm text-muted-foreground"
                  for="typeSelect"
                >
                  Type <span class="text-destructive">*</span>
                </label>
                <select
                  id="typeSelect"
                  bind:value={formData.type}
                  class="w-full px-4 py-3 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all"
                  required
                >
                  <option value="purchase">Purchase</option>
                  <option value="return">Return</option>
                  <option value="adjustment">Adjustment</option>
                </select>
              </div>

              <!-- Quantity -->
              <div class="relative w-full mb-6">
                <label
                  class="block mb-2 text-sm text-muted-foreground"
                  for="qtyInput"
                >
                  Quantity <span class="text-destructive">*</span>
                </label>
                <input
                  id="qtyInput"
                  type="number"
                  bind:value={formData.quantity}
                  class="w-full px-4 py-3 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all"
                  placeholder="Positive to add, negative to remove"
                  required
                />
              </div>

              <!-- Note -->
              <div class="relative w-full mb-6">
                <label
                  class="block mb-2 text-sm text-muted-foreground"
                  for="noteInput">Note</label
                >
                <input
                  id="noteInput"
                  type="text"
                  bind:value={formData.note}
                  class="w-full px-4 py-3 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all"
                  placeholder="Optional note"
                />
              </div>
            </div>

            <!-- Stock Entry Summary Preview -->
            {#if selectedProduct && formData.quantity}
              <div transition:slide={{ duration: 200 }}>
                <Card class="bg-blue-50 border-blue-200">
                  <div class="flex items-center justify-between">
                    <div>
                      <p class="text-sm text-blue-700 mb-1">
                        Stock Entry Summary
                      </p>
                      <p class="font-medium">{selectedProduct.name}</p>
                      <p class="text-sm text-blue-600">
                        Current stock: {selectedProduct.quantity} units
                      </p>
                    </div>
                    <div class="text-right">
                      <p class="text-sm text-blue-700">After Adjustment</p>
                      <p class="text-2xl font-medium text-blue-900">
                        {selectedProduct.quantity + Number(formData.quantity)} units
                      </p>
                    </div>
                  </div>
                </Card>
              </div>
            {/if}

            <div class="flex gap-3">
              <Button type="submit" disabled={saving}
                >{saving ? "Saving…" : "Add Stock Entry"}</Button
              >
              <Button type="button" variant="outline" onclick={resetForm}
                >Cancel</Button
              >
            </div>
          </form>
        </Card>
      </div>
    {/if}

    <!-- Current Stock Levels Table -->
    <Card class="mb-6 md:mb-8">
      <div
        class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-5"
      >
        <h3 class="text-lg md:text-xl">
          Current Stock Levels
          <span class="ml-2 text-sm font-normal text-muted-foreground">
            ({filteredProducts.length}{searchQuery
              ? ` of ${products.length}`
              : ""})
          </span>
        </h3>

        <!-- Search -->
        <div class="relative w-full sm:w-72">
          <Search
            class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground pointer-events-none"
          />
          <input
            type="text"
            bind:value={searchQuery}
            placeholder="Search by product name…"
            class="w-full pl-9 pr-9 py-2 text-sm border border-border rounded-full bg-muted/40 outline-none focus:ring-2 focus:ring-ring transition-all"
          />
          {#if searchQuery}
            <button
              onclick={() => (searchQuery = "")}
              class="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground transition-colors"
            >
              <X class="w-3.5 h-3.5" />
            </button>
          {/if}
        </div>
      </div>

      {#if loading}
        <LoadingSpinner />
      {:else if filteredProducts.length === 0}
        <div class="text-center py-12 text-muted-foreground">
          <Package class="w-10 h-10 mx-auto mb-3 opacity-30" />
          <p class="text-sm">
            {searchQuery
              ? `No products match "${searchQuery}"`
              : "No products in stock yet."}
          </p>
        </div>
      {:else}
        <div class="overflow-x-auto">
          {#snippet cell(row: any, column: any)}
            {#if column.header === "Location"}
              <span class="px-2 py-1 bg-blue-50 text-blue-700 rounded text-sm"
                >{row.locationName}</span
              >
            {:else if column.header === "Category"}
              <span class="px-2 py-1 bg-muted rounded text-sm"
                >{row.category}</span
              >
            {:else if column.header === "Barcode/SKU"}
              <span class="font-mono text-sm">{row.barcode || row.sku}</span>
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

          <DataTable data={filteredProducts} {columns} {cell} />
        </div>
      {/if}
    </Card>
  </FluidLayout>
</div>
