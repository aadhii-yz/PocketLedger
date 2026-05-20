---
title: Inventory
description: Manage stock levels, adjust quantities, and maintain the product catalogue.
---

The stock section (`/stock`) is accessible to `stock_entry`, `manager`, and `admin` roles.

## Inventory view

The main inventory page shows all products with their current quantities at every location. Columns:

| Column | Notes |
|---|---|
| Product | Name + SKU |
| Category | Product category |
| Location | Warehouse or shop |
| Quantity | Current stock level |
| Low stock threshold | Alert fires when quantity ≤ threshold |
| Actions | Adjust, view movements |

**Low-stock alerts** appear as a badge in the sidebar and a panel at the top of the page. Click **Alerts** to filter to only low-stock items.

Use the **Location filter** to view stock at a specific warehouse or shop.

## Adjusting stock

Click **Adjust** on any stock row or use **Stock → Adjust** in the sidebar.

| Field | Notes |
|---|---|
| Product | Pre-filled if coming from a row action |
| Location | Which warehouse or shop |
| Type | `purchase` · `adjustment` · `return` |
| Quantity | Positive number; direction determined by type |
| Notes | Optional reason (visible in stock movements log) |

Every adjustment writes a `stock_movements` record atomically. The adjust endpoint (`POST /api/custom/stock/adjust`) is the only way to change stock quantities — direct PATCH on the stock collection is blocked for `stock_entry` by the collection access rules.

**Movement types:**
- `purchase` — stock received from a supplier
- `adjustment` — manual correction (shrinkage, damage, count discrepancy)
- `return` — customer returns stock to the shop

`sale` and `transfer_in/out` movements are written automatically by the billing and transfer handlers.

## Products

`/stock/products` — the product catalogue. Create, edit, and search products.

### Product fields

| Field | Notes |
|---|---|
| Name | Product display name |
| Category | Must exist in categories first |
| SKU | Auto-generated as `{CAT}-{NAME}-{NNNN}` — override at any time |
| Barcode | Auto-incremented 10-digit integer if left blank; or enter manually |
| Sale price | Default unit price for billing |
| Purchase price | Cost price (for reports) |
| Tax rate | Applied to sales |
| Details | Free-form key-value attributes (e.g. Color, Size) |

### SKU format

Auto-generated SKU: first 3 chars of category + first 3-5 chars of product name + zero-padded count.
Example: `ELE-SAM-0042` for the 42nd product in "Electronics" named "Samsung...".

Auto-fills as you type the product name. Set your own by typing in the SKU field (auto-generation is disabled after manual edit).

### Barcode generation

- **At create time** — leave barcode blank; the frontend queries the highest existing barcode and increments it
- **For existing products** — click **Generate Barcode** on the product row; the backend handler does the same MAX+1 logic
- **Print barcode** — click the barcode icon to print a 50×30 mm label with product name, price (optional), and SKU (optional)

## Categories

`/stock/categories` — manage product categories. Categories are referenced by products and by the SKU auto-generation logic.
