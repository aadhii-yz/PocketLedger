import { pb } from './pb';

export interface PrintSettings {
  shop_name: string;
  shop_address: string;
  shop_phone: string;
  gst_number: string;
  receipt_footer: string;
  show_customer_info: boolean;
  show_tax_breakdown: boolean;
  barcode_show_sku: boolean;
  barcode_show_price: boolean;
}

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
      };
    }
  } catch {
    // fall through to defaults
  }
  return { ...defaultSettings };
}

function fmt(n: number): string {
  return n.toFixed(2);
}

function fmtDate(d: Date): string {
  return d.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
}

export function printReceipt(bill: BillPrintData, settings: PrintSettings): void {
  const shopName = settings.shop_name || bill.shop_name || 'Shop';
  const payLabel = bill.payment_method.toUpperCase();

  const itemRows = bill.items.map((item) => {
    const lineTotal = item.unit_price * item.qty;
    // Truncate long names to avoid layout breakage on 80mm
    const name = item.name.length > 20 ? item.name.slice(0, 19) + '…' : item.name;
    return `<tr>
      <td class="item-name">${esc(name)}</td>
      <td class="num">${item.qty}</td>
      <td class="num">${fmt(item.unit_price)}</td>
      <td class="num">${fmt(lineTotal)}</td>
    </tr>`;
  }).join('');

  const taxRows = settings.show_tax_breakdown
    ? `<tr><td>Subtotal</td><td class="num">&#8377;${fmt(bill.subtotal)}</td></tr>
       <tr><td>GST</td><td class="num">&#8377;${fmt(bill.tax_total)}</td></tr>
       ${bill.discount > 0 ? `<tr><td>Discount</td><td class="num">-&#8377;${fmt(bill.discount)}</td></tr>` : ''}`
    : '';

  const customerRow = settings.show_customer_info && (bill.customer_name || bill.customer_phone)
    ? `<div class="divider"></div>
       <p>Customer: ${esc(bill.customer_name || '')}${bill.customer_phone ? ' / ' + esc(bill.customer_phone) : ''}</p>`
    : '';

  const html = `<!DOCTYPE html>
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

  openPrintWindow(html);
}

export async function printBarcode(
  product: { id: string; name: string; selling_price: number; sku: string; barcode: string },
  settings: PrintSettings
): Promise<void> {
  const PB_URL = (pb as any).baseURL ?? (pb as any).baseUrl ?? window.location.origin;
  const token = pb.authStore.token;

  // Fetch the barcode PNG and convert to a blob URL for use in the new window.
  let imgSrc = '';
  try {
    const res = await fetch(`${PB_URL}/api/custom/barcode/${product.id}`, {
      headers: { Authorization: token },
    });
    if (res.ok) {
      const blob = await res.blob();
      imgSrc = URL.createObjectURL(blob);
    }
  } catch {
    // fall through — label prints without barcode image
  }

  const shopName = settings.shop_name;

  const html = `<!DOCTYPE html>
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
  </div>
</body>
</html>`;

  // openPrintWindow creates a blob URL for the HTML page and triggers autoPrint.
  // The barcode imgSrc blob URL is referenced inside the HTML; revoke it after a
  // generous delay so the new window has time to load the image before we clean up.
  openPrintWindow(html, true);
  if (imgSrc) {
    setTimeout(() => URL.revokeObjectURL(imgSrc), 10000);
  }
}

function esc(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function openPrintWindow(html: string, autoPrint = true): Window | null {
  const blob = new Blob([html], { type: 'text/html' });
  const url = URL.createObjectURL(blob);
  const win = window.open(url, '_blank', 'width=400,height=600');
  if (!win) {
    URL.revokeObjectURL(url);
    return null;
  }
  if (autoPrint) {
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
  } else {
    // Caller manages printing; revoke blob URL after a generous timeout.
    setTimeout(() => URL.revokeObjectURL(url), 30000);
  }
  return win;
}
