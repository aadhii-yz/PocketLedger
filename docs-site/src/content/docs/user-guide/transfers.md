---
title: Stock Transfers
description: Move stock between warehouse and shop locations.
---

Transfers (`/stock/transfers`) allow you to move products from one location (warehouse or shop) to another. Accessible to `stock_entry`, `manager`, and `admin` roles.

## How transfers work

1. **Create** a transfer — select source location, destination, and add line items (product + quantity)
2. **Pending** — the transfer is saved with status `pending`. Stock is **not** deducted yet
3. **Complete** — confirm the transfer. Stock is atomically deducted from the source and added at the destination. If source quantity is insufficient, the completion fails with a 422 error
4. **Cancel** — cancel a pending transfer. No stock changes occur

## Creating a transfer

Click **New Transfer** on the transfers page.

| Field | Notes |
|---|---|
| From location | The source (warehouse or shop) |
| To location | The destination |
| Transfer items | One row per product — add products via search or barcode scanner |
| Quantity | How many units to move |

Each transfer gets a sequential number (`TRF-XXXX`).

## Transfer states

| Status | Description | Actions available |
|---|---|---|
| `pending` | Created, awaiting completion | Complete, Cancel |
| `completed` | Stock moved successfully | View only |
| `cancelled` | Transfer was cancelled | View only |

## Filtering

The transfer list accepts filters:
- **Status** — pending / completed / cancelled
- **From location**
- **To location**

## Stock movements

When a transfer is completed, two `stock_movements` records are written inside the same transaction:
- `transfer_out` at the source location
- `transfer_in` at the destination location

If the transaction fails (e.g. insufficient stock), both movements are rolled back.
