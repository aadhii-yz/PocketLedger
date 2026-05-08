<script lang="ts">
  import ImprovedSidebar from "$lib/components/ImprovedSidebar.svelte";
  import FluidLayout from "$lib/components/FluidLayout.svelte";
  import Card from "$lib/components/Card.svelte";
  import {
    Receipt,
    History,
    Store,
    ChevronDown,
    ChevronUp,
    Banknote,
    Smartphone,
    CreditCard,
    AlertCircle,
    RefreshCw,
    Printer,
  } from "lucide-svelte";
  import { pb } from "$lib/pb";
  import { printReceipt, loadPrintSettings } from "$lib/print";
  import { onMount } from "svelte";
  import { slide } from "svelte/transition";

  const menuItems = [
    { label: "Billing", icon: Receipt, path: "/billing" },
    { label: "Bill History", icon: History, path: "/billing/history" },
  ];

  interface ShopOption {
    id: string;
    name: string;
  }

  interface BillItem {
    id: string;
    product_name: string;
    quantity: number;
    unit_price: number;
    tax_rate: number;
    line_total: number;
  }

  interface Bill {
    id: string;
    bill_number: string;
    grand_total: number;
    subtotal: number;
    tax_total: number;
    discount: number;
    payment_method: string;
    payment_status: string;
    customer_name: string;
    customer_phone: string;
    notes: string;
    created: string;
    items?: BillItem[];
    loadingItems?: boolean;
    expanded?: boolean;
  }

  let userRole = $state("");
  let assignedShop = $state("");
  let shopName = $state("");
  let shops = $state<ShopOption[]>([]);
  let selectedShopId = $state("");
  let bills = $state<Bill[]>([]);
  let loading = $state(false);
  let errorMsg = $state("");
  let page = $state(1);
  let totalPages = $state(1);
  let perPage = $state(10);

  const paymentIcons: Record<string, typeof Receipt> = {
    cash: Banknote,
    upi: Smartphone,
    card: CreditCard,
    credit: Receipt,
  };

  const paymentLabels: Record<string, string> = {
    cash: "Cash",
    upi: "UPI",
    card: "Card",
    credit: "Credit",
  };

  const statusColors: Record<string, string> = {
    paid: "bg-green-100 text-green-800",
    pending: "bg-yellow-100 text-yellow-800",
    partial: "bg-blue-100 text-blue-800",
  };

  async function loadBills(shopId: string, pageNum = 1) {
    loading = true;
    errorMsg = "";
    bills = [];
    try {
      const mapBill = (b: any) => ({
        id: b.id,
        bill_number: b.bill_number,
        grand_total: b.grand_total,
        subtotal: b.subtotal,
        tax_total: b.tax_total,
        discount: b.discount,
        payment_method: b.payment_method,
        payment_status: b.payment_status,
        customer_name: b.customer_name || "",
        customer_phone: b.customer_phone || "",
        notes: b.notes || "",
        created: b.created,
        expanded: false,
        loadingItems: false,
      });
      if (perPage === 0) {
        const result = await pb.collection("bills").getFullList({
          filter: `shop = "${shopId}"`,
          sort: "-created",
          expand: "shop",
        });
        bills = result.map(mapBill);
        totalPages = 1;
        page = 1;
      } else {
        const result = await pb.collection("bills").getList(pageNum, perPage, {
          filter: `shop = "${shopId}"`,
          sort: "-created",
          expand: "shop",
        });
        bills = result.items.map(mapBill);
        totalPages = result.totalPages;
        page = pageNum;
      }
    } catch (e: any) {
      errorMsg = e.message || "Failed to load bills";
    } finally {
      loading = false;
    }
  }

  async function toggleBill(bill: Bill) {
    if (bill.expanded) {
      bills = bills.map((b) =>
        b.id === bill.id ? { ...b, expanded: false } : b,
      );
      return;
    }

    if (bill.items) {
      bills = bills.map((b) =>
        b.id === bill.id ? { ...b, expanded: true } : b,
      );
      return;
    }

    bills = bills.map((b) =>
      b.id === bill.id ? { ...b, loadingItems: true } : b,
    );
    try {
      const records = await pb.collection("bill_items").getFullList({
        filter: `bill = "${bill.id}"`,
        sort: "product_name",
      });
      const items: BillItem[] = records.map((r: any) => ({
        id: r.id,
        product_name: r.product_name,
        quantity: r.quantity,
        unit_price: r.unit_price,
        tax_rate: r.tax_rate,
        line_total: r.line_total,
      }));
      bills = bills.map((b) =>
        b.id === bill.id
          ? { ...b, items, expanded: true, loadingItems: false }
          : b,
      );
    } catch {
      bills = bills.map((b) =>
        b.id === bill.id ? { ...b, loadingItems: false } : b,
      );
    }
  }

  async function handleShopChange(shopId: string) {
    selectedShopId = shopId;
    bills = [];
    if (shopId) {
      const shop = shops.find((s) => s.id === shopId);
      shopName = shop?.name || "";
      await loadBills(shopId);
    }
  }

  onMount(() => {
    async function init() {
      const user = pb.authStore.record as any;
      userRole = user?.role || "";

      if (userRole === "pos") {
        assignedShop = user?.assigned_shop || "";
        if (!assignedShop) {
          errorMsg = "No shop assigned to your account. Contact an admin.";
          return;
        }
        selectedShopId = assignedShop;
        try {
          const loc = await pb.collection("locations").getOne(assignedShop);
          shopName = (loc as any)?.name || "";
        } catch {}
        await loadBills(assignedShop);
      } else {
        try {
          const shopRecords = await pb.collection("locations").getFullList({
            filter: "type = 'shop' && is_active = true",
            sort: "name",
          });
          shops = shopRecords.map((s: any) => ({ id: s.id, name: s.name }));
        } catch (e) {
          console.error("Failed to load shops", e);
        }
      }
    }
    init();
  });

  async function handlePrintBill(bill: Bill) {
    if (!bill.items) return;
    const settings = await loadPrintSettings();
    printReceipt(
      {
        bill_number: bill.bill_number,
        shop_name: shopName,
        date: new Date(bill.created),
        items: bill.items.map((i) => ({
          name: i.product_name,
          qty: i.quantity,
          unit_price: i.unit_price,
          tax_rate: i.tax_rate,
        })),
        subtotal: bill.subtotal,
        tax_total: bill.tax_total,
        discount: bill.discount,
        grand_total: bill.grand_total,
        payment_method: bill.payment_method,
        customer_name: bill.customer_name || undefined,
        customer_phone: bill.customer_phone || undefined,
      },
      settings,
    );
  }

  function formatDate(dateStr: string) {
    return new Date(dateStr).toLocaleString("en-GB", {
      day: "2-digit",
      month: "short",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
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
</script>

<svelte:head>
  <title>Bill History - My Garments</title>
</svelte:head>

<div class="flex min-h-screen bg-background">
  <ImprovedSidebar {menuItems} userRole="Billing" />

  <FluidLayout maxWidth="full">
    <div class="mb-4">
      <h1 class="text-2xl md:text-3xl lg:text-4xl">Bill History</h1>
      <p class="text-muted-foreground text-sm md:text-base">
        {shopName ? `Shop: ${shopName}` : "View past bills for a shop"}
      </p>
    </div>

    {#if userRole !== "pos" && shops.length > 0}
      <Card class="mb-4">
        <div class="flex items-center gap-3">
          <Store class="w-5 h-5 text-primary shrink-0" />
          <div class="flex-1">
            <label for="shopSelect" class="block text-xs text-muted-foreground mb-1">Select Shop</label>
            <select
              id="shopSelect"
              value={selectedShopId}
              onchange={(e) => handleShopChange((e.target as HTMLSelectElement).value)}
              class="w-full px-3 py-2 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring text-sm"
            >
              <option value="">— Choose a shop —</option>
              {#each shops as shop}
                <option value={shop.id}>{shop.name}</option>
              {/each}
            </select>
          </div>
        </div>
      </Card>
    {/if}

    {#if errorMsg}
      <div class="flex items-center gap-2 p-3 mb-4 bg-destructive/10 border border-destructive/30 rounded-lg text-destructive text-sm">
        <AlertCircle class="w-4 h-4 shrink-0" />
        {errorMsg}
      </div>
    {/if}

    {#if !selectedShopId && userRole !== "pos"}
      <Card>
        <div class="text-center py-16">
          <Store class="w-16 h-16 mx-auto mb-4 opacity-20" />
          <p class="text-lg text-muted-foreground">Select a shop to view its bill history</p>
        </div>
      </Card>
    {:else if loading}
      <Card>
        <div class="text-center py-16">
          <RefreshCw class="w-10 h-10 mx-auto mb-4 opacity-40 animate-spin" />
          <p class="text-muted-foreground">Loading bills…</p>
        </div>
      </Card>
    {:else if bills.length === 0}
      <Card>
        <div class="text-center py-16">
          <Receipt class="w-16 h-16 mx-auto mb-4 opacity-20" />
          <p class="text-lg text-muted-foreground">No bills found</p>
        </div>
      </Card>
    {:else}
      <div class="flex justify-end mb-2">
        <div class="flex items-center gap-2 text-sm">
          <span class="text-muted-foreground">Rows:</span>
          <select
            value={perPage}
            onchange={(e) => { perPage = parseInt((e.target as HTMLSelectElement).value); loadBills(selectedShopId, 1); }}
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
      <div class="space-y-2">
        {#each bills as bill (bill.id)}
          <Card class="p-0 overflow-hidden">
            <button
              onclick={() => toggleBill(bill)}
              class="w-full p-4 text-left hover:bg-muted/40 transition-colors"
            >
              <div class="flex items-center justify-between gap-3">
                <div class="flex items-center gap-3 min-w-0">
                  <div class="text-primary shrink-0">
                    {#if bill.payment_method && paymentIcons[bill.payment_method]}
                      {@const Icon = paymentIcons[bill.payment_method]}
                      <Icon class="w-5 h-5" />
                    {:else}
                      <Receipt class="w-5 h-5" />
                    {/if}
                  </div>
                  <div class="min-w-0">
                    <p class="font-semibold text-base">{bill.bill_number}</p>
                    <p class="text-xs text-muted-foreground">{formatDate(bill.created)}</p>
                    {#if bill.customer_name}
                      <p class="text-xs text-muted-foreground truncate">{bill.customer_name}{bill.customer_phone ? ` · ${bill.customer_phone}` : ""}</p>
                    {/if}
                  </div>
                </div>

                <div class="flex items-center gap-3 shrink-0">
                  <div class="text-right">
                    <p class="font-bold text-lg text-primary">₹{Math.round(bill.grand_total).toLocaleString()}</p>
                    <div class="flex items-center gap-1.5 justify-end">
                      <span class="text-xs px-1.5 py-0.5 rounded-full {statusColors[bill.payment_status] || 'bg-muted text-muted-foreground'}">
                        {bill.payment_status}
                      </span>
                      <span class="text-xs text-muted-foreground">{paymentLabels[bill.payment_method] || bill.payment_method}</span>
                    </div>
                  </div>
                  {#if bill.loadingItems}
                    <RefreshCw class="w-4 h-4 animate-spin text-muted-foreground" />
                  {:else if bill.expanded}
                    <ChevronUp class="w-4 h-4 text-muted-foreground" />
                  {:else}
                    <ChevronDown class="w-4 h-4 text-muted-foreground" />
                  {/if}
                </div>
              </div>
            </button>

            {#if bill.expanded && bill.items}
              <div transition:slide={{ duration: 150 }} class="border-t border-border">
                <div class="px-4 py-3 bg-muted/30">
                  <table class="w-full text-sm">
                    <thead>
                      <tr class="text-muted-foreground text-xs">
                        <th class="text-left pb-2 font-medium">Product</th>
                        <th class="text-center pb-2 font-medium">Qty</th>
                        <th class="text-right pb-2 font-medium">Unit Price</th>
                        <th class="text-right pb-2 font-medium">Total</th>
                      </tr>
                    </thead>
                    <tbody class="divide-y divide-border">
                      {#each bill.items as item (item.id)}
                        <tr>
                          <td class="py-1.5 pr-2">
                            {item.product_name}
                            {#if item.tax_rate > 0}
                              <span class="text-xs text-muted-foreground ml-1">+{item.tax_rate}% tax</span>
                            {/if}
                          </td>
                          <td class="py-1.5 text-center">{item.quantity}</td>
                          <td class="py-1.5 text-right">₹{item.unit_price.toLocaleString()}</td>
                          <td class="py-1.5 text-right font-medium">₹{Math.round(item.line_total).toLocaleString()}</td>
                        </tr>
                      {/each}
                    </tbody>
                  </table>

                  <div class="mt-3 pt-3 border-t border-border space-y-1 text-sm">
                    {#if bill.discount > 0}
                      <div class="flex justify-between text-muted-foreground">
                        <span>Discount</span>
                        <span>-₹{bill.discount.toLocaleString()}</span>
                      </div>
                    {/if}
                    {#if bill.tax_total > 0}
                      <div class="flex justify-between text-muted-foreground">
                        <span>Tax</span>
                        <span>₹{Math.round(bill.tax_total).toLocaleString()}</span>
                      </div>
                    {/if}
                    <div class="flex justify-between font-semibold text-base pt-1">
                      <span>Grand Total</span>
                      <span class="text-primary">₹{Math.round(bill.grand_total).toLocaleString()}</span>
                    </div>
                  </div>

                  {#if bill.notes}
                    <p class="mt-2 text-xs text-muted-foreground italic">Note: {bill.notes}</p>
                  {/if}

                  <div class="mt-3 pt-3 border-t border-border">
                    <button
                      onclick={() => handlePrintBill(bill)}
                      class="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors"
                    >
                      <Printer class="w-4 h-4" />
                      Print Receipt
                    </button>
                  </div>
                </div>
              </div>
            {/if}
          </Card>
        {/each}
      </div>

      {#if totalPages > 1 && perPage !== 0}
        <div class="flex items-center justify-center gap-1 mt-6 flex-wrap">
          <button
            onclick={() => loadBills(selectedShopId, page - 1)}
            disabled={page <= 1}
            class="px-3 py-1.5 rounded-lg border border-border text-sm hover:bg-muted transition-colors disabled:opacity-40"
          >Previous</button>
          {#each getPages(page, totalPages) as p}
            {#if p === "..."}
              <span class="px-2 py-1.5 text-sm text-muted-foreground">…</span>
            {:else}
              <button
                onclick={() => loadBills(selectedShopId, p as number)}
                class="px-3 py-1.5 rounded-lg border text-sm transition-colors {p === page ? 'bg-primary text-primary-foreground border-primary' : 'border-border hover:bg-muted'}"
              >{p}</button>
            {/if}
          {/each}
          <button
            onclick={() => loadBills(selectedShopId, page + 1)}
            disabled={page >= totalPages}
            class="px-3 py-1.5 rounded-lg border border-border text-sm hover:bg-muted transition-colors disabled:opacity-40"
          >Next</button>
        </div>
      {/if}
    {/if}
  </FluidLayout>
</div>
