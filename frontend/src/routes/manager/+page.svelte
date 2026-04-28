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
    DollarSign,
    AlertTriangle,
    ShoppingBag,
    ArrowRight,
    Users,
  } from "lucide-svelte";
  import { customFetch, pb } from "$lib/pb";
  import { goto } from "$app/navigation";
  import { onMount } from "svelte";
  import {
    Chart,
    Title,
    Tooltip,
    Legend,
    LineElement,
    LinearScale,
    PointElement,
    CategoryScale,
    BarElement,
  } from "chart.js";
  import { Line, Bar } from "svelte-chartjs";

  Chart.register(
    Title,
    Tooltip,
    Legend,
    LineElement,
    LinearScale,
    PointElement,
    CategoryScale,
    BarElement,
  );

  const menuItems = [
    { label: "Dashboard", icon: LayoutDashboard, path: "/manager" },
    { label: "Sales Analysis", icon: TrendingUp, path: "/manager/sales" },
    { label: "Stock Analysis", icon: Package, path: "/manager/stock" },
    { label: "Reports", icon: FileText, path: "/manager/reports" },
    { label: "Users", icon: Users, path: "/manager/users" },
  ];

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

  let stats = $state<DashboardStats | null>(null);
  let dailyData = $state<Array<{ date: string; sales: number }>>([]);
  let lowStock = $state<
    Array<{ id: string; name: string; category: string; currentStock: number }>
  >([]);
  let loading = $state(true);

  onMount(() => {
    async function loadData() {
      try {
        const [dashStats, billRecords, stockRecords] = await Promise.all([
          customFetch("/stats/dashboard"),
          pb.collection("bills").getList(1, 200, {
            filter: `payment_status = 'paid'`,
            sort: "-created",
          }),
          pb
            .collection("stock")
            .getFullList({ expand: "product,product.category" }),
        ]);

        stats = dashStats;

        const dayMap: Record<string, number> = {};
        const today = new Date();
        for (let i = 6; i >= 0; i--) {
          const d = new Date(today);
          d.setDate(d.getDate() - i);
          const key = d.toLocaleDateString("en-GB", {
            day: "2-digit",
            month: "short",
          });
          dayMap[key] = 0;
        }
        for (const bill of billRecords.items as any[]) {
          const key = new Date(bill.created).toLocaleDateString("en-GB", {
            day: "2-digit",
            month: "short",
          });
          if (key in dayMap) dayMap[key] += bill.grand_total || 0;
        }
        dailyData = Object.entries(dayMap).map(([date, sales]) => ({
          date,
          sales,
        }));

        const low = (stockRecords as any[])
          .filter(
            (s) =>
              s.low_stock_threshold > 0 && s.quantity <= s.low_stock_threshold,
          )
          .map((s) => ({
            id: s.product,
            name: s.expand?.product?.name || "Unknown",
            category: s.expand?.product?.expand?.category?.name || "",
            currentStock: s.quantity,
          }));
        lowStock = low;
      } catch (e) {
        console.error("Dashboard load failed", e);
      } finally {
        loading = false;
      }
    }
    loadData();
  });

  let topProductsChart = $derived(
    (stats?.top_products || []).slice(0, 5).map((p) => ({
      name:
        p.product_name.length > 20
          ? p.product_name.substring(0, 20) + "…"
          : p.product_name,
      revenue: Math.round(p.total_rev),
    })),
  );

  let chartDataLine = $derived({
    labels: dailyData.map((d) => d.date),
    datasets: [
      {
        label: "Sales",
        data: dailyData.map((d) => d.sales),
        borderColor: "#8b2635",
        backgroundColor: "rgba(139, 38, 53, 0.1)",
        borderWidth: 2,
        tension: 0.3,
      },
    ],
  });

  let chartDataBar = $derived({
    labels: topProductsChart.map((p) => p.name),
    datasets: [
      {
        label: "Revenue",
        data: topProductsChart.map((p) => p.revenue),
        backgroundColor: "#8b2635",
      },
    ],
  });
</script>

<svelte:head>
  <title>Manager Dashboard - My Garments</title>
</svelte:head>

<div class="flex min-h-screen bg-background">
  <ImprovedSidebar {menuItems} userRole="Manager" />

  <FluidLayout>
    {#if loading}
      <LoadingSpinner />
    {:else}
      <div class="mb-6 md:mb-8">
        <h1 class="text-2xl md:text-3xl lg:text-4xl">Manager Dashboard</h1>
        <p class="text-muted-foreground text-sm md:text-base">
          Business insights and analytics
        </p>
      </div>

      <!-- Summary Cards -->
      <div
        class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 md:gap-6 mb-6 md:mb-8"
      >
        <div
          onclick={() => goto("/manager/sales")}
          class="cursor-pointer"
          aria-hidden="true"
        >
          <StatCard
            title="Today's Revenue"
            value={`₹${(stats?.today_revenue || 0).toLocaleString()}`}
            change="Paid bills today"
            icon={DollarSign}
            trend="up"
            delay={0}
          />
        </div>
        <div
          onclick={() => goto("/manager/sales")}
          class="cursor-pointer"
          aria-hidden="true"
        >
          <StatCard
            title="Week Revenue"
            value={`₹${(stats?.week_revenue || 0).toLocaleString()}`}
            change="Last 7 days"
            icon={TrendingUp}
            trend="up"
            delay={0.1}
          />
        </div>
        <div
          onclick={() => goto("/manager/sales")}
          class="cursor-pointer"
          aria-hidden="true"
        >
          <StatCard
            title="Month Revenue"
            value={`₹${(stats?.month_revenue || 0).toLocaleString()}`}
            change="This month"
            icon={ShoppingBag}
            trend="neutral"
            delay={0.2}
          />
        </div>
        <div
          onclick={() => goto("/manager/stock")}
          class="cursor-pointer"
          aria-hidden="true"
        >
          <StatCard
            title="Low Stock Alerts"
            value={lowStock.length}
            change="Items need reorder"
            icon={AlertTriangle}
            trend="down"
            delay={0.3}
          />
        </div>
      </div>

      <!-- Charts -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 md:gap-6 mb-6 md:mb-8">
        <Card>
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg md:text-xl">Daily Sales (Last 7 Days)</h3>
            <button
              onclick={() => goto("/manager/sales")}
              class="text-primary hover:underline flex items-center gap-1 text-sm"
            >
              View Details <ArrowRight class="w-4 h-4" />
            </button>
          </div>
          <div style="position: relative; height: 250px; width: 100%;">
            <Line
              data={chartDataLine}
              options={{
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
              }}
            />
          </div>
        </Card>

        <Card>
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg md:text-xl">Top Products (This Month)</h3>
            <button
              onclick={() => goto("/manager/sales")}
              class="text-primary hover:underline flex items-center gap-1 text-sm"
            >
              View Details <ArrowRight class="w-4 h-4" />
            </button>
          </div>
          <div style="position: relative; height: 250px; width: 100%;">
            <Bar
              data={chartDataBar}
              options={{
                indexAxis: "y",
                responsive: true,
                maintainAspectRatio: false,
                plugins: { legend: { display: false } },
              }}
            />
          </div>
        </Card>
      </div>

      <!-- Low Stock Alert -->
      {#if lowStock.length > 0}
        <Card>
          <div class="flex items-center justify-between mb-4">
            <h3 class="text-lg md:text-xl">Low Stock Alerts</h3>
            <button
              onclick={() => goto("/manager/stock")}
              class="text-primary hover:underline flex items-center gap-1 text-sm"
            >
              View All <ArrowRight class="w-4 h-4" />
            </button>
          </div>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {#each lowStock.slice(0, 3) as product (product.id)}
              <div
                class="p-4 bg-red-50 border border-red-200 rounded-lg transition-transform hover:scale-[1.02]"
              >
                <div class="flex justify-between items-start mb-2">
                  <div class="flex-1">
                    <p class="font-medium text-sm">{product.name}</p>
                    <p class="text-xs text-muted-foreground">
                      {product.category}
                    </p>
                  </div>
                  <AlertTriangle class="w-5 h-5 text-destructive" />
                </div>
                <span class="text-destructive font-medium text-sm"
                  >{product.currentStock} units left</span
                >
              </div>
            {/each}
          </div>
        </Card>
      {/if}
    {/if}
  </FluidLayout>
</div>
