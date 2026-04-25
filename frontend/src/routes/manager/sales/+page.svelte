<script lang="ts">
  import ImprovedSidebar from '$lib/components/ImprovedSidebar.svelte';
  import FluidLayout from '$lib/components/FluidLayout.svelte';
  import Card from '$lib/components/Card.svelte';
  import StatCard from '$lib/components/StatCard.svelte';
  import PageHeader from '$lib/components/PageHeader.svelte';
  import DataTable from '$lib/components/DataTable.svelte';
  import LoadingSpinner from '$lib/components/LoadingSpinner.svelte';
  import { LayoutDashboard, TrendingUp, Package, FileText, DollarSign, ShoppingCart, CreditCard, Users } from 'lucide-svelte';
  import { customFetch, pb } from '$lib/pb';
  import { onMount } from 'svelte';
  import { Chart, Title, Tooltip, Legend, LineElement, LinearScale, PointElement, CategoryScale, BarElement, ArcElement } from 'chart.js';
  import { Line, Bar, Pie } from 'svelte-chartjs';

  Chart.register(Title, Tooltip, Legend, LineElement, LinearScale, PointElement, CategoryScale, BarElement, ArcElement);

  const menuItems = [
    { label: 'Dashboard', icon: LayoutDashboard, path: '/manager' },
    { label: 'Sales Analysis', icon: TrendingUp, path: '/manager/sales' },
    { label: 'Stock Analysis', icon: Package, path: '/manager/stock' },
    { label: 'Reports', icon: FileText, path: '/manager/reports' },
    { label: 'Users', icon: Users, path: '/manager/users' },
  ];

  const COLORS = ['#8b2635', '#d4af37', '#c9b88d'];

  interface BillRecord {
    id: string;
    grand_total: number;
    payment_method: string;
    payment_status: string;
    created: string;
  }

  let timeframe = $state<'daily' | 'weekly' | 'monthly'>('daily');
  let bills = $state<BillRecord[]>([]);
  let topProducts = $state<Array<{ product_name: string; total_qty: number; total_rev: number }>>([]);
  let paymentMethods = $state<Array<{ method: string; total: number; count: number }>>([]);
  let loading = $state(true);

  onMount(() => {
    async function loadData() {
      try {
        const [dashStats, billRecords] = await Promise.all([
          customFetch('/stats/dashboard'),
          pb.collection('bills').getFullList({
            filter: `payment_status = 'paid'`,
            sort: '-created',
          }),
        ]);
        bills = billRecords as unknown as BillRecord[];
        topProducts = dashStats.top_products || [];
        paymentMethods = dashStats.payment_methods || [];
      } catch (e) {
        console.error('Sales analysis load failed', e);
      } finally {
        loading = false;
      }
    }
    loadData();
  });

  // Derived aggregations
  let currentData = $derived.by(() => {
    const map: Record<string, number> = {};
    for (const bill of bills) {
      let key = '';
      const date = new Date(bill.created);
      if (timeframe === 'daily') {
        key = date.toLocaleDateString('en-GB', { day: '2-digit', month: 'short' });
      } else if (timeframe === 'weekly') {
        const startOfYear = new Date(date.getFullYear(), 0, 1);
        const week = Math.ceil(((date.getTime() - startOfYear.getTime()) / 86400000 + startOfYear.getDay() + 1) / 7);
        key = `Week ${week}`;
      } else {
        key = date.toLocaleDateString('en-GB', { month: 'short', year: '2-digit' });
      }
      map[key] = (map[key] || 0) + (bill.grand_total || 0);
    }
    const labelKey = timeframe === 'daily' ? 'date' : timeframe === 'weekly' ? 'week' : 'month';
    return Object.entries(map)
      .map(([label, sales]) => ({ [labelKey]: label, label, sales }))
      .slice(-20);
  });

  let revenueByHour = $derived.by(() => {
    const today = new Date().toDateString();
    const hourMap: Record<string, number> = {};
    for (const bill of bills) {
      if (new Date(bill.created).toDateString() === today) {
        const hour = new Date(bill.created).getHours();
        const label = `${hour % 12 || 12} ${hour < 12 ? 'AM' : 'PM'}`;
        hourMap[label] = (hourMap[label] || 0) + (bill.grand_total || 0);
      }
    }
    return Object.entries(hourMap).map(([hour, revenue]) => ({ hour, revenue }));
  });

  let totalSales = $derived(currentData.reduce((sum, d) => sum + d.sales, 0));
  let totalTransactions = $derived(bills.length);
  let avgTransaction = $derived(totalTransactions ? Math.round(totalSales / totalTransactions) : 0);

  // Charts data
  let trendChartData = $derived({
    labels: currentData.map(d => d.label),
    datasets: [{
      label: 'Sales',
      data: currentData.map(d => d.sales),
      borderColor: '#8b2635',
      backgroundColor: 'rgba(139, 38, 53, 0.1)',
      borderWidth: 3,
      tension: 0.3,
      pointRadius: 4,
    }]
  });

  let paymentChartData = $derived({
    labels: paymentMethods.map(p => p.method),
    datasets: [{
      data: paymentMethods.map(p => p.total),
      backgroundColor: COLORS,
      borderWidth: 0,
    }]
  });

  let revenueHourChartData = $derived({
    labels: revenueByHour.map(r => r.hour),
    datasets: [{
      label: 'Revenue',
      data: revenueByHour.map(r => r.revenue),
      backgroundColor: '#8b2635',
    }]
  });
</script>

<svelte:head>
  <title>Sales Analysis - My Garments</title>
</svelte:head>

<div class="flex min-h-screen bg-background">
  <ImprovedSidebar {menuItems} userRole="Manager" />

  <FluidLayout>
    {#if loading}
      <LoadingSpinner />
    {:else}
      <PageHeader title="Sales Analysis" subtitle="Detailed sales insights and trends" icon={TrendingUp} />

      <!-- Summary Cards -->
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 md:gap-6 mb-6 md:mb-8">
        <StatCard title="Total Sales" value={`₹${totalSales.toLocaleString()}`} change={`${timeframe} view`} icon={DollarSign} trend="up" delay={0} />
        <StatCard title="Total Transactions" value={totalTransactions} change="Paid bills" icon={ShoppingCart} trend="neutral" delay={0.1} />
        <StatCard title="Avg Transaction" value={`₹${avgTransaction.toLocaleString()}`} change="Per sale" icon={CreditCard} trend="neutral" delay={0.2} />
      </div>

      <!-- Timeframe Selector -->
      <div class="mb-6 flex flex-wrap gap-2">
        {#each ['daily', 'weekly', 'monthly'] as tf}
          <button
            onclick={() => timeframe = tf as any}
            class="px-4 py-2 rounded-lg transition-colors capitalize {timeframe === tf ? 'bg-primary text-primary-foreground' : 'bg-muted text-foreground hover:bg-muted/80'}"
          >
            {tf}
          </button>
        {/each}
      </div>

      <!-- Sales Trend Chart -->
      <Card class="mb-6 md:mb-8">
        <h3 class="mb-4 text-lg md:text-xl">Sales Trend</h3>
        {#if currentData.length === 0}
          <p class="text-center py-8 text-muted-foreground">No sales data yet</p>
        {:else}
          <div style="position: relative; height: 300px; width: 100%;">
            <Line data={trendChartData} options={{ responsive: true, maintainAspectRatio: false }} />
          </div>
        {/if}
      </Card>

      <!-- Two Column Layout -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 md:gap-6 mb-6 md:mb-8">
        <!-- Payment Methods -->
        <Card>
          <h3 class="mb-4 text-lg md:text-xl">Payment Method Breakdown</h3>
          {#if paymentMethods.length === 0}
            <p class="text-center py-8 text-muted-foreground">No payment data yet</p>
          {:else}
            <div style="position: relative; height: 220px; width: 100%; display: flex; justify-content: center;">
              <Pie data={paymentChartData} options={{ responsive: true, maintainAspectRatio: false, plugins: { legend: { display: false } } }} />
            </div>
            <div class="mt-4 space-y-2">
              {#each paymentMethods as pm, idx}
                <div class="flex items-center justify-between p-2 bg-muted rounded">
                  <div class="flex items-center gap-2">
                    <div class="w-3 h-3 rounded-full" style="background-color: {COLORS[idx % COLORS.length]}"></div>
                    <span class="text-sm capitalize">{pm.method}</span>
                  </div>
                  <div class="text-right">
                    <p class="text-sm font-medium">₹{pm.total.toLocaleString()}</p>
                    <p class="text-xs text-muted-foreground">{pm.count} txns</p>
                  </div>
                </div>
              {/each}
            </div>
          {/if}
        </Card>

        <!-- Revenue by Time of Day -->
        <Card>
          <h3 class="mb-4 text-lg md:text-xl">Today's Revenue by Hour</h3>
          {#if revenueByHour.length === 0}
            <p class="text-center py-8 text-muted-foreground">No sales today yet</p>
          {:else}
            <div style="position: relative; height: 280px; width: 100%;">
              <Bar data={revenueHourChartData} options={{ responsive: true, maintainAspectRatio: false }} />
            </div>
          {/if}
        </Card>
      </div>

      <!-- Top Selling Products -->
      <Card>
        <h3 class="mb-4 text-lg md:text-xl">Top Selling Products (This Month)</h3>
        {#if topProducts.length === 0}
          <p class="text-center py-8 text-muted-foreground">No sales data available</p>
        {:else}
          <div class="overflow-x-auto">
            {#snippet cell(row: any, column: any)}
              {#if column.header === 'Rank'}
                <span class="font-bold text-primary">#{row.rank}</span>
              {:else if column.header === 'Units Sold'}
                <span class="font-medium">{row.total_qty}</span>
              {:else if column.header === 'Revenue'}
                <span class="font-medium text-green-600">₹{row.total_rev.toLocaleString()}</span>
              {:else}
                {row[column.accessor]}
              {/if}
            {/snippet}

            <DataTable
              data={topProducts.map((p, i) => ({ ...p, rank: i + 1 }))}
              columns={[
                { header: 'Rank', accessor: 'rank' },
                { header: 'Product Name', accessor: 'product_name' },
                { header: 'Units Sold', accessor: 'total_qty' },
                { header: 'Revenue', accessor: 'total_rev' },
              ]}
              {cell}
            />
          </div>
        {/if}
      </Card>
    {/if}
  </FluidLayout>
</div>
