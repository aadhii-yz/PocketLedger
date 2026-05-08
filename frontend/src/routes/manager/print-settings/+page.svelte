<script lang="ts">
  import ImprovedSidebar from "$lib/components/ImprovedSidebar.svelte";
  import FluidLayout from "$lib/components/FluidLayout.svelte";
  import Card from "$lib/components/Card.svelte";
  import Button from "$lib/components/Button.svelte";
  import Input from "$lib/components/Input.svelte";
  import PageHeader from "$lib/components/PageHeader.svelte";
  import LoadingSpinner from "$lib/components/LoadingSpinner.svelte";
  import {
    LayoutDashboard,
    TrendingUp,
    Package,
    FileText,
    Users,
    Printer,
    Store,
    CheckCircle,
    AlertCircle,
  } from "lucide-svelte";
  import { pb } from "$lib/pb";
  import { onMount } from "svelte";

  const menuItems = [
    { label: "Dashboard", icon: LayoutDashboard, path: "/manager" },
    { label: "Sales Analysis", icon: TrendingUp, path: "/manager/sales" },
    { label: "Stock Analysis", icon: Package, path: "/manager/stock" },
    { label: "Shop Overview", icon: Store, path: "/stats/overview" },
    { label: "Reports", icon: FileText, path: "/manager/reports" },
    { label: "Users", icon: Users, path: "/manager/users" },
    { label: "Print Settings", icon: Printer, path: "/manager/print-settings" },
  ];

  let loading = $state(true);
  let saving = $state(false);
  let successMsg = $state("");
  let errorMsg = $state("");
  let settingsId = $state("");

  let shopName = $state("");
  let shopAddress = $state("");
  let shopPhone = $state("");
  let gstNumber = $state("");
  let receiptFooter = $state("Thank you for your purchase!");
  let showCustomerInfo = $state(true);
  let showTaxBreakdown = $state(true);
  let barcodeShowSku = $state(true);
  let barcodeShowPrice = $state(true);

  onMount(async () => {
    try {
      const result = await pb.collection("print_settings").getList(1, 1);
      if (result.totalItems > 0) {
        const r = result.items[0];
        settingsId = r.id;
        shopName = r["shop_name"] ?? "";
        shopAddress = r["shop_address"] ?? "";
        shopPhone = r["shop_phone"] ?? "";
        gstNumber = r["gst_number"] ?? "";
        receiptFooter = r["receipt_footer"] ?? "Thank you for your purchase!";
        showCustomerInfo = r["show_customer_info"] !== false;
        showTaxBreakdown = r["show_tax_breakdown"] !== false;
        barcodeShowSku = r["barcode_show_sku"] !== false;
        barcodeShowPrice = r["barcode_show_price"] !== false;
      }
    } catch {
      // no existing settings — defaults are already set
    } finally {
      loading = false;
    }
  });

  async function handleSave() {
    saving = true;
    errorMsg = "";
    successMsg = "";
    const data = {
      shop_name: shopName,
      shop_address: shopAddress,
      shop_phone: shopPhone,
      gst_number: gstNumber,
      receipt_footer: receiptFooter,
      show_customer_info: showCustomerInfo,
      show_tax_breakdown: showTaxBreakdown,
      barcode_show_sku: barcodeShowSku,
      barcode_show_price: barcodeShowPrice,
    };
    try {
      if (settingsId) {
        await pb.collection("print_settings").update(settingsId, data);
      } else {
        const rec = await pb.collection("print_settings").create(data);
        settingsId = rec.id;
      }
      successMsg = "Print settings saved.";
      setTimeout(() => (successMsg = ""), 3000);
    } catch (e: any) {
      errorMsg = e.message || "Failed to save settings";
    } finally {
      saving = false;
    }
  }

  // Derived preview values (live as user types)
  let previewDate = $derived(
    new Date().toLocaleDateString("en-IN", {
      day: "2-digit",
      month: "short",
      year: "numeric",
    })
  );
</script>

<div class="flex h-screen overflow-hidden bg-background">
  <ImprovedSidebar {menuItems} userRole="Manager" />
  <FluidLayout>
    <PageHeader
      title="Print Settings"
      subtitle="Configure receipt and barcode label templates"
    />

    {#if loading}
      <div class="flex justify-center py-12">
        <LoadingSpinner />
      </div>
    {:else}
      <div class="grid grid-cols-1 xl:grid-cols-2 gap-6">
        <!-- Settings Form -->
        <div class="space-y-6">
          <!-- Shop / Business Info -->
          <Card>
            <div class="p-6 space-y-4">
              <h2 class="font-semibold text-lg">Business Information</h2>
              <p class="text-sm text-muted-foreground">
                Shown on receipts and barcode labels.
              </p>

              <div>
                <label class="block text-sm font-medium mb-1" for="shop-name"
                  >Shop / Business Name</label
                >
                <Input
                  id="shop-name"
                  bind:value={shopName}
                  placeholder="My Store"
                />
              </div>

              <div>
                <label class="block text-sm font-medium mb-1" for="shop-address"
                  >Address</label
                >
                <Input
                  id="shop-address"
                  bind:value={shopAddress}
                  placeholder="123 Main St, City"
                />
              </div>

              <div>
                <label class="block text-sm font-medium mb-1" for="shop-phone"
                  >Phone</label
                >
                <Input
                  id="shop-phone"
                  bind:value={shopPhone}
                  placeholder="9876543210"
                />
              </div>

              <div>
                <label class="block text-sm font-medium mb-1" for="gst-number"
                  >GST Number <span class="text-muted-foreground font-normal">(optional)</span></label
                >
                <Input
                  id="gst-number"
                  bind:value={gstNumber}
                  placeholder="29ABCDE1234F1Z5"
                />
              </div>
            </div>
          </Card>

          <!-- Receipt Options -->
          <Card>
            <div class="p-6 space-y-4">
              <h2 class="font-semibold text-lg">Receipt Options</h2>

              <div>
                <label class="block text-sm font-medium mb-1" for="receipt-footer"
                  >Footer Text</label
                >
                <Input
                  id="receipt-footer"
                  bind:value={receiptFooter}
                  placeholder="Thank you for your purchase!"
                />
              </div>

              <label class="flex items-center gap-3 cursor-pointer select-none">
                <input
                  type="checkbox"
                  bind:checked={showCustomerInfo}
                  class="w-4 h-4 accent-primary"
                />
                <span class="text-sm font-medium">Show customer name &amp; phone on receipt</span>
              </label>

              <label class="flex items-center gap-3 cursor-pointer select-none">
                <input
                  type="checkbox"
                  bind:checked={showTaxBreakdown}
                  class="w-4 h-4 accent-primary"
                />
                <span class="text-sm font-medium">Show subtotal / GST breakdown on receipt</span>
              </label>
            </div>
          </Card>

          <!-- Barcode Label Options -->
          <Card>
            <div class="p-6 space-y-4">
              <h2 class="font-semibold text-lg">Barcode Label Options</h2>

              <label class="flex items-center gap-3 cursor-pointer select-none">
                <input
                  type="checkbox"
                  bind:checked={barcodeShowPrice}
                  class="w-4 h-4 accent-primary"
                />
                <span class="text-sm font-medium">Show selling price on label</span>
              </label>

              <label class="flex items-center gap-3 cursor-pointer select-none">
                <input
                  type="checkbox"
                  bind:checked={barcodeShowSku}
                  class="w-4 h-4 accent-primary"
                />
                <span class="text-sm font-medium">Show SKU on label</span>
              </label>
            </div>
          </Card>

          <!-- Feedback & Save -->
          {#if successMsg}
            <div
              class="flex items-center gap-2 p-3 bg-green-50 border border-green-200 rounded-lg text-green-800 text-sm"
            >
              <CheckCircle class="w-4 h-4 shrink-0" />
              {successMsg}
            </div>
          {/if}
          {#if errorMsg}
            <div
              class="flex items-center gap-2 p-3 bg-destructive/10 border border-destructive/30 rounded-lg text-destructive text-sm"
            >
              <AlertCircle class="w-4 h-4 shrink-0" />
              {errorMsg}
            </div>
          {/if}

          <Button
            onclick={handleSave}
            disabled={saving}
            class="w-full"
          >
            {saving ? "Saving…" : "Save Settings"}
          </Button>
        </div>

        <!-- Live Preview -->
        <div class="space-y-6">
          <!-- Receipt Preview -->
          <Card>
            <div class="p-6">
              <h2 class="font-semibold text-lg mb-4">Receipt Preview (80mm)</h2>
              <div
                class="mx-auto bg-white border border-dashed border-gray-300 rounded p-3 text-xs font-mono"
                style="width: 260px; color: #000;"
              >
                {#if shopName}
                  <p class="text-center font-bold text-sm">{shopName}</p>
                {:else}
                  <p class="text-center font-bold text-sm text-gray-400">SHOP NAME</p>
                {/if}
                {#if shopAddress}
                  <p class="text-center">{shopAddress}</p>
                {/if}
                {#if shopPhone}
                  <p class="text-center">Ph: {shopPhone}</p>
                {/if}
                {#if gstNumber}
                  <p class="text-center">GST: {gstNumber}</p>
                {/if}
                <p class="border-t border-dashed border-gray-400 mt-1 pt-1">
                  Date: {previewDate}
                </p>
                <p>Bill No: INV-0001</p>
                <div class="border-t border-dashed border-gray-400 mt-1 pt-1">
                  <div class="flex justify-between">
                    <span>Item</span>
                    <span>Qty Rate Amt</span>
                  </div>
                  <div class="flex justify-between">
                    <span>Sample Product</span>
                    <span>2 50.00 100.00</span>
                  </div>
                </div>
                {#if showTaxBreakdown}
                  <div class="border-t border-dashed border-gray-400 mt-1 pt-1">
                    <div class="flex justify-between">
                      <span>Subtotal</span><span>₹100.00</span>
                    </div>
                    <div class="flex justify-between">
                      <span>GST</span><span>₹18.00</span>
                    </div>
                  </div>
                {/if}
                <div
                  class="border-t border-gray-600 mt-1 pt-1 font-bold flex justify-between"
                >
                  <span>TOTAL</span><span>₹118.00</span>
                </div>
                <div class="border-t border-dashed border-gray-400 mt-1 pt-1">
                  <p>Payment: CASH</p>
                  {#if showCustomerInfo}
                    <p class="text-gray-400">Customer: John / 9876543210</p>
                  {/if}
                </div>
                {#if receiptFooter}
                  <p
                    class="border-t border-dashed border-gray-400 mt-1 pt-1 text-center"
                  >
                    {receiptFooter}
                  </p>
                {/if}
              </div>
            </div>
          </Card>

          <!-- Barcode Label Preview -->
          <Card>
            <div class="p-6">
              <h2 class="font-semibold text-lg mb-4">Barcode Label Preview</h2>
              <div
                class="mx-auto bg-white border border-gray-300 rounded p-3 text-center"
                style="width: 200px;"
              >
                {#if shopName}
                  <p class="text-xs font-bold mb-1">{shopName}</p>
                {:else}
                  <p class="text-xs font-bold text-gray-400 mb-1">SHOP NAME</p>
                {/if}
                <!-- Simulated barcode bars -->
                <div
                  class="mx-auto mb-1 flex items-end gap-px"
                  style="height: 36px; width: 140px;"
                  aria-label="Barcode preview"
                >
                  {#each [3,1,2,1,3,1,2,3,1,2,1,3,2,1,3,2,1,2,3,1,2,1,2,3,1,2,1,3,2,1] as w, i}
                    <div
                      style="width: {w}px; height: {i % 3 === 0 ? '100%' : '85%'}; background: #000;"
                    ></div>
                  {/each}
                </div>
                <p class="text-xs font-mono mb-1">0000000042</p>
                <p class="text-xs font-bold">Sample Product</p>
                {#if barcodeShowPrice}
                  <p class="text-sm font-bold">₹200.00</p>
                {/if}
                {#if barcodeShowSku}
                  <p class="text-xs text-gray-500">SKU: CAT-PRD-0001</p>
                {/if}
              </div>
            </div>
          </Card>
        </div>
      </div>
    {/if}
  </FluidLayout>
</div>
