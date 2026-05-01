<script lang="ts">
  import ImprovedSidebar from "$lib/components/ImprovedSidebar.svelte";
  import FluidLayout from "$lib/components/FluidLayout.svelte";
  import Card from "$lib/components/Card.svelte";
  import Button from "$lib/components/Button.svelte";
  import Input from "$lib/components/Input.svelte";
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
    ArrowRight,
    AlertCircle,
    Warehouse,
    ArrowLeftRight,
    ShoppingBag,
    Plus,
    X,
    Receipt,
  } from "lucide-svelte";
  import { customFetch, pb } from "$lib/pb";
  import { goto } from "$app/navigation";
  import { onMount } from "svelte";
  import { slide } from "svelte/transition";

  const role = (pb.authStore.record as any)?.role ?? "";
  const canManageShops = role === "admin" || role === "manager";

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

  interface ShopStats {
    id: string;
    name: string;
    today_revenue: number;
    month_revenue: number;
  }

  interface GlobalStats {
    today_revenue: number;
    week_revenue: number;
    month_revenue: number;
  }

  interface Bill {
    id: string;
    bill_number: string;
    shop_name: string;
    customer_name: string;
    grand_total: number;
    payment_method: string;
    payment_status: string;
    created: string;
  }

  let globalStats = $state<GlobalStats | null>(null);
  let shopStats = $state<ShopStats[]>([]);
  let loading = $state(true);
  let errorMsg = $state("");

  let bills = $state<Bill[]>([]);
  let billsPage = $state(1);
  let billsTotalPages = $state(1);
  let billsLoading = $state(false);
  let billsPerPage = $state(10);

  let showAddForm = $state(false);
  let saving = $state(false);
  let formError = $state("");
  let formData = $state({ name: "", address: "", phone: "" });

  async function loadBills(pageNum = 1) {
    billsLoading = true;
    try {
      const mapBill = (b: any) => ({
        id: b.id,
        bill_number: b.bill_number,
        shop_name: b.expand?.shop?.name || "—",
        customer_name: b.customer_name || "—",
        grand_total: b.grand_total,
        payment_method: b.payment_method,
        payment_status: b.payment_status,
        created: b.created,
      });
      if (billsPerPage === 0) {
        const result = await pb.collection("bills").getFullList({ sort: "-created", expand: "shop" });
        bills = result.map(mapBill);
        billsTotalPages = 1;
        billsPage = 1;
      } else {
        const result = await pb.collection("bills").getList(pageNum, billsPerPage, {
          sort: "-created",
          expand: "shop",
        });
        bills = result.items.map(mapBill);
        billsTotalPages = result.totalPages;
        billsPage = pageNum;
      }
    } catch (e: any) {
      console.error("Failed to load bills", e);
    } finally {
      billsLoading = false;
    }
  }

  const statusColors: Record<string, string> = {
    paid: "bg-green-100 text-green-800",
    pending: "bg-yellow-100 text-yellow-800",
    partial: "bg-blue-100 text-blue-800",
  };

  function formatDate(d: string) {
    return new Date(d).toLocaleString("en-GB", {
      day: "2-digit", month: "short", year: "numeric",
      hour: "2-digit", minute: "2-digit",
    });
  }

  function getPages(current: number, total: number): (number | string)[] {
    if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1);
    const pages: (number | string)[] = [1];
    if (current > 3) pages.push("...");
    for (let i = Math.max(2, current - 1); i <= Math.min(total - 1, current + 1); i++) {
      pages.push(i);
    }
    if (current < total - 2) pages.push("...");
    pages.push(total);
    return pages;
  }

  async function loadData() {
    try {
      const [aggregateStats, shopRecords] = await Promise.all([
        customFetch("/stats/dashboard"),
        pb.collection("locations").getFullList({
          filter: "type = 'shop' && is_active = true",
          sort: "name",
        }),
      ]);

      globalStats = {
        today_revenue: aggregateStats.today_revenue,
        week_revenue: aggregateStats.week_revenue,
        month_revenue: aggregateStats.month_revenue,
      };

      const perShop = await Promise.all(
        shopRecords.map(async (shop: any) => {
          try {
            const s = await customFetch(`/stats/dashboard?shop_id=${shop.id}`);
            return {
              id: shop.id,
              name: shop.name,
              today_revenue: s.today_revenue,
              month_revenue: s.month_revenue,
            };
          } catch {
            return {
              id: shop.id,
              name: shop.name,
              today_revenue: 0,
              month_revenue: 0,
            };
          }
        }),
      );
      shopStats = perShop;
    } catch (e: any) {
      errorMsg = e.message || "Failed to load stats";
    } finally {
      loading = false;
    }
  }

  onMount(async () => {
    await loadData();
    await loadBills();
  });

  async function handleAddShop(e: SubmitEvent) {
    e.preventDefault();
    saving = true;
    formError = "";
    try {
      await customFetch("/locations", {
        method: "POST",
        body: JSON.stringify({
          name: formData.name.trim(),
          type: "shop",
          address: formData.address.trim(),
          phone: formData.phone.trim(),
        }),
      });
      formData = { name: "", address: "", phone: "" };
      showAddForm = false;
      loading = true;
      await loadData();
    } catch (e: any) {
      formError = e.message || "Failed to create shop";
    } finally {
      saving = false;
    }
  }
</script>

<svelte:head>
  <title>Shop Overview — My Garments</title>
</svelte:head>

<div class="flex min-h-screen bg-background">
  <ImprovedSidebar {menuItems} userRole={sidebarRole} />

  <FluidLayout>
    <div class="flex items-start justify-between mb-6">
      <div>
        <h1 class="text-2xl md:text-3xl lg:text-4xl">Shop Overview</h1>
        <p class="text-muted-foreground text-sm md:text-base">
          All-shop aggregate stats and per-shop comparison
        </p>
      </div>
      {#if canManageShops}
        <Button
          variant={showAddForm ? "outline" : "primary"}
          icon={showAddForm ? X : Plus}
          onclick={() => {
            showAddForm = !showAddForm;
            formError = "";
            formData = { name: "", address: "", phone: "" };
          }}
        >
          {showAddForm ? "Cancel" : "Add Shop"}
        </Button>
      {/if}
    </div>

    {#if canManageShops && showAddForm}
      <div transition:slide={{ duration: 300 }} class="mb-6">
        <Card>
          <h3 class="text-base font-medium mb-4">New Shop</h3>
          {#if formError}
            <div
              class="mb-4 flex items-center gap-2 p-3 bg-destructive/10 border border-destructive/30 rounded-lg text-destructive text-sm"
            >
              <AlertCircle class="w-4 h-4" />{formError}
            </div>
          {/if}
          <form onsubmit={handleAddShop} class="space-y-2">
            <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
              <Input label="Shop Name" bind:value={formData.name} required />
              <Input label="Address" bind:value={formData.address} />
              <Input label="Phone" bind:value={formData.phone} />
            </div>
            <div class="flex justify-end pt-2">
              <Button type="submit" disabled={saving}>
                {saving ? "Creating…" : "Create Shop"}
              </Button>
            </div>
          </form>
        </Card>
      </div>
    {/if}

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

      <!-- Aggregate summary -->
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-8">
        <StatCard
          title="Today (All Shops)"
          value={`₹${(globalStats?.today_revenue || 0).toLocaleString()}`}
          change="Paid bills today"
          icon={DollarSign}
          trend="up"
          delay={0}
        />
        <StatCard
          title="This Week"
          value={`₹${(globalStats?.week_revenue || 0).toLocaleString()}`}
          change="Last 7 days"
          icon={TrendingUp}
          trend="up"
          delay={0.1}
        />
        <StatCard
          title="This Month"
          value={`₹${(globalStats?.month_revenue || 0).toLocaleString()}`}
          change="Current month"
          icon={DollarSign}
          trend="up"
          delay={0.2}
        />
      </div>

      <!-- Per-shop comparison -->
      <Card>
        <h3 class="text-lg mb-4">Per-Shop Breakdown</h3>
        {#if shopStats.length === 0}
          <div class="text-center py-8 text-muted-foreground">
            <Store class="w-10 h-10 mx-auto mb-3 opacity-30" />
            <p class="text-sm">No shops found.{canManageShops ? ' Use "Add Shop" to create one.' : ""}</p>
          </div>
        {:else}
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {#each shopStats as shop (shop.id)}
              <button
                onclick={() => goto(`/stats/${shop.id}`)}
                class="p-4 border border-border rounded-xl text-left hover:border-primary/50 hover:shadow-md transition-all group"
              >
                <div class="flex items-center justify-between mb-3">
                  <div class="flex items-center gap-2">
                    <Store class="w-5 h-5 text-primary" />
                    <span class="font-medium">{shop.name}</span>
                  </div>
                  <ArrowRight
                    class="w-4 h-4 text-muted-foreground group-hover:text-primary transition-colors"
                  />
                </div>
                <div class="space-y-1">
                  <div class="flex justify-between text-sm">
                    <span class="text-muted-foreground">Today</span>
                    <span class="font-medium text-primary"
                      >₹{shop.today_revenue.toLocaleString()}</span
                    >
                  </div>
                  <div class="flex justify-between text-sm">
                    <span class="text-muted-foreground">This Month</span>
                    <span class="font-medium"
                      >₹{shop.month_revenue.toLocaleString()}</span
                    >
                  </div>
                </div>
              </button>
            {/each}
          </div>
        {/if}
      </Card>
    {/if}

    <!-- All Bills -->
    <Card class="mt-6">
      <div class="flex items-center justify-between mb-4">
        <div class="flex items-center gap-2">
          <Receipt class="w-5 h-5 text-primary" />
          <h3 class="text-lg">All Bills</h3>
        </div>
        <div class="flex items-center gap-2 text-sm">
          <span class="text-muted-foreground">Rows:</span>
          <select
            value={billsPerPage}
            onchange={(e) => { billsPerPage = parseInt((e.target as HTMLSelectElement).value); loadBills(1); }}
            class="px-2 py-1 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring text-sm"
          >
            <option value={10}>10</option>
            <option value={20}>20</option>
            <option value={50}>50</option>
            <option value={100}>100</option>
            <option value={0}>All</option>
          </select>
        </div>
      </div>

      {#if billsLoading}
        <div class="text-center py-10 text-muted-foreground text-sm">Loading bills…</div>
      {:else if bills.length === 0}
        <div class="text-center py-10">
          <Receipt class="w-12 h-12 mx-auto mb-3 opacity-20" />
          <p class="text-muted-foreground text-sm">No bills found</p>
        </div>
      {:else}
        <div class="overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-border text-muted-foreground">
                <th class="text-left py-2 px-3 font-medium">Bill #</th>
                <th class="text-left py-2 px-3 font-medium">Shop</th>
                <th class="text-left py-2 px-3 font-medium">Customer</th>
                <th class="text-left py-2 px-3 font-medium">Date</th>
                <th class="text-right py-2 px-3 font-medium">Total</th>
                <th class="text-center py-2 px-3 font-medium">Payment</th>
                <th class="text-center py-2 px-3 font-medium">Status</th>
              </tr>
            </thead>
            <tbody>
              {#each bills as bill (bill.id)}
                <tr class="border-b border-border hover:bg-muted/40 transition-colors">
                  <td class="py-2 px-3 font-medium">{bill.bill_number}</td>
                  <td class="py-2 px-3 text-muted-foreground">{bill.shop_name}</td>
                  <td class="py-2 px-3 text-muted-foreground">{bill.customer_name}</td>
                  <td class="py-2 px-3 text-muted-foreground whitespace-nowrap">{formatDate(bill.created)}</td>
                  <td class="py-2 px-3 text-right font-semibold text-primary">₹{Math.round(bill.grand_total).toLocaleString()}</td>
                  <td class="py-2 px-3 text-center capitalize text-muted-foreground">{bill.payment_method}</td>
                  <td class="py-2 px-3 text-center">
                    <span class="px-2 py-0.5 rounded-full text-xs font-medium {statusColors[bill.payment_status] || 'bg-muted text-muted-foreground'}">
                      {bill.payment_status}
                    </span>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>

        {#if billsTotalPages > 1 && billsPerPage !== 0}
          <div class="flex items-center justify-center gap-1 mt-4 flex-wrap">
            <button
              onclick={() => loadBills(billsPage - 1)}
              disabled={billsPage <= 1}
              class="px-3 py-1.5 rounded-lg border border-border text-sm hover:bg-muted transition-colors disabled:opacity-40"
            >Previous</button>
            {#each getPages(billsPage, billsTotalPages) as p}
              {#if p === "..."}
                <span class="px-2 py-1.5 text-sm text-muted-foreground">…</span>
              {:else}
                <button
                  onclick={() => loadBills(p as number)}
                  class="px-3 py-1.5 rounded-lg border text-sm transition-colors {p === billsPage ? 'bg-primary text-primary-foreground border-primary' : 'border-border hover:bg-muted'}"
                >{p}</button>
              {/if}
            {/each}
            <button
              onclick={() => loadBills(billsPage + 1)}
              disabled={billsPage >= billsTotalPages}
              class="px-3 py-1.5 rounded-lg border border-border text-sm hover:bg-muted transition-colors disabled:opacity-40"
            >Next</button>
          </div>
        {/if}
      {/if}
    </Card>
  </FluidLayout>
</div>
