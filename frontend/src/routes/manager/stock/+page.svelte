<script lang="ts">
  import ImprovedSidebar from "$lib/components/ImprovedSidebar.svelte";
  import FluidLayout from "$lib/components/FluidLayout.svelte";
  import Card from "$lib/components/Card.svelte";
  import StatCard from "$lib/components/StatCard.svelte";
  import PageHeader from "$lib/components/PageHeader.svelte";
  import DataTable from "$lib/components/DataTable.svelte";
  import LoadingSpinner from "$lib/components/LoadingSpinner.svelte";
  import {
    LayoutDashboard,
    TrendingUp,
    Package,
    FileText,
    AlertTriangle,
    Archive,
    CheckCircle,
    Users,
  } from "lucide-svelte";
  import { pb } from "$lib/pb";
  import { onMount } from "svelte";
  import {
    Chart,
    Title,
    Tooltip,
    Legend,
    CategoryScale,
    BarElement,
    ArcElement,
    LinearScale,
  } from "chart.js";
  import { Bar, Pie } from "svelte-chartjs";
  import { Store, Printer } from "lucide-svelte";

  Chart.register(
    Title,
    Tooltip,
    Legend,
    CategoryScale,
    BarElement,
    ArcElement,
    LinearScale,
  );

  const menuItems = [
    { label: "Dashboard", icon: LayoutDashboard, path: "/manager" },
    { label: "Sales Analysis", icon: TrendingUp, path: "/manager/sales" },
    { label: "Stock Analysis", icon: Package, path: "/manager/stock" },
    { label: "Shop Overview", icon: Store, path: "/stats/overview" },
    { label: "Reports", icon: FileText, path: "/manager/reports" },
    { label: "Users", icon: Users, path: "/manager/users" },
    { label: "Print Settings", icon: Printer, path: "/manager/print-settings" },
  ];

  const COLORS = ["#8b2635", "#d4af37", "#c9b88d", "#a0522d", "#cd853f"];

  interface StockLevel {
    category: string;
    total: number;
    low: number;
    healthy: number;
  }

  interface LowStockItem {
    id: string;
    name: string;
    category: string;
    currentStock: number;
    reorderLevel: number;
  }

  let stockLevels = $state<StockLevel[]>([]);
  let lowStockItems = $state<LowStockItem[]>([]);
  let totalStockValue = $state(0);
  let loading = $state(true);

  onMount(() => {
    async function loadData() {
      try {
        const [stockRecords, productRecords] = await Promise.all([
          pb
            .collection("stock")
            .getFullList({ expand: "product,product.category" }),
          pb.collection("products").getFullList({ expand: "category" }),
        ]);

        const priceMap = new Map(
          (productRecords as any[]).map((p) => [p.id, p.selling_price || 0]),
        );

        const catMap: Record<string, StockLevel> = {};
        const lowItems: LowStockItem[] = [];
        let stockValue = 0;

        for (const s of stockRecords as any[]) {
          const catName =
            s.expand?.product?.expand?.category?.name || "Uncategorized";
          const qty: number = s.quantity || 0;
          const threshold: number = s.low_stock_threshold || 0;
          const price = priceMap.get(s.product) || 0;
          stockValue += qty * price;

          if (!catMap[catName])
            catMap[catName] = {
              category: catName,
              total: 0,
              low: 0,
              healthy: 0,
            };
          catMap[catName].total += qty;

          if (threshold > 0 && qty <= threshold) {
            catMap[catName].low += qty;
            lowItems.push({
              id: s.product,
              name: s.expand?.product?.name || "Unknown",
              category: catName,
              currentStock: qty,
              reorderLevel: threshold,
            });
          } else {
            catMap[catName].healthy += qty;
          }
        }

        stockLevels = Object.values(catMap);
        lowStockItems = lowItems.sort(
          (a, b) => a.currentStock - b.currentStock,
        );
        totalStockValue = stockValue;
      } catch (e) {
        console.error("Stock analysis load failed", e);
      } finally {
        loading = false;
      }
    }
    loadData();
  });

  let totalStock = $derived(stockLevels.reduce((s, c) => s + c.total, 0));
  let totalLowStock = $derived(stockLevels.reduce((s, c) => s + c.low, 0));
  let totalHealthy = $derived(stockLevels.reduce((s, c) => s + c.healthy, 0));

  let pieChartData = $derived({
    labels: stockLevels.map((s) => s.category),
    datasets: [
      {
        data: stockLevels.map((s) => s.total),
        backgroundColor: COLORS,
        borderWidth: 0,
      },
    ],
  });

  let barChartData = $derived({
    labels: stockLevels.map((s) => s.category),
    datasets: [
      {
        label: "Healthy",
        data: stockLevels.map((s) => s.healthy),
        backgroundColor: "#10b981",
      },
      {
        label: "Low Stock",
        data: stockLevels.map((s) => s.low),
        backgroundColor: "#ef4444",
      },
    ],
  });
</script>

<svelte:head>
  <title>Stock Analysis - My Garments</title>
</svelte:head>

<div class="flex min-h-screen bg-background">
  <ImprovedSidebar {menuItems} userRole="Manager" />

  <FluidLayout>
    {#if loading}
      <LoadingSpinner />
    {:else}
      <PageHeader
        title="Stock Analysis"
        subtitle="Inventory levels and stock monitoring"
        icon={Package}
      />

      <div
        class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 md:gap-6 mb-6 md:mb-8"
      >
        <StatCard
          title="Total Items"
          value={totalStock}
          change="All categories"
          icon={Archive}
          trend="neutral"
          delay={0}
        />
        <StatCard
          title="Healthy Stock"
          value={totalHealthy}
          change={totalStock
            ? `${Math.round((totalHealthy / totalStock) * 100)}% of total`
            : "—"}
          icon={CheckCircle}
          trend="up"
          delay={0.1}
        />
        <StatCard
          title="Low Stock"
          value={totalLowStock}
          change="Need reorder"
          icon={AlertTriangle}
          trend="down"
          delay={0.2}
        />
        <StatCard
          title="Stock Value"
          value={`₹${(totalStockValue / 1000).toFixed(0)}K`}
          change="Total inventory value"
          icon={Package}
          trend="neutral"
          delay={0.3}
        />
      </div>

      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 md:gap-6 mb-6 md:mb-8">
        <Card>
          <h3 class="mb-4 text-lg md:text-xl">
            Stock Distribution by Category
          </h3>
          {#if stockLevels.length === 0}
            <p class="text-center py-8 text-muted-foreground">No stock data</p>
          {:else}
            <div
              style="position: relative; height: 280px; width: 100%; display: flex; justify-content: center;"
            >
              <Pie
                data={pieChartData}
                options={{ responsive: true, maintainAspectRatio: false }}
              />
            </div>
          {/if}
        </Card>

        <Card>
          <h3 class="mb-4 text-lg md:text-xl">Stock Health by Category</h3>
          {#if stockLevels.length === 0}
            <p class="text-center py-8 text-muted-foreground">No stock data</p>
          {:else}
            <div style="position: relative; height: 280px; width: 100%;">
              <Bar
                data={barChartData}
                options={{
                  responsive: true,
                  maintainAspectRatio: false,
                  scales: {
                    x: { stacked: true },
                    y: { stacked: true },
                  },
                }}
              />
            </div>
          {/if}
        </Card>
      </div>

      <Card class="mb-6 md:mb-8">
        <h3 class="mb-4 text-lg md:text-xl">Category Stock Overview</h3>
        {#if stockLevels.length === 0}
          <p class="text-center py-8 text-muted-foreground">No stock data</p>
        {:else}
          <div class="overflow-x-auto">
            {#snippet overviewCell(row: any, column: any)}
              {#if column.header === "Total Stock"}
                <span class="font-medium">{row.total} units</span>
              {:else if column.header === "Healthy"}
                <span class="text-green-600 font-medium"
                  >{row.healthy} units</span
                >
              {:else if column.header === "Low Stock"}
                <span
                  class={row.low > 0
                    ? "text-destructive font-medium"
                    : "text-muted-foreground"}>{row.low} units</span
                >
              {:else if column.header === "Health %"}
                {@const pct = row.total
                  ? Math.round((row.healthy / row.total) * 100)
                  : 100}
                <div class="flex items-center gap-2">
                  <div class="w-24 h-2 bg-muted rounded-full overflow-hidden">
                    <div
                      class="h-full {pct > 80
                        ? 'bg-green-600'
                        : pct > 50
                          ? 'bg-yellow-500'
                          : 'bg-red-600'}"
                      style="width: {pct}%"
                    ></div>
                  </div>
                  <span class="text-sm font-medium">{pct}%</span>
                </div>
              {:else}
                {row[column.accessor]}
              {/if}
            {/snippet}

            <DataTable
              data={stockLevels}
              columns={[
                { header: "Category", accessor: "category" },
                { header: "Total Stock", accessor: "total" },
                { header: "Healthy", accessor: "healthy" },
                { header: "Low Stock", accessor: "low" },
                { header: "Health %", accessor: () => "" },
              ]}
              cell={overviewCell}
            />
          </div>
        {/if}
      </Card>

      <Card>
        <div class="flex items-center gap-2 mb-4">
          <AlertTriangle class="w-5 h-5 text-destructive" />
          <h3 class="text-lg md:text-xl">Critical Low Stock Items</h3>
        </div>
        {#if lowStockItems.length === 0}
          <p class="text-center py-8 text-green-600 font-medium">
            ✓ All items are adequately stocked
          </p>
        {:else}
          <div class="overflow-x-auto">
            {#snippet lowCell(row: any, column: any)}
              {#if column.header === "Current Stock"}
                <span class="text-destructive font-medium"
                  >{row.currentStock} units</span
                >
              {:else if column.header === "Reorder Level"}
                <span>{row.reorderLevel} units</span>
              {:else if column.header === "Priority"}
                {@const ratio = row.currentStock / row.reorderLevel}
                {@const priority =
                  ratio <= 0.3 ? "Critical" : ratio <= 0.6 ? "High" : "Medium"}
                {@const color =
                  priority === "Critical"
                    ? "bg-red-100 text-red-700"
                    : priority === "High"
                      ? "bg-yellow-100 text-yellow-700"
                      : "bg-blue-100 text-blue-700"}
                <span class="px-2 py-1 rounded text-xs font-medium {color}"
                  >{priority}</span
                >
              {:else}
                {row[column.accessor]}
              {/if}
            {/snippet}

            <DataTable
              data={lowStockItems}
              columns={[
                { header: "Product Name", accessor: "name" },
                { header: "Category", accessor: "category" },
                { header: "Current Stock", accessor: "currentStock" },
                { header: "Reorder Level", accessor: "reorderLevel" },
                { header: "Priority", accessor: () => "" },
              ]}
              cell={lowCell}
            />
          </div>
        {/if}
      </Card>
    {/if}
  </FluidLayout>
</div>
