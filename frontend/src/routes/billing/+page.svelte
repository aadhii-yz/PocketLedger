<script lang="ts">
  import ImprovedSidebar from "$lib/components/ImprovedSidebar.svelte";
  import { isCompanionMode, companionMenuItem } from "$lib/companion";
  import FluidLayout from "$lib/components/FluidLayout.svelte";
  import Card from "$lib/components/Card.svelte";
  import Button from "$lib/components/Button.svelte";
  import {
    Receipt,
    History,
    Plus,
    Minus,
    Trash2,
    CreditCard,
    Smartphone,
    Banknote,
    Printer,
    Search,
    AlertCircle,
    ChevronDown,
    X,
    Store,
  } from "lucide-svelte";
  import BarcodeScanner from "$lib/components/BarcodeScanner.svelte";
  import { pb, customFetch } from "$lib/pb";
  import { printReceipt, loadPrintSettings } from "$lib/print";
  import { onMount, onDestroy } from "svelte";
  import { slide, fade } from "svelte/transition";

  const baseMenuItems = [
    { label: "Billing", icon: Receipt, path: "/billing" },
    { label: "Bill History", icon: History, path: "/billing/history" },
  ];
  const menuItems = isCompanionMode() ? [...baseMenuItems, companionMenuItem] : baseMenuItems;

  interface Product {
    id: string;
    name: string;
    category: string;
    price: number;
    costPrice: number;
    taxRate: number;
    quantity: number;
    barcode: string;
    sku: string;
  }

  interface CartItem {
    product: Product;
    quantity: number;
  }

  let products = $state<Product[]>([]);
  let loadingProducts = $state(true);
  let searchTerm = $state("");
  let cart = $state<CartItem[]>([]);
  let paymentMethod = $state<"cash" | "upi" | "card" | "credit">("cash");
  let showReceipt = $state(false);
  let billNumber = $state("");
  let submitting = $state(false);
  let errorMsg = $state("");
  let showProductPicker = $state(false);
  let pickerCategory = $state<string>("");
  let pickerRef = $state<HTMLElement | null>(null);
  let searchInputEl = $state<HTMLInputElement | null>(null);
  interface ShopOption { id: string; name: string; }

  let userRole = $state("");
  let assignedShop = $state("");
  let shopName = $state("");
  let shops = $state<ShopOption[]>([]);
  let selectedShopId = $state("");
  let online = $state(true);
  let clearTimer: ReturnType<typeof setTimeout> | undefined;

  $effect(() => {
    online = navigator.onLine;
    const setOnline = () => (online = true);
    const setOffline = () => (online = false);
    window.addEventListener('online', setOnline);
    window.addEventListener('offline', setOffline);
    return () => {
      window.removeEventListener('online', setOnline);
      window.removeEventListener('offline', setOffline);
    };
  });

  async function loadStockForShop(shopId: string) {
    loadingProducts = true;
    products = [];
    try {
      const [productRecords, stockRecords, shopRecord] = await Promise.all([
        pb.collection("products").getFullList({ expand: "category" }),
        pb.collection("stock").getFullList({ filter: `location = "${shopId}"` }),
        pb.collection("locations").getOne(shopId),
      ]);
      shopName = (shopRecord as any)?.name || "";
      const stockMap = new Map(
        stockRecords.map((s: any) => [s.product, s.quantity as number]),
      );
      products = productRecords.map((p: any) => ({
        id: p.id,
        name: p.name,
        sku: p.sku || "",
        barcode: p.barcode || "",
        category: p.expand?.category?.name || "Uncategorized",
        price: p.selling_price || 0,
        costPrice: p.cost_price || 0,
        taxRate: p.tax_rate || 0,
        quantity: stockMap.get(p.id) || 0,
      }));
    } catch (e: any) {
      errorMsg = e?.message || "Failed to load products for this shop.";
    } finally {
      loadingProducts = false;
      setTimeout(() => searchInputEl?.focus(), 50);
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
          loadingProducts = false;
          return;
        }
        selectedShopId = assignedShop;
        await loadStockForShop(assignedShop);
      } else {
        // manager / stock_entry — load all shops and let them pick
        try {
          const shopRecords = await pb.collection("locations").getFullList({
            filter: "type = 'shop' && is_active = true",
            sort: "name",
          });
          shops = shopRecords.map((s: any) => ({ id: s.id, name: s.name }));
        } catch (e) {
          console.error("Failed to load shops", e);
        }
        loadingProducts = false;
      }
    }
    init();
  });

  onDestroy(() => {
    clearTimeout(clearTimer);
  });

  function handleOutsideClick(e: MouseEvent) {
    if (
      showProductPicker &&
      pickerRef &&
      !pickerRef.contains(e.target as Node)
    ) {
      showProductPicker = false;
    }
  }

  let categories = $derived(
    Array.from(new Set(products.map((p) => p.category))).sort(),
  );

  let filteredProducts = $derived(
    products.filter(
      (p) =>
        p.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
        p.barcode.toLowerCase().includes(searchTerm.toLowerCase()) ||
        p.sku.toLowerCase().includes(searchTerm.toLowerCase()),
    ),
  );

  let pickerProducts = $derived(
    showProductPicker
      ? pickerCategory
        ? products.filter((p) => p.category === pickerCategory)
        : products
      : [],
  );

  function addToCart(product: Product) {
    const existingItem = cart.find((item) => item.product.id === product.id);
    if (existingItem) {
      cart = cart.map((item) =>
        item.product.id === product.id
          ? { ...item, quantity: item.quantity + 1 }
          : item,
      );
    } else {
      cart = [...cart, { product, quantity: 1 }];
    }
    searchTerm = "";
    errorMsg = "";
    searchInputEl?.focus();
  }

  function handleSearchKeydown(e: KeyboardEvent) {
    if (e.key !== "Enter" || !searchTerm || loadingProducts || !selectedShopId)
      return;
    const exactMatch = products.find(
      (p) => p.barcode === searchTerm || p.sku === searchTerm,
    );
    if (exactMatch) {
      if (exactMatch.quantity > 0) {
        addToCart(exactMatch);
      } else {
        errorMsg = `"${exactMatch.name}" is out of stock`;
      }
      return;
    }
    if (filteredProducts.length === 1) {
      if (filteredProducts[0].quantity > 0) {
        addToCart(filteredProducts[0]);
      } else {
        errorMsg = `"${filteredProducts[0].name}" is out of stock`;
      }
    }
  }

  function handleWindowKeydown(e: KeyboardEvent) {
    const target = e.target as HTMLElement;
    const isInputFocused =
      target.tagName === "INPUT" ||
      target.tagName === "TEXTAREA" ||
      target.tagName === "SELECT";
    if (
      !isInputFocused &&
      e.key.length === 1 &&
      !e.ctrlKey &&
      !e.metaKey &&
      !e.altKey &&
      selectedShopId &&
      !loadingProducts &&
      searchInputEl
    ) {
      e.preventDefault();
      searchTerm += e.key;
      searchInputEl.focus();
    }
  }

  function updateQuantity(productId: string, delta: number) {
    cart = cart
      .map((item) =>
        item.product.id === productId
          ? { ...item, quantity: item.quantity + delta }
          : item,
      )
      .filter((item) => item.quantity > 0);
  }

  function removeFromCart(productId: string) {
    cart = cart.filter((item) => item.product.id !== productId);
  }

  let total = $derived(
    cart.reduce((sum, item) => {
      const lineTotal = item.product.price * item.quantity;
      const tax = lineTotal * (item.product.taxRate / 100);
      return sum + lineTotal + tax;
    }, 0),
  );

  async function handleShopChange(shopId: string) {
    selectedShopId = shopId;
    cart = [];
    errorMsg = "";
    if (shopId) await loadStockForShop(shopId);
  }

  async function handleGenerateBill() {
    if (cart.length === 0 || submitting) return;
    submitting = true;
    errorMsg = "";
    try {
      const payload = {
        shop_id: selectedShopId,
        customer_name: "",
        customer_phone: "",
        items: cart.map((item) => ({
          product_id: item.product.id,
          quantity: item.quantity,
          unit_price: item.product.price,
          tax_rate: item.product.taxRate,
        })),
        discount: 0,
        payment_method: paymentMethod,
        payment_status: "paid",
        notes: "",
      };
      const result = await customFetch("/bills/create", {
        method: "POST",
        body: JSON.stringify(payload),
      });
      billNumber = result.bill_number;
      showReceipt = true;

      // Compute totals from cart for the receipt.
      const subtotal = cart.reduce((s, item) => s + item.product.price * item.quantity, 0);
      const taxTotal = cart.reduce(
        (s, item) => s + item.product.price * item.quantity * (item.product.taxRate / 100),
        0,
      );
      const settings = await loadPrintSettings();
      printReceipt(
        {
          bill_number: result.bill_number,
          shop_name: shopName,
          date: new Date(),
          items: cart.map((c) => ({
            name: c.product.name,
            qty: c.quantity,
            unit_price: c.product.price,
            tax_rate: c.product.taxRate,
          })),
          subtotal,
          tax_total: taxTotal,
          discount: 0,
          grand_total: result.grand_total,
          payment_method: paymentMethod,
        },
        settings,
      );

      products = products.map((p) => {
        const cartItem = cart.find((c) => c.product.id === p.id);
        return cartItem
          ? { ...p, quantity: p.quantity - cartItem.quantity }
          : p;
      });
      clearTimer = setTimeout(() => {
        showReceipt = false;
        cart = [];
        paymentMethod = "cash";
        billNumber = "";
        searchInputEl?.focus();
      }, 4000);
    } catch (e: any) {
      errorMsg = e.message || "Failed to create bill";
    } finally {
      submitting = false;
    }
  }

  function setPaymentMethodMode(method: "cash" | "upi" | "card" | "credit") {
    paymentMethod = method;
  }

  function handleBarcodeScan(barcode: string) {
    const exactMatch = products.find((p) => p.barcode === barcode || p.sku === barcode);
    if (exactMatch) {
      if (exactMatch.quantity > 0) {
        addToCart(exactMatch);
      } else {
        errorMsg = `"${exactMatch.name}" is out of stock`;
      }
    } else {
      searchTerm = barcode;
    }
  }
</script>

<svelte:window onmousedown={handleOutsideClick} onkeydown={handleWindowKeydown} />
<svelte:head>
  <title>Point of Sale - My Garments</title>
</svelte:head>

<div class="flex min-h-screen bg-background">
  <ImprovedSidebar {menuItems} userRole="Billing" />

  <FluidLayout maxWidth="full">
    <div class="mb-4">
      <h1 class="text-2xl md:text-3xl lg:text-4xl">Point of Sale</h1>
      <p class="text-muted-foreground text-sm md:text-base">
        {shopName ? `Shop: ${shopName}` : "Fast and easy billing"}
      </p>
    </div>

    {#if userRole !== "pos" && shops.length > 0}
      <Card class="mb-4">
        <div class="flex items-center gap-3">
          <Store class="w-5 h-5 text-primary shrink-0" />
          <div class="flex-1">
            <label for="shopSelect" class="block text-xs text-muted-foreground mb-1">Select Shop to Bill From</label>
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

    <!-- Search Bar + Browse Button -->
    <Card class="mb-4">
      <div class="flex gap-2 items-start">
        <!-- Search input -->
        <div class="flex-1 relative">
          <Search
            class="absolute left-4 top-1/2 -translate-y-1/2 w-5 h-5 text-muted-foreground"
          />
          {#if searchTerm}
            <button
              onclick={() => { searchTerm = ""; searchInputEl?.focus(); }}
              class="absolute right-4 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground transition-colors"
              aria-label="Clear search"
            >
              <X class="w-5 h-5" />
            </button>
          {/if}
          <input
            type="text"
            placeholder={loadingProducts
              ? "Loading products…"
              : !selectedShopId
                ? "Select a shop first…"
                : "Search by name, SKU or scan barcode…"}
            bind:value={searchTerm}
            bind:this={searchInputEl}
            onkeydown={handleSearchKeydown}
            disabled={loadingProducts || !selectedShopId}
            class="w-full pl-12 pr-10 py-4 text-lg bg-input-background border-2 border-border rounded-xl outline-none focus:ring-2 focus:ring-ring focus:border-primary transition-all shadow-sm disabled:opacity-50"
          />
        </div>

        <!-- Camera barcode scanner (mobile only) -->
        <BarcodeScanner
          onScan={handleBarcodeScan}
          disabled={loadingProducts || !selectedShopId}
          class="px-4 py-4 bg-muted border border-border rounded-xl hover:bg-primary/10 hover:border-primary transition-colors disabled:opacity-50"
        />

        <!-- Browse / Picker toggle -->
        <button
          onclick={() => {
            showProductPicker = !showProductPicker;
            pickerCategory = "";
          }}
          disabled={loadingProducts || !selectedShopId}
          class="flex items-center gap-2 px-4 py-4 bg-primary text-primary-foreground rounded-xl font-medium whitespace-nowrap hover:opacity-90 transition-opacity disabled:opacity-50"
        >
          Browse <ChevronDown
            class="w-4 h-4 transition-transform {showProductPicker
              ? 'rotate-180'
              : ''}"
          />
        </button>
      </div>

      <!-- Inline search results dropdown -->
      {#if searchTerm && filteredProducts.length > 0}
        <div
          transition:slide={{ duration: 150 }}
          class="mt-3 max-h-64 overflow-y-auto border border-border rounded-lg"
        >
          {#each filteredProducts.slice(0, 8) as product (product.id)}
            <button
              onclick={() => addToCart(product)}
              disabled={product.quantity === 0}
              class="w-full p-3 hover:bg-muted transition-colors text-left border-b border-border last:border-0 flex justify-between items-center disabled:opacity-40"
            >
              <div>
                <p class="font-medium">{product.name}</p>
                <p class="text-sm text-muted-foreground">
                  {product.category}{product.sku ? " • " + product.sku : ""}{product.barcode ? " • " + product.barcode : ""}
                </p>
              </div>
              <div class="text-right">
                <p class="font-medium text-primary">₹{product.price}</p>
                <p
                  class="text-xs {product.quantity < 5
                    ? 'text-destructive'
                    : 'text-muted-foreground'}"
                >
                  {product.quantity} in stock
                </p>
              </div>
            </button>
          {/each}
        </div>
      {/if}

      {#if searchTerm && filteredProducts.length === 0 && !loadingProducts}
        <p class="mt-3 text-sm text-muted-foreground px-2">
          No products found for "{searchTerm}"
        </p>
      {/if}

      <!-- Product Picker Panel -->
      {#if showProductPicker}
        <div
          bind:this={pickerRef}
          transition:slide={{ duration: 200 }}
          class="mt-4 overflow-hidden"
        >
          <!-- Category tabs -->
          <div class="flex gap-2 flex-wrap mb-4">
            <button
              onclick={() => (pickerCategory = "")}
              class="px-3 py-1.5 rounded-full text-sm font-medium transition-colors {pickerCategory ===
              ''
                ? 'bg-primary text-primary-foreground'
                : 'bg-muted text-muted-foreground hover:bg-muted/80'}"
            >
              All
            </button>
            {#each categories as cat}
              <button
                onclick={() => (pickerCategory = cat)}
                class="px-3 py-1.5 rounded-full text-sm font-medium transition-colors {pickerCategory ===
                cat
                  ? 'bg-primary text-primary-foreground'
                  : 'bg-muted text-muted-foreground hover:bg-muted/80'}"
              >
                {cat}
              </button>
            {/each}
          </div>

          <!-- Product grid -->
          <div
            class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-2 max-h-80 overflow-y-auto pr-1"
          >
            {#each pickerProducts as product (product.id)}
              {@const inCart = cart.find((c) => c.product.id === product.id)}
              <button
                onclick={() => addToCart(product)}
                disabled={product.quantity === 0}
                class="relative p-3 rounded-xl border-2 text-left transition-all disabled:opacity-40 {inCart
                  ? 'border-primary bg-primary/5'
                  : 'border-border hover:border-primary/50 bg-card hover:bg-muted/50'}"
              >
                {#if inCart}
                  <span
                    class="absolute top-1.5 right-1.5 w-5 h-5 bg-primary text-primary-foreground rounded-full text-xs flex items-center justify-center font-bold"
                  >
                    {inCart.quantity}
                  </span>
                {/if}
                <p class="text-sm font-medium leading-tight mb-1 pr-5">
                  {product.name}
                </p>
                <p class="text-xs text-muted-foreground mb-1">
                  {product.category}
                </p>
                <p class="text-sm font-semibold text-primary">
                  ₹{product.price}
                </p>
                <p
                  class="text-xs mt-0.5 {product.quantity < 5
                    ? 'text-destructive'
                    : 'text-muted-foreground'}"
                >
                  {product.quantity} left
                </p>
              </button>
            {/each}
            {#if pickerProducts.length === 0}
              <p
                class="col-span-full text-center py-8 text-muted-foreground text-sm"
              >
                No products in this category
              </p>
            {/if}
          </div>

          <div class="flex justify-end mt-3">
            <button
              onclick={() => (showProductPicker = false)}
              class="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground transition-colors"
            >
              <X class="w-4 h-4" /> Close picker
            </button>
          </div>
        </div>
      {/if}
    </Card>

    <!-- Cart -->
    <Card class="mb-4 min-h-[400px]">
      <h3 class="text-xl mb-4 flex items-center gap-2">
        <Receipt class="w-6 h-6 text-primary" />
        Cart Items ({cart.length})
      </h3>

      {#if cart.length === 0}
        <div class="text-center py-20">
          <Receipt class="w-20 h-20 mx-auto mb-4 opacity-20" />
          <p class="text-xl text-muted-foreground">Cart is empty</p>
          <p class="text-sm text-muted-foreground mt-2">
            Search or browse products to start billing
          </p>
        </div>
      {:else}
        <div class="space-y-3">
          {#each cart as item (item.product.id)}
            <div
              transition:slide={{ duration: 150 }}
              class="p-4 bg-muted rounded-lg border border-border"
            >
              <div class="flex items-center justify-between mb-3">
                <div class="flex-1">
                  <p class="text-lg font-medium">{item.product.name}</p>
                  <p class="text-sm text-muted-foreground">
                    {item.product.category}{item.product.sku ? " • " + item.product.sku : ""}{item.product.barcode ? " • " + item.product.barcode : ""}
                  </p>
                  <p class="text-primary mt-1">
                    ₹{item.product.price} each {#if item.product.taxRate > 0}<span
                        class="text-xs text-muted-foreground"
                        >(+{item.product.taxRate}% tax)</span
                      >{/if}
                  </p>
                </div>
                <button
                  onclick={() => removeFromCart(item.product.id)}
                  class="text-destructive hover:bg-destructive/10 p-2 rounded transition-colors"
                >
                  <Trash2 class="w-5 h-5" />
                </button>
              </div>

              <div class="flex items-center justify-between">
                <div class="flex items-center gap-3">
                  <button
                    onclick={() => updateQuantity(item.product.id, -1)}
                    class="w-10 h-10 bg-background border-2 border-border rounded-lg flex items-center justify-center hover:bg-primary hover:text-primary-foreground transition-colors"
                  >
                    <Minus class="w-5 h-5" />
                  </button>
                  <span class="w-16 text-center text-xl font-medium"
                    >{item.quantity}</span
                  >
                  <button
                    onclick={() => updateQuantity(item.product.id, 1)}
                    disabled={item.quantity >= item.product.quantity}
                    class="w-10 h-10 bg-background border-2 border-border rounded-lg flex items-center justify-center hover:bg-primary hover:text-primary-foreground transition-colors disabled:opacity-40"
                  >
                    <Plus class="w-5 h-5" />
                  </button>
                </div>
                <div class="text-right">
                  <p class="text-sm text-muted-foreground">Subtotal</p>
                  <p class="text-2xl font-medium text-primary">
                    ₹{(item.product.price * item.quantity).toLocaleString()}
                  </p>
                </div>
              </div>
            </div>
          {/each}
        </div>
      {/if}
    </Card>

    <!-- Bill Summary -->
    <Card
      class="bg-gradient-to-br from-primary/5 to-secondary/5 border-2 border-primary/20"
    >
      <div class="space-y-4">
        <div
          class="flex justify-between items-center pb-4 border-b-2 border-border"
        >
          <span class="text-xl font-medium">Total Amount</span>
          <span class="text-4xl font-bold text-primary"
            >₹{Math.round(total).toLocaleString()}</span
          >
        </div>

        <div>
          <p class="text-sm font-medium mb-3 text-muted-foreground">
            Payment Method
          </p>
          <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <button
              onclick={() => setPaymentMethodMode("cash")}
              class="p-4 rounded-xl border-2 transition-all {paymentMethod ===
              'cash'
                ? 'border-primary bg-primary text-primary-foreground shadow-lg'
                : 'border-border hover:border-primary/50 hover:shadow-md'}"
            >
              <Banknote class="w-8 h-8 mx-auto mb-2" />
              <p class="font-medium">Cash</p>
            </button>
            <button
              onclick={() => setPaymentMethodMode("upi")}
              class="p-4 rounded-xl border-2 transition-all {paymentMethod ===
              'upi'
                ? 'border-primary bg-primary text-primary-foreground shadow-lg'
                : 'border-border hover:border-primary/50 hover:shadow-md'}"
            >
              <Smartphone class="w-8 h-8 mx-auto mb-2" />
              <p class="font-medium">UPI</p>
            </button>
            <button
              onclick={() => setPaymentMethodMode("card")}
              class="p-4 rounded-xl border-2 transition-all {paymentMethod ===
              'card'
                ? 'border-primary bg-primary text-primary-foreground shadow-lg'
                : 'border-border hover:border-primary/50 hover:shadow-md'}"
            >
              <CreditCard class="w-8 h-8 mx-auto mb-2" />
              <p class="font-medium">Card</p>
            </button>
            <button
              onclick={() => setPaymentMethodMode("credit")}
              class="p-4 rounded-xl border-2 transition-all {paymentMethod ===
              'credit'
                ? 'border-primary bg-primary text-primary-foreground shadow-lg'
                : 'border-border hover:border-primary/50 hover:shadow-md'}"
            >
              <Receipt class="w-8 h-8 mx-auto mb-2" />
              <p class="font-medium">Credit</p>
            </button>
          </div>
        </div>

        {#if !online}
          <div
            class="flex items-center gap-2 p-3 bg-yellow-50 border border-yellow-300 rounded-lg text-yellow-800 text-sm"
          >
            <AlertCircle class="w-4 h-4 shrink-0" />
            You are offline. Reconnect to process transactions.
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
          onclick={handleGenerateBill}
          disabled={cart.length === 0 || submitting || !selectedShopId || !online}
          class="w-full py-4 text-lg font-semibold flex justify-center gap-2"
        >
          {#if submitting}
            Processing…
          {:else}
            <Printer class="w-5 h-5" /> Generate Bill & Print
          {/if}
        </Button>

        {#if showReceipt}
          <div
            transition:fade={{ duration: 200 }}
            class="p-4 bg-green-50 border-2 border-green-200 rounded-xl text-center"
          >
            <p class="text-lg text-green-800 font-medium">
              Bill {billNumber} generated successfully!
            </p>
            <p class="text-sm text-green-600 mt-1">
              Payment: {paymentMethod.toUpperCase()} · Total: ₹{Math.round(
                total,
              ).toLocaleString()}
            </p>
          </div>
        {/if}
      </div>
    </Card>
  </FluidLayout>
</div>
