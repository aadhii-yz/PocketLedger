---
title: Print Settings
description: Configure receipt templates, barcode label templates, and printer connections.
---

Print settings (`/manager/print-settings`) configure how receipts and barcode labels look, and which printers are used. Readable by all authenticated users; writable by `manager` and `admin` only.

## Shop info

These fields appear on printed receipts:

| Field | Printed as |
|---|---|
| Shop name | Header of receipt |
| Shop address | Below shop name |
| Shop phone | Below address |
| GST number | In the tax section |
| Receipt footer | Last line of receipt (e.g. "Thank you for shopping with us") |

## Receipt options

| Setting | Effect |
|---|---|
| Show customer info | Prints customer name if set at billing time |
| Show tax breakdown | Prints GST calculation line before total |

## Label options

| Setting | Effect |
|---|---|
| Show SKU on label | Prints product SKU below the barcode |
| Show price on label | Prints sale price below the barcode |

## Printer names (QZ Tray)

If you use **QZ Tray** for browser-based printing (no companion app), enter the printer names here:

| Field | Notes |
|---|---|
| Receipt printer | Exact printer name as shown in your OS (e.g. `TVS RP 3230`) |
| Label printer | Exact printer name as shown in your OS (e.g. `TVS LP 46`) |

QZ Tray must be installed and running on the device. It's lazy-loaded — no JS downloaded unless a QZ printer name is configured.

## Printing fallback chain

All print functions follow this order:

1. **Flutter JS channel** — used when running inside the companion app's WebView. Highest priority, fire-and-forget
2. **Companion app HTTP** (`localhost:8765`) — used from a regular browser with the companion app running alongside
3. **QZ Tray** — used from a browser with QZ Tray installed and a printer name configured in Print Settings
4. **Browser print dialog** — fallback for any browser without the companion app or QZ Tray

## Test prints

After saving settings, use the **Test Print** button on the companion app's printer card (Settings tab) to verify the connection and template.

For browser-based users, the **Print Receipt** button on a completed bill triggers the full fallback chain — check the browser console for errors if nothing prints.
