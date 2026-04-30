<script lang="ts">
  import ImprovedSidebar from "$lib/components/ImprovedSidebar.svelte";
  import FluidLayout from "$lib/components/FluidLayout.svelte";
  import Card from "$lib/components/Card.svelte";
  import DataTable from "$lib/components/DataTable.svelte";
  import PageHeader from "$lib/components/PageHeader.svelte";
  import LoadingSpinner from "$lib/components/LoadingSpinner.svelte";
  import {
    Package,
    ShoppingBag,
    Warehouse,
    Store,
    ArrowLeftRight,
    AlertTriangle,
    AlertCircle,
    TrendingUp,
  } from "lucide-svelte";
  import { pb, customFetch } from "$lib/pb";
  import { onMount } from "svelte";

  const menuItems = [
    { label: "Product Management", icon: ShoppingBag, path: "/stock/products" },
    { label: "Stock Management", icon: Package, path: "/stock/inventory" },
    { label: "Warehouse", icon: Warehouse, path: "/stock/warehouse" },
    { label: "Shop Stock", icon: Store, path: "/stock/shops" },
    { label: "Transfers", icon: ArrowLeftRight, path: "/stock/transfers" },
  ];

  interface Shop {
    id: string;
    name: string;
  }

  interface ShopStockRow {
    productId: string;
    name: string;
    sku: string;
    barcode: string;
    category: string;
    sellingPrice: number;
    quantity: number;
    lowStockThreshold: number;
  }

  interface LowStockAlert {
    product_id: string;
    product_name: string;
    quantity: number;
    low_stock_threshold: number;
  }

  let shops = $state<Shop[]>([]);
  let selectedShopId = $state("");
  let shopStock = $state<ShopStockRow[]>([]);
  let lowStockAlerts = $state<LowStockAlert[]>([]);
  let loading = $state(true);
  let loadingStock = $state(false);
  let errorMsg = $state("");

  onMount(async () => {
    try {
      const records = await pb.collection("locations").getFullList({
        filter: "type = 'shop' && is_active = true",
        sort: "name",
      });
      shops = records.map((r: any) => ({ id: r.id, name: r.name }));
      if (shops.length > 0) {
        selectedShopId = shops[0].id;
        await loadShopStock(selectedShopId);
      }
    } catch (e: any) {
      errorMsg = e.message || "Failed to load shops";
    } finally {
      loading = false;
    }
  });

  async function loadShopStock(shopId: string) {
    loadingStock = true;
    errorMsg = "";
    try {
      const [stockRecords, alertsData] = await Promise.all([
        pb.collection("stock").getFullList({
          filter: `location = "${shopId}"`,
          expand: "product,product.category",
        }),
        customFetch(`/stock/alerts?location_id=${shopId}`),
      ]);

      shopStock = stockRecords.map((s: any) => ({
        productId: s.product,
        name: s.expand?.product?.name || "Unknown",
        sku: s.expand?.product?.sku || "",
        barcode: s.expand?.product?.barcode || "",
        category: s.expand?.product?.expand?.category?.name || "",
        sellingPrice: s.expand?.product?.selling_price || 0,
        quantity: s.quantity as number,
        lowStockThreshold: s.low_stock_threshold as number,
      }));

      lowStockAlerts = alertsData || [];
    } catch (e: any) {
      errorMsg = e.message || "Failed to load shop stock";
    } finally {
      loadingStock = false;
    }
  }

  async function handleShopChange(shopId: string) {
    selectedShopId = shopId;
    await loadShopStock(shopId);
  }

  const columns: any[] = [
    { header: "Product", accessor: "name" },
    { header: "Category", accessor: "category" },
    { header: "SKU", accessor: "sku" },
    { header: "Stock", accessor: "quantity" },
    { header: "Price", accessor: "sellingPrice" },
  ];
</script>

<svelte:head>
  <title>Shop Stock — My Garments</title>
</svelte:head>

<div class="flex min-h-screen bg-background">
  <ImprovedSidebar {menuItems} userRole="Stock Manager" />

  <FluidLayout>
    <PageHeader
      title="Shop Stock Levels"
      subtitle="View current stock at each shop"
      icon={Store}
    />

    {#if errorMsg}
      <div
        class="mb-4 flex items-center gap-2 p-3 bg-destructive/10 border border-destructive/30 rounded-lg text-destructive text-sm"
      >
        <AlertCircle class="w-4 h-4" />{errorMsg}
      </div>
    {/if}

    {#if loading}
      <LoadingSpinner />
    {:else if shops.length === 0}
      <Card>
        <div class="text-center py-12 text-muted-foreground">
          <Store class="w-10 h-10 mx-auto mb-3 opacity-30" />
          <p>No active shops found. Create a shop location first.</p>
        </div>
      </Card>
    {:else}
      <!-- Shop selector tabs -->
      <div class="flex gap-2 flex-wrap mb-6">
        {#each shops as shop}
          <button
            onclick={() => handleShopChange(shop.id)}
            class="px-4 py-2 rounded-full text-sm font-medium transition-colors {selectedShopId ===
            shop.id
              ? 'bg-primary text-primary-foreground'
              : 'bg-muted text-muted-foreground hover:bg-muted/80'}"
          >
            {shop.name}
          </button>
        {/each}
      </div>

      {#if lowStockAlerts.length > 0}
        <Card class="mb-6 border-yellow-200 bg-yellow-50">
          <div class="flex items-center gap-2 mb-3">
            <AlertTriangle class="w-5 h-5 text-yellow-600" />
            <h3 class="text-yellow-800 font-medium">
              Low Stock Alerts ({lowStockAlerts.length})
            </h3>
          </div>
          <div class="flex flex-wrap gap-2">
            {#each lowStockAlerts as alert}
              <span
                class="px-3 py-1 bg-yellow-100 text-yellow-800 rounded-full text-sm border border-yellow-200"
              >
                {alert.product_name} — {alert.quantity} left (threshold: {alert.low_stock_threshold})
              </span>
            {/each}
          </div>
        </Card>
      {/if}

      <Card>
        <h3 class="text-lg mb-4">
          {shops.find((s) => s.id === selectedShopId)?.name ?? "Shop"} — Stock ({shopStock.length}
          products)
        </h3>
        {#if loadingStock}
          <LoadingSpinner />
        {:else if shopStock.length === 0}
          <div class="text-center py-12 text-muted-foreground">
            <Package class="w-10 h-10 mx-auto mb-3 opacity-30" />
            <p class="text-sm">
              No stock at this shop. Transfer stock from the warehouse.
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
          <DataTable data={shopStock} {columns} {cell} />
        {/if}
      </Card>
    {/if}
  </FluidLayout>
</div>
