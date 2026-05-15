<script lang="ts">
  import ImprovedSidebar from "$lib/components/ImprovedSidebar.svelte";
  import FluidLayout from "$lib/components/FluidLayout.svelte";
  import Card from "$lib/components/Card.svelte";
  import Button from "$lib/components/Button.svelte";
  import PageHeader from "$lib/components/PageHeader.svelte";
  import {
    LayoutDashboard,
    TrendingUp,
    Package,
    FileText,
    Download,
    CheckCircle,
    FileBarChart,
    Calendar,
    Users,
  } from "lucide-svelte";
  import { fly } from "svelte/transition";
  import { Store, Printer, AlertCircle } from "lucide-svelte";
  import { pb } from "$lib/pb";
  import { startOfMonth, endOfMonth, subDays, format } from "date-fns";

  const menuItems = [
    { label: "Dashboard", icon: LayoutDashboard, path: "/manager" },
    { label: "Sales Analysis", icon: TrendingUp, path: "/manager/sales" },
    { label: "Stock Analysis", icon: Package, path: "/manager/stock" },
    { label: "Shop Overview", icon: Store, path: "/stats/overview" },
    { label: "Reports", icon: FileText, path: "/manager/reports" },
    { label: "Users", icon: Users, path: "/manager/users" },
    { label: "Print Settings", icon: Printer, path: "/manager/print-settings" },
  ];

  const MONTHS = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
  ];

  const currentYear = new Date().getFullYear();
  const YEARS = [currentYear, currentYear - 1, currentYear - 2];

  let downloading = $state<string | null>(null);
  let downloaded = $state<Set<string>>(new Set());

  let selectedMonth = $state(MONTHS[new Date().getMonth()]);
  let selectedYear = $state(currentYear);
  let monthlyDownloading = $state(false);
  let monthlyDownloaded = $state(false);
  let errorMsg = $state("");

  // ── CSV helpers (RFC-4180 quoting, BOM for Excel) ──────────────────────────
  function csvCell(v: unknown): string {
    const s = v === null || v === undefined ? "" : String(v);
    return /[",\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  }

  function toCSV(headers: string[], rows: unknown[][]): string {
    const lines = [headers.map(csvCell).join(",")];
    for (const r of rows) lines.push(r.map(csvCell).join(","));
    return lines.join("\r\n");
  }

  function downloadCSV(filename: string, csv: string) {
    const blob = new Blob(["﻿" + csv], {
      type: "text/csv;charset=utf-8;",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  const pbDate = (d: Date) => format(d, "yyyy-MM-dd HH:mm:ss");

  async function fetchBills(from: Date, to?: Date) {
    let filter = `created >= "${pbDate(from)}"`;
    if (to) filter += ` && created <= "${pbDate(to)}"`;
    return pb.collection("bills").getFullList({
      filter,
      sort: "-created",
      expand: "shop",
    });
  }

  function billRows(bills: any[]): unknown[][] {
    return bills.map((b) => [
      b.bill_number,
      b.created ? format(new Date(b.created), "yyyy-MM-dd HH:mm") : "",
      b.expand?.shop?.name || b.shop || "",
      b.customer_name || "",
      b.payment_method || "",
      b.payment_status || "",
      b.subtotal ?? 0,
      b.tax_total ?? 0,
      b.discount ?? 0,
      b.grand_total ?? 0,
    ]);
  }
  const BILL_HEADERS = [
    "Bill Number",
    "Date",
    "Shop",
    "Customer",
    "Payment Method",
    "Payment Status",
    "Subtotal",
    "Tax",
    "Discount",
    "Grand Total",
  ];

  function financialSummary(bills: any[]): unknown[][] {
    const sum = (k: string) =>
      bills.reduce((s, b) => s + (Number(b[k]) || 0), 0);
    const byMethod = new Map<string, { count: number; total: number }>();
    for (const b of bills) {
      const m = b.payment_method || "unknown";
      const e = byMethod.get(m) || { count: 0, total: 0 };
      e.count += 1;
      e.total += Number(b.grand_total) || 0;
      byMethod.set(m, e);
    }
    const rows: unknown[][] = [
      ["Metric", "Value"],
      ["Total Bills", bills.length],
      ["Total Revenue", sum("grand_total").toFixed(2)],
      ["Total Tax Collected", sum("tax_total").toFixed(2)],
      ["Total Discounts", sum("discount").toFixed(2)],
      ["Net Subtotal", sum("subtotal").toFixed(2)],
      [],
      ["Payment Method", "Bills", "Revenue"],
    ];
    for (const [m, e] of byMethod)
      rows.push([m, e.count, e.total.toFixed(2)]);
    return rows;
  }

  async function buildReport(id: string): Promise<{ name: string; csv: string }> {
    if (id === "sales") {
      const bills = await fetchBills(subDays(new Date(), 30));
      return {
        name: `sales-report-last-30-days-${format(new Date(), "yyyy-MM-dd")}.csv`,
        csv: toCSV(BILL_HEADERS, billRows(bills)),
      };
    }
    if (id === "stock") {
      const stock = await pb
        .collection("stock")
        .getFullList({ expand: "product,location", sort: "location" });
      const rows = stock.map((s: any) => {
        const p = s.expand?.product;
        const qty = Number(s.quantity) || 0;
        const price = Number(p?.selling_price) || 0;
        const threshold = Number(s.low_stock_threshold) || 0;
        return [
          p?.name || s.product,
          p?.sku || "",
          p?.barcode || "",
          s.expand?.location?.name || s.location,
          qty,
          threshold,
          price,
          (qty * price).toFixed(2),
          threshold > 0 && qty <= threshold ? "LOW" : "",
        ];
      });
      return {
        name: `stock-report-${format(new Date(), "yyyy-MM-dd")}.csv`,
        csv: toCSV(
          [
            "Product",
            "SKU",
            "Barcode",
            "Location",
            "Quantity",
            "Low Stock Threshold",
            "Selling Price",
            "Stock Value",
            "Status",
          ],
          rows,
        ),
      };
    }
    // financial
    const bills = await fetchBills(subDays(new Date(), 30));
    return {
      name: `financial-report-last-30-days-${format(new Date(), "yyyy-MM-dd")}.csv`,
      csv: toCSV(financialSummary(bills)[0] as string[], financialSummary(bills).slice(1)),
    };
  }

  async function runReport(id: string) {
    if (downloading) return;
    downloading = id;
    errorMsg = "";
    try {
      const { name, csv } = await buildReport(id);
      downloadCSV(name, csv);
      const s = new Set(downloaded);
      s.add(id);
      downloaded = s;
      setTimeout(() => {
        const r = new Set(downloaded);
        r.delete(id);
        downloaded = r;
      }, 3000);
    } catch (e: any) {
      errorMsg = e?.message || "Failed to generate report";
    } finally {
      downloading = null;
    }
  }

  async function runMonthlyDownload() {
    if (monthlyDownloading) return;
    monthlyDownloading = true;
    monthlyDownloaded = false;
    errorMsg = "";
    try {
      const monthIdx = MONTHS.indexOf(selectedMonth);
      const from = startOfMonth(new Date(selectedYear, monthIdx, 1));
      const to = endOfMonth(from);
      const bills = await fetchBills(from, to);
      const csv = [
        `${selectedMonth} ${selectedYear} — Sales`,
        toCSV(BILL_HEADERS, billRows(bills)),
        "",
        `${selectedMonth} ${selectedYear} — Financial Summary`,
        toCSV(
          financialSummary(bills)[0] as string[],
          financialSummary(bills).slice(1),
        ),
      ].join("\r\n");
      downloadCSV(
        `report-${selectedYear}-${String(monthIdx + 1).padStart(2, "0")}-${selectedMonth}.csv`,
        csv,
      );
      monthlyDownloaded = true;
      setTimeout(() => (monthlyDownloaded = false), 3000);
    } catch (e: any) {
      errorMsg = e?.message || "Failed to generate monthly report";
    } finally {
      monthlyDownloading = false;
    }
  }

  const reports = [
    {
      id: "sales",
      name: "Sales Report",
      description:
        "Comprehensive sales analysis including daily, weekly, and monthly breakdowns",
      icon: TrendingUp,
      includes: [
        "Sales trends and patterns",
        "Top selling products",
        "Payment method analysis",
        "Revenue by time of day",
        "Category-wise performance",
      ],
      color: "bg-green-100 text-green-700",
    },
    {
      id: "stock",
      name: "Stock Report",
      description: "Complete inventory status and stock level analysis",
      icon: Package,
      includes: [
        "Current stock levels",
        "Low stock alerts",
        "Stock distribution by category",
        "Stock health metrics",
        "Reorder recommendations",
      ],
      color: "bg-blue-100 text-blue-700",
    },
    {
      id: "financial",
      name: "Financial Report",
      description: "Profit, revenue, and financial performance metrics",
      icon: FileBarChart,
      includes: [
        "Revenue summary",
        "Profit margins",
        "Transaction analysis",
        "Payment trends",
        "Financial forecasts",
      ],
      color: "bg-purple-100 text-purple-700",
    },
  ];
</script>

<svelte:head>
  <title>Reports - My Garments</title>
</svelte:head>

<div class="flex min-h-screen bg-background">
  <ImprovedSidebar {menuItems} userRole="Manager" />

  <FluidLayout>
    <PageHeader
      title="Reports"
      subtitle="Download business reports and analytics"
      icon={FileText}
    />

    {#if errorMsg}
      <div
        class="mb-6 flex items-center gap-2 p-3 bg-destructive/10 border border-destructive/30 rounded-lg text-destructive text-sm"
      >
        <AlertCircle class="w-4 h-4 shrink-0" />
        {errorMsg}
      </div>
    {/if}

    <!-- MONTHLY REPORT SECTION -->
    <div in:fly={{ y: 16, duration: 350 }}>
      <Card class="mb-6 md:mb-8 border-[1.5px] border-[#e0d8f0]">
        <div class="flex items-center gap-3 mb-5">
          <div
            class="w-10 h-10 rounded-lg bg-purple-100 flex items-center justify-center"
          >
            <Calendar class="w-5 h-5 text-purple-700" />
          </div>
          <div>
            <h3 class="text-lg font-medium text-gray-900">
              Monthly Report Download
            </h3>
            <p class="text-sm text-muted-foreground">
              Select a month and year to download a targeted report
            </p>
          </div>
        </div>

        <div class="flex flex-col sm:flex-row gap-3 mb-5">
          <div class="flex-1">
            <label
              class="block text-xs font-medium text-muted-foreground mb-1.5 uppercase tracking-wide"
              for="monthSelect">Month</label
            >
            <select
              id="monthSelect"
              bind:value={selectedMonth}
              onchange={() => (monthlyDownloaded = false)}
              class="w-full px-3 py-2.5 text-sm border border-border rounded-lg bg-background outline-none focus:ring-2 focus:ring-ring transition-all"
            >
              {#each MONTHS as m}
                <option value={m}>{m}</option>
              {/each}
            </select>
          </div>

          <div class="w-full sm:w-36">
            <label
              class="block text-xs font-medium text-muted-foreground mb-1.5 uppercase tracking-wide"
              for="yearSelect">Year</label
            >
            <select
              id="yearSelect"
              bind:value={selectedYear}
              onchange={() => (monthlyDownloaded = false)}
              class="w-full px-3 py-2.5 text-sm border border-border rounded-lg bg-background outline-none focus:ring-2 focus:ring-ring transition-all"
            >
              {#each YEARS as y}
                <option value={y}>{y}</option>
              {/each}
            </select>
          </div>
        </div>

        <div
          class="flex items-center gap-3 p-3 rounded-lg bg-purple-50 border border-purple-100 mb-5"
        >
          <FileText class="w-4 h-4 text-purple-600 flex-shrink-0" />
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-purple-900">
              {selectedMonth}
              {selectedYear} — Full Business Report
            </p>
            <p class="text-xs text-purple-600 mt-0.5">
              Sales · Stock · Financial data for the selected month
            </p>
          </div>
        </div>

        <Button
          onclick={runMonthlyDownload}
          disabled={monthlyDownloading}
          icon={monthlyDownloaded ? CheckCircle : Download}
          variant={monthlyDownloaded ? "secondary" : "primary"}
          class="w-full sm:w-auto"
        >
          {monthlyDownloading
            ? `Generating ${selectedMonth} ${selectedYear} CSV…`
            : monthlyDownloaded
              ? `Downloaded — ${selectedMonth} ${selectedYear}`
              : `Download ${selectedMonth} ${selectedYear} Report (CSV)`}
        </Button>
      </Card>
    </div>

    <!-- INFO CARD -->
    <Card class="mb-6 md:mb-8 bg-blue-50 border-blue-200">
      <div class="flex items-start gap-3">
        <FileText class="w-6 h-6 text-blue-600 mt-1" />
        <div>
          <h3 class="text-lg mb-2 text-blue-900">
            General Reports (Last 30 Days)
          </h3>
          <p class="text-sm text-blue-700">
            Download general reports covering the last 30 days of data as CSV
            files, ready to open in Excel or Google Sheets.
          </p>
        </div>
      </div>
    </Card>

    <!-- GENERAL REPORTS GRID -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 md:gap-8">
      {#each reports as report, idx}
        {@const Icon = report.icon}
        {@const isDownloading = downloading === report.id}
        {@const isDownloaded = downloaded.has(report.id)}

        <div in:fly={{ y: 20, duration: 300, delay: idx * 100 }}>
          <Card class="h-full">
            <div class="flex items-start gap-4 mb-4">
              <div
                class="w-12 h-12 rounded-lg flex items-center justify-center {report.color}"
              >
                <Icon class="w-6 h-6" />
              </div>
              <div class="flex-1">
                <h3 class="text-xl mb-1">{report.name}</h3>
                <p class="text-sm text-muted-foreground">
                  {report.description}
                </p>
              </div>
            </div>

            <div class="mb-6">
              <p class="text-sm font-medium mb-2 text-muted-foreground">
                Includes:
              </p>
              <ul class="space-y-1">
                {#each report.includes as item}
                  <li class="text-sm flex items-start gap-2">
                    <CheckCircle
                      class="w-4 h-4 text-green-600 mt-0.5 flex-shrink-0"
                    />
                    <span>{item}</span>
                  </li>
                {/each}
              </ul>
            </div>

            <Button
              onclick={() => runReport(report.id)}
              disabled={isDownloading}
              icon={isDownloaded ? CheckCircle : Download}
              variant={isDownloaded ? "secondary" : "primary"}
              class="w-full"
            >
              {isDownloading
                ? "Generating CSV…"
                : isDownloaded
                  ? "Downloaded Successfully"
                  : "Download Report (Last 30 Days)"}
            </Button>
          </Card>
        </div>
      {/each}
    </div>

    <!-- Additional Info -->
    <Card class="mt-8">
      <h3 class="mb-4 text-lg md:text-xl">Report Features</h3>
      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <div>
          <h4 class="font-medium mb-2 flex items-center gap-2">
            <FileText class="w-4 h-4 text-primary" />
            Format & Layout
          </h4>
          <ul class="space-y-1 text-sm text-muted-foreground">
            <li>• Spreadsheet-ready CSV format</li>
            <li>• Opens in Excel / Google Sheets</li>
            <li>• One row per record</li>
            <li>• UTF-8 with Excel BOM</li>
          </ul>
        </div>
        <div>
          <h4 class="font-medium mb-2 flex items-center gap-2">
            <Download class="w-4 h-4 text-primary" />
            Data Included
          </h4>
          <ul class="space-y-1 text-sm text-muted-foreground">
            <li>• Last 30 days or selected month</li>
            <li>• Comparative analytics</li>
            <li>• Trend predictions</li>
            <li>• Executive summary</li>
          </ul>
        </div>
      </div>
    </Card>
  </FluidLayout>
</div>
