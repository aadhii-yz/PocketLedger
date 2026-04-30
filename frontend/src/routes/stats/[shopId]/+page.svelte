<script lang="ts">
  import ImprovedSidebar from "$lib/components/ImprovedSidebar.svelte";
  import FluidLayout from "$lib/components/FluidLayout.svelte";
  import Card from "$lib/components/Card.svelte";
  import StatCard from "$lib/components/StatCard.svelte";
  import LoadingSpinner from "$lib/components/LoadingSpinner.svelte";
  import {
    LayoutDashboard,
    TrendingUp,
    Package,
    FileText,
    Users,
    Store,
    DollarSign,
    ArrowLeft,
    AlertTriangle,
    AlertCircle,
    Warehouse,
    ArrowLeftRight,
    ShoppingBag,
    Receipt,
  } from "lucide-svelte";
  import { customFetch, pb } from "$lib/pb";
  import { goto } from "$app/navigation";
  import { page } from "$app/stores";
  import { onMount } from "svelte";

  const role = (pb.authStore.record as any)?.role ?? "";

  const managerMenuItems = [
    { label: "Dashboard", icon: LayoutDashboard, path: "/manager" },
    { label: "Sales Analysis", icon: TrendingUp, path: "/manager/sales" },
    { label: "Stock Analysis", icon: Package, path: "/manager/stock" },
    { label: "Shop Overview", icon: Store, path: "/stats/overview" },
    { label: "Reports", icon: FileText, path: "/manager/reports" },
    { label: "Users", icon: Users, path: "/manager/users" },
  ];

  const stockMenuItems = [
    { label: "Product Management", icon: ShoppingBag, path: "/stock/products" },
    { label: "Stock Management", icon: Package, path: "/stock/inventory" },
    { label: "Warehouse", icon: Warehouse, path: "/stock/warehouse" },
    { label: "Shop Stock", icon: Store, path: "/stock/shops" },
    { label: "Transfers", icon: ArrowLeftRight, path: "/stock/transfers" },
    { label: "Shop Stats", icon: TrendingUp, path: "/stats/overview" },
  ];

  const menuItems = role === "stock_entry" ? stockMenuItems : managerMenuItems;
  const sidebarRole = role === "stock_entry" ? "Stock Manager" : "Manager";

  interface DashboardStats {
    today_revenue: number;
    week_revenue: number;
    month_revenue: number;
    top_products: Array<{
      product_id: string;
      product_name: string;
      total_qty: number;
      total_rev: number;
    }>;
    payment_methods: Array<{ method: string; total: number; count: number }>;
  }

  interface LowStockAlert {
    product_id: string;
    product_name: string;
    quantity: number;
    low_stock_threshold: number;
  }

  let shopId = $derived($page.params.shopId ?? "");
  let shopName = $state("Shop");
  let stats = $state<DashboardStats | null>(null);
  let lowStock = $state<LowStockAlert[]>([]);
  let loading = $state(true);
  let errorMsg = $state("");

  onMount(async () => {
    try {
      const [shopRecord, dashStats, alerts] = await Promise.all([
        pb.collection("locations").getOne(shopId),
        customFetch(`/stats/dashboard?shop_id=${shopId}`),
        customFetch(`/stock/alerts?location_id=${shopId}`),
      ]);
      shopName = (shopRecord as any).name || "Shop";
      stats = dashStats;
      lowStock = alerts || [];
    } catch (e: any) {
      errorMsg = e.message || "Failed to load shop stats";
    } finally {
      loading = false;
    }
  });
</script>

<svelte:head>
  <title>{shopName} Stats — My Garments</title>
</svelte:head>

<div class="flex min-h-screen bg-background">
  <ImprovedSidebar {menuItems} userRole={sidebarRole} />

  <FluidLayout>
    <div class="mb-6">
      <button
        onclick={() => goto("/stats/overview")}
        class="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground transition-colors mb-2"
      >
        <ArrowLeft class="w-4 h-4" /> Back to Shop Overview
      </button>
      <div class="flex items-center gap-3">
        <Store class="w-8 h-8 text-primary" />
        <div>
          <h1 class="text-2xl md:text-3xl">{shopName}</h1>
          <p class="text-muted-foreground text-sm">
            Per-shop revenue and inventory stats
          </p>
        </div>
      </div>
    </div>

    {#if errorMsg}
      <div
        class="mb-4 flex items-center gap-2 p-3 bg-destructive/10 border border-destructive/30 rounded-lg text-destructive text-sm"
      >
        <AlertCircle class="w-4 h-4" />{errorMsg}
      </div>
    {/if}

    {#if loading}
      <LoadingSpinner />
    {:else}
      <!-- Revenue summary -->
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-8">
        <StatCard
          title="Today's Revenue"
          value={`₹${(stats?.today_revenue || 0).toLocaleString()}`}
          change="Paid bills today"
          icon={DollarSign}
          trend="up"
          delay={0}
        />
        <StatCard
          title="This Week"
          value={`₹${(stats?.week_revenue || 0).toLocaleString()}`}
          change="Last 7 days"
          icon={TrendingUp}
          trend="up"
          delay={0.1}
        />
        <StatCard
          title="This Month"
          value={`₹${(stats?.month_revenue || 0).toLocaleString()}`}
          change="Current month"
          icon={DollarSign}
          trend="up"
          delay={0.2}
        />
      </div>

      {#if lowStock.length > 0}
        <Card class="mb-6 border-yellow-200 bg-yellow-50">
          <div class="flex items-center gap-2 mb-3">
            <AlertTriangle class="w-5 h-5 text-yellow-600" />
            <h3 class="text-yellow-800 font-medium">
              Low Stock Alerts ({lowStock.length})
            </h3>
          </div>
          <div class="flex flex-wrap gap-2">
            {#each lowStock as alert}
              <span
                class="px-3 py-1 bg-yellow-100 text-yellow-800 rounded-full text-sm border border-yellow-200"
              >
                {alert.product_name} — {alert.quantity} left
              </span>
            {/each}
          </div>
        </Card>
      {/if}

      <!-- Top products -->
      {#if (stats?.top_products || []).length > 0}
        <Card class="mb-6">
          <h3 class="text-lg mb-4">Top Products This Month</h3>
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-border">
                  <th
                    class="text-left py-2 px-3 font-medium text-muted-foreground"
                    >Product</th
                  >
                  <th
                    class="text-right py-2 px-3 font-medium text-muted-foreground"
                    >Qty Sold</th
                  >
                  <th
                    class="text-right py-2 px-3 font-medium text-muted-foreground"
                    >Revenue</th
                  >
                </tr>
              </thead>
              <tbody>
                {#each stats?.top_products || [] as product}
                  <tr class="border-b border-border hover:bg-muted/50">
                    <td class="py-2 px-3">{product.product_name}</td>
                    <td class="py-2 px-3 text-right">{product.total_qty}</td>
                    <td class="py-2 px-3 text-right font-medium text-primary"
                      >₹{product.total_rev.toLocaleString()}</td
                    >
                  </tr>
                {/each}
              </tbody>
            </table>
          </div>
        </Card>
      {/if}

      <!-- Payment methods -->
      {#if (stats?.payment_methods || []).length > 0}
        <Card>
          <h3 class="text-lg mb-4">Payment Methods This Month</h3>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            {#each stats?.payment_methods || [] as pm}
              <div class="p-3 bg-muted rounded-lg text-center">
                <p class="text-xs text-muted-foreground uppercase mb-1">
                  {pm.method}
                </p>
                <p class="font-semibold text-primary">
                  ₹{pm.total.toLocaleString()}
                </p>
                <p class="text-xs text-muted-foreground">{pm.count} bills</p>
              </div>
            {/each}
          </div>
        </Card>
      {/if}
    {/if}
  </FluidLayout>
</div>
