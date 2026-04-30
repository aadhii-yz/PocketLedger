<script lang="ts">
  import ImprovedSidebar from "$lib/components/ImprovedSidebar.svelte";
  import FluidLayout from "$lib/components/FluidLayout.svelte";
  import Card from "$lib/components/Card.svelte";
  import Button from "$lib/components/Button.svelte";
  import Input from "$lib/components/Input.svelte";
  import DataTable from "$lib/components/DataTable.svelte";
  import PageHeader from "$lib/components/PageHeader.svelte";
  import LoadingSpinner from "$lib/components/LoadingSpinner.svelte";
  import {
    Users as UsersIcon,
    Activity,
    Plus,
    X,
    Edit,
    Trash2,
    Mail,
    Shield,
    AlertCircle,
  } from "lucide-svelte";
  import { pb } from "$lib/pb";
  import { onMount } from "svelte";
  import { slide } from "svelte/transition";

  const menuItems = [
    { label: "Users", icon: UsersIcon, path: "/admin/users" },
    { label: "System Logs", icon: Activity, path: "/admin/logs" },
  ];

  interface SystemUser {
    id: string;
    email: string;
    role: "admin" | "manager" | "pos" | "stock_entry";
    fullName: string;
    assignedShop: string;
    assignedShopName: string;
    isActive: boolean;
    createdAt: string;
  }

  interface Shop {
    id: string;
    name: string;
  }

  let users = $state<SystemUser[]>([]);
  let shops = $state<Shop[]>([]);
  let loading = $state(true);
  let showAddForm = $state(false);
  let editingUser = $state<SystemUser | null>(null);
  let saving = $state(false);
  let errorMsg = $state("");

  let formData = $state({
    email: "",
    fullName: "",
    role: "pos" as SystemUser["role"],
    password: "",
    assignedShop: "",
  });

  async function loadUsers() {
    try {
      loading = true;
      const [records, shopRecords] = await Promise.all([
        pb.collection("users").getFullList({ sort: "created" }),
        pb.collection("locations").getFullList({ filter: "type = 'shop'", sort: "name" }),
      ]);
      shops = shopRecords.map((s: any) => ({ id: s.id, name: s.name }));
      const shopMap = new Map(shops.map((s) => [s.id, s.name]));
      users = records.map((r: any) => ({
        id: r.id,
        email: r.email || "",
        role: r.role || "pos",
        fullName: r.name || "",
        assignedShop: r.assigned_shop || "",
        assignedShopName: shopMap.get(r.assigned_shop) || "—",
        isActive: r.verified !== false,
        createdAt: r.created ? r.created.split(" ")[0] : "",
      }));
    } catch {
      errorMsg = "Failed to load users";
    } finally {
      loading = false;
    }
  }

  onMount(() => {
    loadUsers();
  });

  function resetForm() {
    formData = {
      email: "",
      fullName: "",
      role: "pos",
      password: "",
      assignedShop: "",
    };
    editingUser = null;
    showAddForm = false;
    errorMsg = "";
  }

  async function handleSubmit(e: SubmitEvent) {
    e.preventDefault();
    saving = true;
    errorMsg = "";
    try {
      const needsShop = formData.role === "pos" || formData.role === "stock_entry";
      if (editingUser) {
        const data: any = {
          email: formData.email,
          name: formData.fullName,
          role: formData.role,
          assigned_shop: needsShop ? formData.assignedShop || null : null,
        };
        if (formData.password) {
          data.password = formData.password;
          data.passwordConfirm = formData.password;
        }
        await pb.collection("users").update(editingUser.id, data);
      } else {
        await pb.collection("users").create({
          email: formData.email,
          name: formData.fullName,
          role: formData.role,
          assigned_shop: needsShop ? formData.assignedShop || null : null,
          password: formData.password,
          passwordConfirm: formData.password,
        });
      }
      await loadUsers();
      resetForm();
    } catch (e: any) {
      errorMsg = e.message || "Failed to save user";
    } finally {
      saving = false;
    }
  }

  function handleEdit(user: SystemUser) {
    editingUser = user;
    formData = {
      email: user.email,
      fullName: user.fullName,
      role: user.role,
      password: "",
      assignedShop: user.assignedShop,
    };
    showAddForm = true;
  }

  async function handleDelete(id: string) {
    if (!confirm("Are you sure you want to delete this user?")) return;
    try {
      await pb.collection("users").delete(id);
      users = users.filter((u) => u.id !== id);
    } catch (e: any) {
      alert("Failed to delete: " + e.message);
    }
  }

  const roleLabel: Record<string, string> = {
    admin: "Admin",
    manager: "Manager",
    pos: "POS / Billing",
    stock_entry: "Stock Entry",
  };

  const columns: any[] = [
    { header: "Full Name", accessor: "fullName" },
    { header: "Email", accessor: "email" },
    { header: "Role", accessor: "role" },
    { header: "Assigned Shop", accessor: "assignedShopName" },
    { header: "Created", accessor: "createdAt" },
    { header: "Actions" },
  ];
</script>

<svelte:head>
  <title>User Management - My Garments</title>
</svelte:head>

<div class="flex min-h-screen bg-background">
  <ImprovedSidebar {menuItems} userRole="Admin" />

  {#snippet actionButton()}
    <Button
      icon={showAddForm ? X : Plus}
      onclick={() => {
        if (showAddForm) {
          showAddForm = false;
        } else {
          resetForm();
          showAddForm = true;
        }
      }}
    >
      {showAddForm ? "Cancel" : "Add User"}
    </Button>
  {/snippet}

  <FluidLayout>
    <PageHeader
      title="User Management"
      subtitle="Manage system users and permissions"
      icon={UsersIcon}
      action={actionButton}
    />

    {#if errorMsg}
      <div
        class="mb-4 flex items-center gap-2 p-3 bg-destructive/10 border border-destructive/30 rounded-lg text-destructive text-sm"
      >
        <AlertCircle class="w-4 h-4" />
        {errorMsg}
      </div>
    {/if}

    {#if showAddForm}
      <div transition:slide={{ duration: 300 }}>
        <Card class="mb-8">
          <h3 class="mb-6">{editingUser ? "Edit User" : "Add New User"}</h3>
          <form onsubmit={handleSubmit} class="space-y-4">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <Input
                label="Email"
                type="email"
                bind:value={formData.email}
                required
              >
                {#snippet icon()}
                  <Mail class="w-5 h-5" />
                {/snippet}
              </Input>

              <Input
                label="Full Name"
                bind:value={formData.fullName}
                required
              />

              <div class="relative w-full">
                <label class="block mb-2 text-muted-foreground" for="roleSelect"
                  >Role <span class="text-destructive">*</span></label
                >
                <select
                  id="roleSelect"
                  bind:value={formData.role}
                  class="w-full px-4 py-3 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all"
                  required
                >
                  <option value="admin">Admin</option>
                  <option value="manager">Manager</option>
                  <option value="pos">POS / Billing</option>
                  <option value="stock_entry">Stock Entry</option>
                </select>
              </div>

              {#if formData.role === 'pos' || formData.role === 'stock_entry'}
                <div class="relative w-full">
                  <label class="block mb-2 text-muted-foreground" for="shopSelect">
                    Assigned Shop
                  </label>
                  <select
                    id="shopSelect"
                    bind:value={formData.assignedShop}
                    class="w-full px-4 py-3 bg-input-background border border-border rounded-lg outline-none focus:ring-2 focus:ring-ring transition-all"
                  >
                    <option value="">-- None --</option>
                    {#each shops as shop}
                      <option value={shop.id}>{shop.name}</option>
                    {/each}
                  </select>
                </div>
              {/if}

              <Input
                label={editingUser
                  ? "New Password (leave blank to keep current)"
                  : "Password"}
                type="password"
                bind:value={formData.password}
                required={!editingUser}
              />
            </div>

            <div class="flex gap-3">
              <Button type="submit" disabled={saving}
                >{saving
                  ? "Saving…"
                  : editingUser
                    ? "Update User"
                    : "Add User"}</Button
              >
              <Button type="button" variant="outline" onclick={resetForm}
                >Cancel</Button
              >
            </div>
          </form>
        </Card>
      </div>
    {/if}

    <Card>
      <h3 class="mb-4">All Users ({users.length})</h3>
      {#if loading}
        <LoadingSpinner />
      {:else}
        {#snippet cell(row: any, column: any)}
          {#if column.header === "Email"}
            <span class="text-muted-foreground font-mono text-sm"
              >{row.email}</span
            >
          {:else if column.header === "Role"}
            <div class="flex items-center gap-2">
              <Shield class="w-4 h-4 text-primary" />
              <span
                class="capitalize px-2 py-1 bg-primary/10 text-primary rounded"
                >{roleLabel[row.role] || row.role}</span
              >
            </div>
          {:else if column.header === "Actions"}
            <div class="flex gap-2">
              <button
                onclick={() => handleEdit(row)}
                class="p-2 hover:bg-muted rounded transition-colors"
              >
                <Edit class="w-4 h-4 text-primary" />
              </button>
              <button
                onclick={() => handleDelete(row.id)}
                disabled={row.role === "admin" &&
                  users.filter((u) => u.role === "admin").length === 1}
                class="p-2 hover:bg-muted rounded transition-colors"
              >
                <Trash2
                  class="w-4 h-4 {row.role === 'admin' &&
                  users.filter((u) => u.role === 'admin').length === 1
                    ? 'text-muted-foreground'
                    : 'text-destructive'}"
                />
              </button>
            </div>
          {:else}
            {row[column.accessor]}
          {/if}
        {/snippet}

        <DataTable data={users} {columns} {cell} />
      {/if}
    </Card>
  </FluidLayout>
</div>
