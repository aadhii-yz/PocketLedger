<script lang="ts">
  import { ShoppingBag, Mail, Lock } from "lucide-svelte";
  import { goto } from "$app/navigation";
  import { pb, mapRole } from "$lib/pb";
  import { fade, fly } from "svelte/transition";

  let email = $state("");
  let password = $state("");
  let error = $state("");
  let loading = $state(false);
  let showPassword = $state(false);

  async function handleLogin(e: SubmitEvent) {
    e.preventDefault();
    loading = true;
    error = "";
    try {
      const authData = await pb
        .collection("users")
        .authWithPassword(email, password);
      const role = mapRole(authData.record["role"]);
      switch (role) {
        case "admin":
          await goto("/admin");
          break;
        case "manager":
          await goto("/manager");
          break;
        case "billing":
          await goto("/billing");
          break;
        case "stock":
          await goto("/stock/products");
          break;
      }
    } catch {
      error = "Invalid email or password. Please try again.";
    } finally {
      loading = false;
    }
  }

  function handleFocus(e: Event) {
    const el = e.target as HTMLElement;
    el.style.borderColor = "#8B2635";
    el.style.boxShadow = "0 0 0 3px rgba(139,38,53,0.08)";
    el.style.background = "#fff";
  }

  function handleBlur(e: Event) {
    const el = e.target as HTMLElement;
    el.style.borderColor = error ? "#ef4444" : "#e5e7eb";
    el.style.boxShadow = "none";
    el.style.background = "#f9fafb";
  }
</script>

<svelte:head>
  <title>Login - My Garments</title>
</svelte:head>

<div
  class="min-h-screen flex items-center justify-center p-4"
  style="background: linear-gradient(135deg, #f8f7f4 0%, #f0ede8 60%, #f8f7f4 100%)"
>
  <div
    in:fly={{ y: 20, duration: 380, delay: 100 }}
    class="w-full"
    style="max-width: 400px;"
  >
    <div
      class="bg-white rounded-2xl p-8"
      style="box-shadow: 0 4px 32px rgba(0,0,0,0.08), 0 1px 4px rgba(0,0,0,0.04); border: 1px solid rgba(0,0,0,0.07);"
    >
      <div class="text-center mb-8">
        <div
          class="w-14 h-14 rounded-2xl flex items-center justify-center mx-auto mb-4"
          style="background: linear-gradient(135deg, #8B2635 0%, #b8892a 100%)"
        >
          <ShoppingBag class="w-7 h-7 text-white" />
        </div>
        <h1 class="text-2xl font-semibold text-gray-900 mb-1 tracking-tight">
          My Garments
        </h1>
        <p class="text-sm text-gray-500">Sign in to your account</p>
      </div>

      <form onsubmit={handleLogin} class="space-y-4">
        <div>
          <label
            class="block text-sm font-medium text-gray-700 mb-1.5"
            for="email">Email address</label
          >
          <div class="relative">
            <Mail
              class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400 pointer-events-none"
            />
            <input
              id="email"
              type="email"
              bind:value={email}
              oninput={() => (error = "")}
              onfocus={handleFocus}
              onblur={handleBlur}
              placeholder="you@mygarments.com"
              required
              class="w-full pl-9 pr-4 py-2.5 text-sm border border-gray-200 rounded-lg outline-none transition-all bg-gray-50 text-gray-900 placeholder-gray-400"
              style="font-size: 14px;"
            />
          </div>
        </div>

        <div>
          <label
            class="block text-sm font-medium text-gray-700 mb-1.5"
            for="password">Password</label
          >
          <div class="relative">
            <Lock
              class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400 pointer-events-none"
            />
            <input
              id="password"
              type={showPassword ? "text" : "password"}
              bind:value={password}
              oninput={() => (error = "")}
              onfocus={handleFocus}
              onblur={handleBlur}
              placeholder="Enter your password"
              required
              class="w-full pl-9 pr-14 py-2.5 text-sm border border-gray-200 rounded-lg outline-none transition-all bg-gray-50 text-gray-900 placeholder-gray-400"
              style="font-size: 14px;"
            />
            <button
              type="button"
              onclick={() => (showPassword = !showPassword)}
              class="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-gray-400 hover:text-gray-600 transition-colors font-medium"
            >
              {showPassword ? "Hide" : "Show"}
            </button>
          </div>
        </div>

        {#if error}
          <p
            in:fly={{ y: -6, duration: 200 }}
            class="text-sm text-red-600 bg-red-50 border border-red-100 rounded-lg px-3 py-2.5"
          >
            {error}
          </p>
        {/if}

        <button
          type="submit"
          disabled={loading}
          class="w-full py-2.5 px-4 text-sm font-semibold text-white rounded-lg transition-opacity mt-1 disabled:opacity-60 hover:opacity-90"
          style="background: linear-gradient(135deg, #8B2635 0%, #a03040 100%)"
        >
          {loading ? "Signing in…" : "Sign in"}
        </button>
      </form>
    </div>

    <p class="text-center text-xs text-gray-400 mt-5">
      My Garments · Textile Shop Management System
    </p>
  </div>
</div>
