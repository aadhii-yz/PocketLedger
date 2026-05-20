---
title: Manager Guide
description: Dashboard, sales reports, user management, and location management for managers.
---

The manager dashboard (`/manager`) is accessible to `manager` and `admin` roles.

## Dashboard / Stats

`/stats/overview` — the main overview page. Shows:

- **Total sales** — revenue across all shops for the selected period
- **Bills count** — number of invoices created
- **Low stock items** — count of products below their threshold
- **Recent activity** — latest bills and stock movements

The stats page also has per-shop views — click a shop card to drill into `/stats/[shopId]` for that location's specific metrics.

## Sales reports

Under **Manager → Reports**, you can filter bills by:
- Date range
- Shop / location
- Payment method

Bills are listed with invoice number, customer, amount, and payment method. Export is not built-in — use PocketBase's admin panel for data exports if needed.

## User management

`/manager/users` (manager) or `/admin/users` (admin) — create and manage user accounts.

| Role | What they can do |
|---|---|
| `admin` | System logs, user management, full access |
| `manager` | Reports, all stock, billing, locations, user management |
| `stock_entry` | Inventory adjustments, products, transfers — no billing |
| `pos` | Billing at their `assigned_shop` only |

When creating a `pos` user, select their **Assigned shop** — this scopes all their billing to that location and is enforced at the database level.

## Location management

`/stock/shops` — manage warehouses and shops.

| Field | Notes |
|---|---|
| Name | Display name |
| Type | `warehouse` or `shop` |
| Active | Inactive locations don't appear in location selectors |

The default locations (one Warehouse, one Shop) are seeded on first launch and cannot be deleted if they have stock or bills associated.

## Print settings

`/manager/print-settings` — configure receipt and label templates. See the [Print Settings guide](/PocketLedger/user-guide/print-settings/).
