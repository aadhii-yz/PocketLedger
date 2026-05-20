---
title: Billing / POS
description: Create bills, scan barcodes, process payments, and print receipts.
---

import { Aside } from '@astrojs/starlight/components';

The billing screen (`/billing`) is the point-of-sale interface. `pos` role users are sent here automatically after login and see only stock from their assigned shop.

## Creating a bill

### 1. Find products

- **Search box** — type the product name or SKU; results update as you type
- **Barcode scanner** — on touch devices, a camera button appears next to the search box. Tap it to open the full-screen scanner. Point at a Code 128 barcode; it's added to the cart instantly
- **Barcode input** — if you have a USB barcode scanner, just scan — the barcode field captures it automatically

### 2. Build the cart

Each product row shows:
- Name, SKU, and current stock level
- Quantity selector (increment / decrement / type directly)
- Unit price (can be overridden for the current bill)
- Line total

Products with zero stock are shown but disabled to prevent overselling.

<Aside type="note">
The billing page operates in **NetworkOnly** mode — stock quantities are always fetched live. If the device goes offline, a banner appears and checkout is disabled.
</Aside>

### 3. Process payment

Click **Checkout**. In the payment dialog:

| Field | Notes |
|---|---|
| Customer name | Optional — shown on receipt if "Show customer info" is enabled in Print Settings |
| Payment method | Cash, Card, or Credit |
| Amount received | For Cash — calculates change automatically |

Click **Confirm** to create the bill. Stock quantities are deducted atomically along with the bill creation.

### 4. Print receipt

After confirmation, a **Print Receipt** button appears. Printing follows this fallback chain:

1. **Flutter JS channel** — if you're in the companion app WebView, prints instantly
2. **localhost:8765** — if the companion app is running alongside Chrome, sends via HTTP
3. **QZ Tray** — if a receipt printer name is set in Print Settings and QZ Tray is installed
4. **Browser print dialog** — `window.open` fallback

## Bill history

The **History** tab (`/billing/history` or the history link in the billing header) lists all bills for the current user's shop. Each row shows:

- Invoice number (`INV-XXXX`)
- Customer name (if set)
- Date and time
- Total amount and payment method

Click a row to see the full bill detail with all line items.

## Roles and shop scoping

`pos` users can only bill at their `assigned_shop`. They see stock quantities for that shop only, and all bills they create are automatically scoped to that shop — this is enforced at the database level, not just the UI.

`manager` and `admin` users can create bills for any shop — they'll see a shop selector.
