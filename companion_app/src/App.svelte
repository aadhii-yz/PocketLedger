<script lang="ts">
  import { invoke } from '@tauri-apps/api/core';
  import { onMount } from 'svelte';

  interface Settings {
    pocketledger_url: string;
    barcode_ip: string;
    barcode_port: number;
    receipt_ip: string;
    receipt_port: number;
    server_port: number;
  }

  let settings: Settings = $state({
    pocketledger_url: '',
    barcode_ip: '',
    barcode_port: 9100,
    receipt_ip: '',
    receipt_port: 9100,
    server_port: 8765,
  });

  let saving = $state(false);
  let saved = $state(false);
  let error = $state('');

  const isAndroid = typeof navigator !== 'undefined' && navigator.userAgent.includes('Android');

  onMount(async () => {
    try {
      settings = await invoke<Settings>('get_settings');
    } catch (e) {
      console.error('Failed to load settings:', e);
    }
    if (isAndroid) {
      invoke('plugin:print|startService').catch(() => {});
    }
  });

  async function save() {
    saving = true;
    error = '';
    try {
      await invoke('save_settings', { settings });
      saved = true;
      setTimeout(() => (saved = false), 2000);
    } catch (e) {
      error = String(e);
    } finally {
      saving = false;
    }
  }
</script>

<div class="shell">
  <header>
    <h1>PocketLedger Companion</h1>
    <p class="subtitle">Print server running on localhost:{settings.server_port}</p>
  </header>

  <form onsubmit={(e) => { e.preventDefault(); save(); }}>
    <section>
      <h2>App</h2>
      <div class="field">
        <label for="url">PocketLedger URL</label>
        <input
          id="url"
          type="url"
          placeholder="https://your-app.pockethost.io"
          bind:value={settings.pocketledger_url}
        />
      </div>
    </section>

    <section>
      <h2>Barcode Printer (TVS LP 46 dlite)</h2>
      <div class="row">
        <div class="field grow">
          <label for="barcode-ip">IP Address</label>
          <input
            id="barcode-ip"
            type="text"
            placeholder="192.168.1.100"
            bind:value={settings.barcode_ip}
          />
        </div>
        <div class="field port">
          <label for="barcode-port">Port</label>
          <input
            id="barcode-port"
            type="number"
            min="1"
            max="65535"
            bind:value={settings.barcode_port}
          />
        </div>
      </div>
    </section>

    <section>
      <h2>Receipt Printer (TVS RP 3230)</h2>
      <div class="row">
        <div class="field grow">
          <label for="receipt-ip">IP Address</label>
          <input
            id="receipt-ip"
            type="text"
            placeholder="192.168.1.101"
            bind:value={settings.receipt_ip}
          />
        </div>
        <div class="field port">
          <label for="receipt-port">Port</label>
          <input
            id="receipt-port"
            type="number"
            min="1"
            max="65535"
            bind:value={settings.receipt_port}
          />
        </div>
      </div>
    </section>

    {#if error}
      <p class="error">{error}</p>
    {/if}

    <div class="actions">
      <button type="submit" class="primary" disabled={saving}>
        {saving ? 'Saving…' : saved ? 'Saved!' : 'Save Settings'}
      </button>
    </div>
  </form>

  {#if settings.pocketledger_url}
    <section class="launch">
      <h2>Launch</h2>
      <div class="launch-buttons">
        <button
          class="launch-btn"
          onclick={() => { window.location.href = settings.pocketledger_url + '/billing?companion=1'; }}
        >
          Open Billing
        </button>
        <button
          class="launch-btn"
          onclick={() => { window.location.href = settings.pocketledger_url + '/stock/inventory?companion=1'; }}
        >
          Open Stock Entry
        </button>
      </div>
    </section>
  {/if}
</div>

<style>
  .shell {
    max-width: 440px;
    margin: 0 auto;
    padding: 24px 20px;
  }

  header {
    margin-bottom: 24px;
  }

  h1 {
    font-size: 18px;
    font-weight: 700;
    color: #1e40af;
  }

  .subtitle {
    font-size: 12px;
    color: #64748b;
    margin-top: 2px;
  }

  h2 {
    font-size: 13px;
    font-weight: 600;
    color: #475569;
    margin-bottom: 10px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  section {
    background: #fff;
    border: 1px solid #e2e8f0;
    border-radius: 8px;
    padding: 14px 16px;
    margin-bottom: 12px;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 4px;
    margin-bottom: 10px;
  }

  .field:last-child {
    margin-bottom: 0;
  }

  .row {
    display: flex;
    gap: 10px;
  }

  .grow { flex: 1; }
  .port { width: 90px; }

  .actions {
    margin-top: 16px;
    display: flex;
    justify-content: flex-end;
  }

  .error {
    font-size: 13px;
    color: #dc2626;
    background: #fef2f2;
    border: 1px solid #fecaca;
    border-radius: 6px;
    padding: 8px 12px;
    margin-bottom: 12px;
  }

  .launch {
    margin-top: 12px;
  }

  .launch-buttons {
    display: flex;
    gap: 8px;
  }

  .launch-btn {
    flex: 1;
    padding: 10px 16px;
    font-size: 14px;
    font-weight: 600;
    color: #1e40af;
    background: #eff6ff;
    border: 1px solid #bfdbfe;
    border-radius: 8px;
    cursor: pointer;
    transition: background 0.15s;
  }

  .launch-btn:hover {
    background: #dbeafe;
  }
</style>
