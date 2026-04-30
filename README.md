# PocketLedger

A minimal yet powerful web-based **Inventory** and **Billing** system for small businesses.

> [!CAUTION]
> Currently under development

## Stack

- **Backend:** Go + [PocketBase](https://pocketbase.io/) (SQLite, auth, REST API)
- **Frontend:** [SvelteKit](https://svelte.dev/) (static SPA, Svelte 5 runes)

## Prerequisites

- Go 1.26+
- Node.js 18+
- `make`

## Running

```bash
make run         # build frontend + backend, then serve at http://localhost:8090
```

For development:

```bash
# backend
cd backend && go build -o backend . && ./backend serve

# frontend (hot reload)
make dev-frontend
```

Create `frontend/.env` for local dev:

```
VITE_PB_URL=http://localhost:8090
```

## User Roles

| Role | Dashboard | Access |
|---|---|---|
| `admin` | `/admin` | User management, system config |
| `manager` | `/manager` | Reports, sales, stock overview, transfers, stats |
| `pos` | `/billing` | Create bills for their assigned shop only |
| `stock_entry` | `/stock` | Inventory, products, stock movements, transfers, stats |

- `pos` users are restricted to their `assigned_shop` — billing loads only that shop's stock
- `manager` and `stock_entry` are unrestricted — they pick a shop at bill time and can access all locations

## Data Model

| Collection | Purpose |
|---|---|
| `locations` | Warehouse and shop locations (`type`: warehouse\|shop, `is_active`) |
| `users` | PocketBase auth extended with `role` and `assigned_shop` (RelationField → locations) |
| `categories` | Product categories |
| `products` | Catalogue — SKU, barcode, prices, tax rate |
| `stock` | Current quantity + low-stock threshold per **(product, location)** pair |
| `stock_movements` | Audit log of every stock change; scoped to a `location` |
| `stock_transfers` | Transfer headers (`TRF-XXXX`, from/to locations, status: pending\|completed\|cancelled) |
| `stock_transfer_items` | Line items per transfer (product snapshot, quantity) |
| `bills` | Invoice headers scoped to a `shop`; payment_method includes `credit` |
| `bill_items` | Line items with price snapshot at sale time |
| `system_logs` | Application event log (INFO / WARNING / ERROR) |

## Architecture Notes

- Custom API routes live under `/api/custom/*`, registered in `backend/main.go`
- Schema bootstrap in `backend/collections/schema.go` — idempotent, runs at startup; seeds default warehouse/shop locations
- Billing, stock adjustments, and transfer completion are fully transactional (SQLite, rolled back on failure)
- Bill numbering: sequential `INV-XXXX`; transfer numbering: sequential `TRF-XXXX`
- All raw SQL uses parameterised queries — no string-concatenated user input
- Built frontend (`frontend/build/`) is copied to `backend/pb_public/` and served as a static site
