import { pb, PB_URL } from './pb';
import type { PrintSettings } from '$lib/schemas';

export type { PrintSettings } from '$lib/schemas';

export interface BillPrintItem {
  name: string;
  qty: number;
  unit_price: number;
  tax_rate: number;
}

export interface BillPrintData {
  bill_number: string;
  shop_name: string;
  date: Date;
  items: BillPrintItem[];
  subtotal: number;
  tax_total: number;
  discount: number;
  grand_total: number;
  payment_method: string;
  customer_name?: string;
  customer_phone?: string;
}

const defaultSettings: PrintSettings = {
  shop_name: '',
  shop_address: '',
  shop_phone: '',
  gst_number: '',
  receipt_footer: 'Thank you for your purchase!',
  show_customer_info: true,
  show_tax_breakdown: true,
  barcode_show_sku: true,
  barcode_show_price: true,
  receipt_printer: '',
  label_printer: '',
};

export async function loadPrintSettings(): Promise<PrintSettings> {
  try {
    const result = await pb.collection('print_settings').getList(1, 1);
    if (result.totalItems > 0) {
      const r = result.items[0];
      return {
        shop_name: r['shop_name'] ?? '',
        shop_address: r['shop_address'] ?? '',
        shop_phone: r['shop_phone'] ?? '',
        gst_number: r['gst_number'] ?? '',
        receipt_footer: r['receipt_footer'] ?? '',
        show_customer_info: r['show_customer_info'] !== false,
        show_tax_breakdown: r['show_tax_breakdown'] !== false,
        barcode_show_sku: r['barcode_show_sku'] !== false,
        barcode_show_price: r['barcode_show_price'] !== false,
        receipt_printer: r['receipt_printer'] ?? '',
        label_printer: r['label_printer'] ?? '',
      };
    }
  } catch {
    // fall through to defaults
  }
  return { ...defaultSettings };
}

// ── QZ Tray ───────────────────────────────────────────────────────────────────
// QZ Tray must have "Allow unsigned content" enabled in its Advanced settings
// for the unsigned security setup below to work.

import type * as QZTray from 'qz-tray';

let _qz: typeof QZTray | null = null;
let _qzConnectPromise: Promise<boolean> | null = null;

async function loadQZ(): Promise<typeof QZTray | null> {
  if (_qz) return _qz;
  try {
    _qz = await import('qz-tray');
    _qz.security.setCertificatePromise((resolve) => resolve(''));
    _qz.security.setSignatureAlgorithm('SHA512');
    _qz.security.setSignaturePromise(() => (resolve) => resolve(''));
    return _qz;
  } catch {
    return null;
  }
}

async function getQZConnection(): Promise<typeof QZTray | null> {
  const qz = await loadQZ();
  if (!qz) return null;

  if (qz.websocket.isActive()) return qz;

  if (_qzConnectPromise) {
    return (await _qzConnectPromise) ? qz : null;
  }

  _qzConnectPromise = (async () => {
    try {
      await Promise.race([
        qz.websocket.connect(),
        new Promise<never>((_, reject) =>
          setTimeout(() => reject(new Error('QZ timeout')), 2000)
        ),
      ]);
      return true;
    } catch {
      _qzConnectPromise = null;
      return false;
    }
  })();

  return (await _qzConnectPromise) ? qz : null;
}

async function printRawViaQZ(data: Uint8Array, printerName: string): Promise<boolean> {
  try {
    const qz = await getQZConnection();
    if (!qz) { console.warn('[print] QZ Tray not connected'); return false; }
    const found = await qz.printers.find(printerName);
    const printer: string = Array.isArray(found) ? found[0] : found;
    if (!printer) { console.warn('[print] Printer not found:', printerName); return false; }
    const config = qz.configs.create(printer, { forceRaw: true });
    // Binary ESC/POS data must be base64-encoded — 'plain' flavor can't carry binary over JSON/WebSocket
    let binary = '';
    for (let i = 0; i < data.length; i++) binary += String.fromCharCode(data[i]);
    const b64 = btoa(binary);
    await qz.print(config, [{ type: 'raw', format: 'command', flavor: 'base64', data: b64 }]);
    return true;
  } catch (err) {
    console.error('[print] QZ raw print failed:', err);
    return false;
  }
}

async function printHtmlViaQZ(html: string, printerName: string): Promise<boolean> {
  try {
    const qz = await getQZConnection();
    if (!qz) return false;
    const found = await qz.printers.find(printerName);
    const printer: string = Array.isArray(found) ? found[0] : found;
    if (!printer) return false;
    const config = qz.configs.create(printer);
    await qz.print(config, [{ type: 'pixel', format: 'html', flavor: 'file', data: html }]);
    return true;
  } catch {
    return false;
  }
}

export async function listQZPrinters(): Promise<string[]> {
  try {
    const qz = await getQZConnection();
    if (!qz) return [];
    const found = await qz.printers.find('');
    return Array.isArray(found) ? found : found ? [found] : [];
  } catch {
    return [];
  }
}

// ── ESC/POS ───────────────────────────────────────────────────────────────────

const E = {
  INIT: [0x1b, 0x40],
  CENTER: [0x1b, 0x61, 0x01],
  LEFT: [0x1b, 0x61, 0x00],
  BOLD_ON: [0x1b, 0x45, 0x01],
  BOLD_OFF: [0x1b, 0x45, 0x00],
  DBLW_ON: [0x1b, 0x21, 0x20],
  DBLW_OFF: [0x1b, 0x21, 0x00],
  CUT: [0x1d, 0x56, 0x00],
  LF: [0x0a],
};

class EscPos {
  private buf: number[] = [];

  cmd(...bytes: number[][]): this { bytes.forEach(b => this.buf.push(...b)); return this; }

  txt(s: string): this {
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      this.buf.push(c < 128 ? c : 0x3f);
    }
    return this;
  }

  line(s = ''): this { return this.txt(s).cmd(E.LF); }

  sep(width = 42): this { return this.line('-'.repeat(width)); }

  build(): Uint8Array { return new Uint8Array(this.buf); }
}

const COL = 42;

function rpad(s: string, w: number): string { return s.slice(0, w).padEnd(w); }
function lpad(s: string, w: number): string { return s.slice(0, w).padStart(w); }

function buildReceiptEscPos(bill: BillPrintData, settings: PrintSettings): Uint8Array {
  const shopName = settings.shop_name || bill.shop_name || 'Shop';
  const p = new EscPos();

  p.cmd(E.INIT);

  // Header
  p.cmd(E.CENTER, E.BOLD_ON, E.DBLW_ON).line(shopName.slice(0, 21)).cmd(E.DBLW_OFF, E.BOLD_OFF);
  if (settings.shop_address) p.cmd(E.CENTER).line(settings.shop_address);
  if (settings.shop_phone) p.cmd(E.CENTER).line('Ph: ' + settings.shop_phone);
  if (settings.gst_number) p.cmd(E.CENTER).line('GST: ' + settings.gst_number);

  p.cmd(E.LEFT).sep();
  p.line('Date   : ' + fmtDate(bill.date));
  p.line('Bill No: ' + bill.bill_number);
  p.sep();

  // Items header  (20 | 4 | 9 | 9 = 42)
  const NW = 20, QW = 4, RW = 9, AW = 9;
  p.cmd(E.BOLD_ON).txt(rpad('Item', NW)).txt(lpad('Qty', QW)).txt(lpad('Rate', RW)).line(lpad('Amt', AW)).cmd(E.BOLD_OFF);
  p.sep();

  for (const item of bill.items) {
    const name = item.name.length > NW ? item.name.slice(0, NW - 1) + '>' : item.name;
    const total = item.unit_price * item.qty;
    p.txt(rpad(name, NW)).txt(lpad(String(item.qty), QW)).txt(lpad(fmt(item.unit_price), RW)).line(lpad(fmt(total), AW));
  }

  p.sep();

  // Totals
  const LW = COL - 10;
  if (settings.show_tax_breakdown) {
    p.txt(rpad('Subtotal', LW)).line(lpad('Rs.' + fmt(bill.subtotal), 10));
    p.txt(rpad('GST', LW)).line(lpad('Rs.' + fmt(bill.tax_total), 10));
    if (bill.discount > 0)
      p.txt(rpad('Discount', LW)).line(lpad('-Rs.' + fmt(bill.discount), 10));
  }
  p.cmd(E.BOLD_ON).txt(rpad('TOTAL', LW)).line(lpad('Rs.' + fmt(bill.grand_total), 10)).cmd(E.BOLD_OFF);

  p.sep();
  p.line('Payment: ' + bill.payment_method.toUpperCase());

  if (settings.show_customer_info && (bill.customer_name || bill.customer_phone)) {
    const cust = [bill.customer_name, bill.customer_phone].filter(Boolean).join(' / ');
    p.sep().line('Customer: ' + cust);
  }

  if (settings.receipt_footer) {
    p.sep().cmd(E.CENTER).line(settings.receipt_footer);
  }

  p.cmd(E.LEFT).line().line().line().cmd(E.CUT);
  return p.build();
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmt(n: number): string {
  return n.toFixed(2);
}

function fmtDate(d: Date): string {
  return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
}

function esc(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function blobToDataUrl(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => resolve(reader.result as string);
    reader.onerror = reject;
    reader.readAsDataURL(blob);
  });
}

function openPrintWindow(html: string): void {
  const blob = new Blob([html], { type: 'text/html' });
  const url = URL.createObjectURL(blob);
  const win = window.open(url, '_blank', 'width=400,height=600');
  if (!win) {
    URL.revokeObjectURL(url);
    return;
  }
  win.addEventListener('load', () => {
    win.print();
    win.close();
    URL.revokeObjectURL(url);
  });
  setTimeout(() => {
    if (!win.closed) {
      win.print();
      win.close();
      URL.revokeObjectURL(url);
    }
  }, 1500);
}

// ── Receipt ───────────────────────────────────────────────────────────────────

function buildReceiptHtml(bill: BillPrintData, settings: PrintSettings): string {
  const shopName = settings.shop_name || bill.shop_name || 'Shop';
  const payLabel = bill.payment_method.toUpperCase();

  const itemRows = bill.items
    .map((item) => {
      const lineTotal = item.unit_price * item.qty;
      const name = item.name.length > 20 ? item.name.slice(0, 19) + '…' : item.name;
      return `<tr>
      <td class="item-name">${esc(name)}</td>
      <td class="num">${item.qty}</td>
      <td class="num">${fmt(item.unit_price)}</td>
      <td class="num">${fmt(lineTotal)}</td>
    </tr>`;
    })
    .join('');

  const taxRows = settings.show_tax_breakdown
    ? `<tr><td>Subtotal</td><td class="num">&#8377;${fmt(bill.subtotal)}</td></tr>
       <tr><td>GST</td><td class="num">&#8377;${fmt(bill.tax_total)}</td></tr>
       ${bill.discount > 0 ? `<tr><td>Discount</td><td class="num">-&#8377;${fmt(bill.discount)}</td></tr>` : ''}`
    : '';

  const customerRow =
    settings.show_customer_info && (bill.customer_name || bill.customer_phone)
      ? `<div class="divider"></div>
       <p>Customer: ${esc(bill.customer_name || '')}${bill.customer_phone ? ' / ' + esc(bill.customer_phone) : ''}</p>`
      : '';

  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>${esc(bill.bill_number)}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: 'Courier New', Courier, monospace;
    font-size: 11px;
    width: 80mm;
    padding: 4mm 3mm;
    color: #000;
  }
  .shop-name { font-size: 15px; font-weight: bold; text-align: center; margin-bottom: 2px; }
  .center { text-align: center; }
  .divider { border-top: 1px dashed #000; margin: 4px 0; }
  table { width: 100%; border-collapse: collapse; }
  td { padding: 1px 0; vertical-align: top; }
  .num { text-align: right; white-space: nowrap; }
  th { text-align: left; font-size: 10px; border-bottom: 1px solid #000; }
  th.num { text-align: right; }
  .item-name { max-width: 130px; }
  .totals td { padding: 1px 0; }
  .grand td { font-weight: bold; font-size: 13px; border-top: 1px solid #000; padding-top: 2px; }
  .footer { text-align: center; margin-top: 6px; font-size: 10px; }
  @page { margin: 0; size: 80mm auto; }
  @media print { html, body { width: 80mm; } }
</style>
</head>
<body>
  <p class="shop-name">${esc(shopName)}</p>
  ${settings.shop_address ? `<p class="center">${esc(settings.shop_address)}</p>` : ''}
  ${settings.shop_phone ? `<p class="center">Ph: ${esc(settings.shop_phone)}</p>` : ''}
  ${settings.gst_number ? `<p class="center">GST: ${esc(settings.gst_number)}</p>` : ''}
  <div class="divider"></div>
  <p>Date: ${fmtDate(bill.date)}</p>
  <p>Bill No: ${esc(bill.bill_number)}</p>
  <div class="divider"></div>
  <table>
    <thead>
      <tr>
        <th>Item</th>
        <th class="num">Qty</th>
        <th class="num">Rate</th>
        <th class="num">Amt</th>
      </tr>
    </thead>
    <tbody>${itemRows}</tbody>
  </table>
  <div class="divider"></div>
  <table class="totals">
    ${taxRows}
    <tr class="grand"><td>TOTAL</td><td class="num">&#8377;${fmt(bill.grand_total)}</td></tr>
  </table>
  <div class="divider"></div>
  <p>Payment: ${payLabel}</p>
  ${customerRow}
  ${settings.receipt_footer ? `<div class="divider"></div><p class="footer">${esc(settings.receipt_footer)}</p>` : ''}
</body>
</html>`;
}

// ── Companion app (Tauri IPC + HTTP fallback) ─────────────────────────────────

type TauriCore = { invoke: (cmd: string, args?: Record<string, unknown>) => Promise<unknown> };

function tauriCore(): TauriCore | null {
  return (window as unknown as { __TAURI__?: { core: TauriCore } }).__TAURI__?.core ?? null;
}

async function companionAvailable(): Promise<boolean> {
  try {
    const res = await fetch('http://localhost:8765/status', { signal: AbortSignal.timeout(800) });
    return res.ok;
  } catch {
    return false;
  }
}

async function _companionPrintReceipt(
  bill: BillPrintData,
  settings: PrintSettings
): Promise<boolean> {
  try {
    const res = await fetch('http://localhost:8765/print/receipt', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(_receiptPayload(bill, settings)),
      signal: AbortSignal.timeout(5000),
    });
    return res.ok;
  } catch (e) {
    console.warn('[print] companion HTTP receipt failed:', e);
    return false;
  }
}

async function _companionPrintBarcode(
  product: Parameters<typeof printBarcode>[0],
  settings: PrintSettings
): Promise<boolean> {
  try {
    const res = await fetch('http://localhost:8765/print/barcode', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        name: product.name,
        barcode: product.barcode,
        sku: product.sku,
        selling_price: product.selling_price,
        show_sku: settings.barcode_show_sku,
        show_price: settings.barcode_show_price,
        shop_name: settings.shop_name,
        details: product.details ?? {},
      }),
      signal: AbortSignal.timeout(5000),
    });
    return res.ok;
  } catch (e) {
    console.warn('[print] companion HTTP barcode failed:', e);
    return false;
  }
}

function _receiptPayload(bill: BillPrintData, settings: PrintSettings) {
  return {
    shop_name: settings.shop_name || bill.shop_name,
    shop_address: settings.shop_address,
    shop_phone: settings.shop_phone,
    gst_number: settings.gst_number,
    date: bill.date.toISOString(),
    bill_number: bill.bill_number,
    items: bill.items.map((i) => ({ name: i.name, qty: i.qty, unit_price: i.unit_price })),
    subtotal: bill.subtotal,
    tax_total: bill.tax_total,
    discount: bill.discount,
    grand_total: bill.grand_total,
    show_tax_breakdown: settings.show_tax_breakdown,
    show_customer_info: settings.show_customer_info,
    payment_method: bill.payment_method,
    customer_name: bill.customer_name ?? '',
    customer_phone: bill.customer_phone ?? '',
    receipt_footer: settings.receipt_footer,
  };
}

export async function printReceipt(bill: BillPrintData, settings: PrintSettings): Promise<void> {
  // Step 1: Tauri IPC (running inside the companion app WebView)
  const tauri = tauriCore();
  if (tauri) {
    try {
      await tauri.invoke('print_receipt_cmd', { data: _receiptPayload(bill, settings) });
      return;
    } catch (e) {
      console.warn('[print] Tauri receipt failed:', e);
    }
  }

  // Step 2: Companion app HTTP server (browser users with companion running)
  if (await companionAvailable()) {
    if (await _companionPrintReceipt(bill, settings)) return;
  }

  // Step 3: QZ Tray raw ESC/POS
  if (settings.receipt_printer) {
    const escpos = buildReceiptEscPos(bill, settings);
    const ok = await printRawViaQZ(escpos, settings.receipt_printer);
    if (ok) return;
  }

  // Step 4: Browser print dialog
  openPrintWindow(buildReceiptHtml(bill, settings));
}

// ── Barcode ───────────────────────────────────────────────────────────────────

function buildBarcodeHtml(
  product: {
    name: string;
    selling_price: number;
    sku: string;
    barcode: string;
    details?: Record<string, string>;
  },
  settings: PrintSettings,
  imgSrc: string
): string {
  const shopName = settings.shop_name;
  return `<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<title>Barcode - ${esc(product.name)}</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: Arial, Helvetica, sans-serif;
    display: flex;
    justify-content: center;
    align-items: flex-start;
    padding: 12mm;
    background: #fff;
    color: #000;
  }
  .label {
    text-align: center;
    width: 64mm;
    border: 1px solid #ccc;
    padding: 4mm;
  }
  .shop { font-size: 10px; font-weight: bold; margin-bottom: 3mm; letter-spacing: 0.5px; }
  .barcode-img { width: 100%; height: auto; display: block; margin: 0 auto; }
  .no-barcode { font-size: 12px; font-family: 'Courier New', monospace; letter-spacing: 3px; margin: 4mm 0; }
  .product-name { font-size: 12px; font-weight: bold; margin-top: 3mm; }
  .price { font-size: 16px; font-weight: bold; margin-top: 2mm; }
  .sku { font-size: 9px; color: #555; margin-top: 2mm; }
  .details { margin-top: 2mm; text-align: left; width: 100%; border-collapse: collapse; }
  .details td { font-size: 9px; color: #333; padding: 0.5px 0; }
  .details td:first-child { font-weight: bold; padding-right: 3px; white-space: nowrap; }
  @page { margin: 0; }
  @media print { body { padding: 8mm; } }
</style>
</head>
<body>
  <div class="label">
    ${shopName ? `<p class="shop">${esc(shopName)}</p>` : ''}
    ${imgSrc
      ? `<img class="barcode-img" src="${imgSrc}" alt="${esc(product.barcode)}" />`
      : `<p class="no-barcode">${esc(product.barcode)}</p>`
    }
    <p class="product-name">${esc(product.name)}</p>
    ${settings.barcode_show_price ? `<p class="price">&#8377;${fmt(product.selling_price)}</p>` : ''}
    ${settings.barcode_show_sku && product.sku ? `<p class="sku">SKU: ${esc(product.sku)}</p>` : ''}
    ${(() => {
      const entries = Object.entries(product.details || {}).filter(([k]) => k.trim());
      if (!entries.length) return '';
      const rows = entries
        .map(([k, v]) => `<tr><td>${esc(k)}</td><td>${esc(String(v))}</td></tr>`)
        .join('');
      return `<table class="details">${rows}</table>`;
    })()}
  </div>
</body>
</html>`;
}

export async function printBarcode(
  product: {
    id: string;
    name: string;
    selling_price: number;
    sku: string;
    barcode: string;
    details?: Record<string, string>;
  },
  settings: PrintSettings
): Promise<void> {
  const token = pb.authStore.token;

  // Fetch barcode PNG and convert to base64 data URL so it works in both
  // QZ Tray's HTML renderer and the fallback window.open approach.
  let imgSrc = '';
  try {
    const res = await fetch(`${PB_URL}/api/custom/barcode/${product.id}`, {
      headers: { Authorization: token },
    });
    if (res.ok) {
      imgSrc = await blobToDataUrl(await res.blob());
    }
  } catch {
    // label prints without barcode image
  }

  const html = buildBarcodeHtml(product, settings, imgSrc);

  // Step 1: Tauri IPC
  const tauri = tauriCore();
  if (tauri) {
    try {
      await tauri.invoke('print_barcode_cmd', {
        data: {
          name: product.name,
          barcode: product.barcode,
          sku: product.sku,
          selling_price: product.selling_price,
          show_sku: settings.barcode_show_sku,
          show_price: settings.barcode_show_price,
          shop_name: settings.shop_name,
          details: product.details ?? {},
        },
      });
      return;
    } catch (e) {
      console.warn('[print] Tauri barcode failed:', e);
    }
  }

  // Step 2: Companion app HTTP server
  if (await companionAvailable()) {
    if (await _companionPrintBarcode(product, settings)) return;
  }

  // Step 3: QZ Tray HTML print
  if (settings.label_printer) {
    const ok = await printHtmlViaQZ(html, settings.label_printer);
    if (ok) return;
  }

  // Step 4: Browser print dialog
  openPrintWindow(html);
}
