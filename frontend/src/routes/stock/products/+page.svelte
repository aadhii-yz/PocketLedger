<script lang="ts">
  import ImprovedSidebar from '$lib/components/ImprovedSidebar.svelte';
  import FluidLayout from '$lib/components/FluidLayout.svelte';
  import Card from '$lib/components/Card.svelte';
  import Button from '$lib/components/Button.svelte';
  import Input from '$lib/components/Input.svelte';
  import DataTable from '$lib/components/DataTable.svelte';
  import PageHeader from '$lib/components/PageHeader.svelte';
  import LoadingSpinner from '$lib/components/LoadingSpinner.svelte';
  import { Package, ShoppingBag, Plus, Edit, Trash2, Barcode, Printer, RefreshCw, Search, X, AlertCircle } from 'lucide-svelte';
  import { pb, customFetch } from '$lib/pb';
  import { onMount } from 'svelte';
  import { slide } from 'svelte/transition';

  const menuItems = [
    { label: 'Product Management', icon: ShoppingBag, path: '/stock/products' },
    { label: 'Stock Management', icon: Package, path: '/stock/inventory' },
  ];

  interface Product {
    id: string;
    name: string;
    sku: string;
    barcode: string;
    categoryId: string;
    category: string;
    sellingPrice: number;
    costPrice: number;
    taxRate: number;
  }

  interface Category {
    id: string;
    name: string;
  }

  let products = $state<Product[]>([]);
  let categories = $state<Category[]>([]);
  let loading = $state(true);
  let errorMsg = $state('');
  let showAddForm = $state(false);
  let editingProduct = $state<Product | null>(null);
  let generatedBarcode = $state('');
  let searchQuery = $state('');
  let saving = $state(false);

  let formData = $state({
    name: '',
    sku: '',
    barcode: '',
    categoryId: '',
    sellingPrice: '',
    costPrice: '',
    taxRate: '0',
  });

  async function loadData() {
    try {
      loading = true;
      const [productRecords, categoryRecords] = await Promise.all([
        pb.collection('products').getFullList({ expand: 'category', sort: 'name' }),
        pb.collection('categories').getFullList({ sort: 'name' }),
      ]);
      const cats: Category[] = categoryRecords.map((c: any) => ({ id: c.id, name: c.name }));
      categories = cats;
      products = productRecords.map((p: any) => ({
        id: p.id,
        name: p.name,
        sku: p.sku || '',
        barcode: p.barcode || '',
        categoryId: p.category || '',
        category: p.expand?.category?.name || '',
        sellingPrice: p.selling_price || 0,
        costPrice: p.cost_price || 0,
        taxRate: p.tax_rate || 0,
      }));
    } catch (e) {
      errorMsg = 'Failed to load products';
    } finally {
      loading = false;
    }
  }

  onMount(() => {
    loadData();
  });

  function resetForm() {
    formData = {
      name: '',
      sku: '',
      barcode: '',
      categoryId: categories[0]?.id || '',
      sellingPrice: '',
      costPrice: '',
      taxRate: '0',
    };
    editingProduct = null;
    showAddForm = false;
    generatedBarcode = '';
    errorMsg = '';
  }

  function handleGenerateBarcodeClient() {
    if (!editingProduct && !formData.name) return;
    try {
      const prefix = formData.sku || formData.name.substring(0, 3).toUpperCase();
      const newBarcode = `${prefix}${Date.now().toString(36).toUpperCase().slice(-4)}`;
      generatedBarcode = newBarcode;
      formData.barcode = newBarcode;
    } catch {
      const newBarcode = Math.random().toString(36).substring(2, 9).toUpperCase();
      generatedBarcode = newBarcode;
      formData.barcode = newBarcode;
    }
  }

  async function handleGenerateBarcodeForProduct(product: Product) {
    try {
      const result = await customFetch('/barcode/generate', {
        method: 'POST',
        body: JSON.stringify({ product_id: product.id, value: '' }),
      });
      products = products.map((p) => p.id === product.id ? { ...p, barcode: result.barcode } : p);
    } catch (e: any) {
      alert('Failed to generate barcode: ' + e.message);
    }
  }

  function handlePrintBarcode(barcode: string, name: string) {
    alert(`Printing barcode: ${barcode}\nProduct: ${name}\n\nIn production, this would send to a barcode printer.`);
  }

  async function handleSubmit(e: SubmitEvent) {
    e.preventDefault();
    saving = true;
    errorMsg = '';
    try {
      const data = {
        name: formData.name,
        sku: formData.sku,
        barcode: formData.barcode,
        category: formData.categoryId,
        selling_price: Number(formData.sellingPrice),
        cost_price: Number(formData.costPrice),
        tax_rate: Number(formData.taxRate),
      };
      if (editingProduct) {
        await pb.collection('products').update(editingProduct.id, data);
      } else {
        await pb.collection('products').create(data);
      }
      await loadData();
      resetForm();
    } catch (e: any) {
      errorMsg = e.message || 'Failed to save product';
    } finally {
      saving = false;
    }
  }

  function handleEdit(product: Product) {
    editingProduct = product;
    formData = {
      name: product.name,
      sku: product.sku,
      barcode: product.barcode,
      categoryId: product.categoryId,
      sellingPrice: String(product.sellingPrice),
      costPrice: String(product.costPrice),
      taxRate: String(product.taxRate),
    };
    generatedBarcode = product.barcode;
    showAddForm = true;
  }

  async function handleDelete(id: string) {
    if (!confirm('Are you sure you want to delete this product?')) return;
    try {
      await pb.collection('products').delete(id);
      products = products.filter((p) => p.id !== id);
    } catch (e: any) {
      alert('Failed to delete: ' + e.message);
    }
  }

  let filteredProducts = $derived(
    (() => {
      const q = searchQuery.trim().toLowerCase();
      if (!q) return products;
      return products.filter(
        (p) =>
          p.name.toLowerCase().includes(q) ||
          p.category.toLowerCase().includes(q) ||
          p.barcode.toLowerCase().includes(q) ||
          p.sku.toLowerCase().includes(q)
      );
    })()
  );

  const columns: any[] = [
    { header: 'Barcode/SKU', accessor: 'barcode' },
    { header: 'Product Name', accessor: 'name' },
    { header: 'Category', accessor: 'category' },
    { header: 'Selling Price', accessor: 'sellingPrice' },
    { header: 'Cost Price', accessor: 'costPrice' },
    { header: 'Tax', accessor: 'taxRate' },
    { header: 'Actions' },
  ];
</script>

<svelte:head>
  <title>Product Management - My Garments</title>
</svelte:head>

<div class="flex min-h-screen bg-background">
  <ImprovedSidebar {menuItems} userRole="Stock Manager" />

  {#snippet actionButton()}
    <Button icon={showAddForm ? X : Plus} onclick={() => { if (showAddForm) { showAddForm = false; } else { resetForm(); showAddForm = true; } }}>
      {showAddForm ? 'Cancel' : 'Add Product'}
    </Button>
  {/snippet}

  <FluidLayout>
    <PageHeader
      title="Product Management"
      subtitle="Manage product catalog and barcodes"
      icon={ShoppingBag}
      action={actionButton}
    />

    {#if errorMsg}
      <div class="mb-4 flex items-center gap-2 p-3 bg-destructive/10 border border-destructive/30 rounded-lg text-destructive text-sm">
        <AlertCircle class="w-4 h-4" /> {errorMsg}
      </div>
    {/if}

    <!-- Add/Edit Form -->
    {#if showAddForm}
      <div transition:slide={{ duration: 300 }}>
        <Card class="mb-6 md:mb-8">
          <h3 class="mb-6 text-lg md:text-xl">{editingProduct ? 'Edit Product' : 'Add New Product'}</h3>
          <form onsubmit={handleSubmit} class="space-y-6">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <Input label="Product Name" bind:value={formData.name} required />
              <Input label="SKU" bind:value={formData.sku} required />

              <div class="relative w-full mb-6">
                <label class="block mb-2 text-sm text-muted-foreground" for="cat">Category <span class="text-destructive">*</span></label>
                <select
                  id="cat"
                  bind:value={formData.categoryId}
                  class="w-full px-4 py-3 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all"
                  required
                >
                  <option value="">Select category</option>
                  {#each categories as cat}
                    <option value={cat.id}>{cat.name}</option>
                  {/each}
                </select>
              </div>

              <Input label="Selling Price (₹)" type="number" bind:value={formData.sellingPrice} required />
              <Input label="Cost Price (₹)" type="number" bind:value={formData.costPrice} required />
              <Input label="Tax Rate (%)" type="number" bind:value={formData.taxRate} />
            </div>

            <!-- Barcode Section -->
            <Card class="bg-muted/50">
              <h4 class="mb-4 flex items-center gap-2">
                <Barcode class="w-5 h-5 text-primary" />
                Barcode Management
              </h4>
              <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mb-4">
                <Input label="Barcode Number" bind:value={formData.barcode} />
                <div class="flex items-end gap-2">
                  <Button type="button" variant="outline" icon={RefreshCw} onclick={handleGenerateBarcodeClient} class="flex-1">Auto Generate</Button>
                  <Button type="button" variant="secondary" icon={Printer} onclick={() => handlePrintBarcode(formData.barcode, formData.name)} disabled={!formData.barcode}>Print</Button>
                </div>
              </div>
              {#if formData.barcode}
                <div transition:slide={{ duration: 200 }} class="p-4 bg-white border-2 border-primary rounded-lg text-center">
                  <p class="text-xs text-muted-foreground mb-2">Barcode Preview</p>
                  <div class="flex flex-col items-center justify-center gap-2">
                    <Barcode class="w-20 h-20 text-primary" />
                    <p class="font-mono text-xl tracking-wider">{formData.barcode}</p>
                    <p class="text-sm text-muted-foreground">{formData.name || 'Product Name'}</p>
                  </div>
                </div>
              {/if}
            </Card>

            <div class="flex gap-3">
              <Button type="submit" disabled={saving}>{saving ? 'Saving…' : editingProduct ? 'Update Product' : 'Add Product'}</Button>
              <Button type="button" variant="outline" onclick={resetForm}>Cancel</Button>
            </div>
          </form>
        </Card>
      </div>
    {/if}

    <!-- Products Table -->
    <Card>
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-5">
        <h3 class="text-lg md:text-xl">
          All Products
          <span class="ml-2 text-sm font-normal text-muted-foreground">
            ({filteredProducts.length}{searchQuery ? ` of ${products.length}` : ''})
          </span>
        </h3>
        <div class="relative w-full sm:w-72">
          <Search class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground pointer-events-none" />
          <input
            type="text"
            bind:value={searchQuery}
            placeholder="Search by name, SKU or category…"
            class="w-full pl-9 pr-9 py-2 text-sm border border-border rounded-full bg-muted/40 outline-none focus:ring-2 focus:ring-ring transition-all"
          />
          {#if searchQuery}
            <button onclick={() => searchQuery = ''} class="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground transition-colors">
              <X class="w-3.5 h-3.5" />
            </button>
          {/if}
        </div>
      </div>

      {#if loading}
        <LoadingSpinner />
      {:else if filteredProducts.length === 0}
        <div class="text-center py-12 text-muted-foreground">
          <Search class="w-10 h-10 mx-auto mb-3 opacity-30" />
          <p class="text-sm">{searchQuery ? `No products match "${searchQuery}"` : 'No products yet. Add your first product above.'}</p>
        </div>
      {:else}
        {#snippet cell(row: any, column: any)}
          {#if column.header === 'Barcode/SKU'}
            <div class="flex items-center gap-2">
              <Barcode class="w-4 h-4 text-primary shrink-0" />
              <span class="font-mono text-sm">{row.barcode || row.sku}</span>
            </div>
          {:else if column.header === 'Category'}
            <span class="px-2 py-1 bg-primary/10 text-primary rounded text-sm">{row.category}</span>
          {:else if column.header === 'Selling Price'}
            <span>₹{row.sellingPrice.toLocaleString()}</span>
          {:else if column.header === 'Cost Price'}
            <span>₹{row.costPrice.toLocaleString()}</span>
          {:else if column.header === 'Tax'}
            <span>{row.taxRate}%</span>
          {:else if column.header === 'Actions'}
            <div class="flex gap-2">
              <button onclick={() => handleEdit(row)} class="p-2 hover:bg-muted rounded transition-colors" title="Edit">
                <Edit class="w-4 h-4 text-primary" />
              </button>
              <button onclick={() => handleGenerateBarcodeForProduct(row)} class="p-2 hover:bg-muted rounded transition-colors" title="Generate Barcode from Server">
                <RefreshCw class="w-4 h-4 text-secondary" />
              </button>
              <button onclick={() => handlePrintBarcode(row.barcode || row.sku, row.name)} class="p-2 hover:bg-muted rounded transition-colors" title="Print Barcode">
                <Printer class="w-4 h-4 text-secondary" />
              </button>
              <button onclick={() => handleDelete(row.id)} class="p-2 hover:bg-muted rounded transition-colors" title="Delete">
                <Trash2 class="w-4 h-4 text-destructive" />
              </button>
            </div>
          {:else}
            {row[column.accessor]}
          {/if}
        {/snippet}

        <DataTable
          data={filteredProducts}
          {columns}
          {cell}
        />
      {/if}
    </Card>
  </FluidLayout>
</div>
