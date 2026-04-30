# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

### Build & Run
```bash
make run          # full build (frontend + backend) then start server at :8090
make build        # build only (frontend + backend + copy assets)
make clean        # remove build artifacts
```

### Development
```bash
make dev-frontend    # start Svelte dev server (hot reload, no backend needed)
```
For full-stack dev: run `make dev-frontend` alongside a pre-built backend (`make backend && cd backend && ./backend serve`).

### Frontend only
```bash
cd frontend && npm run check        # type-check Svelte + TypeScript
cd frontend && npm run check:watch  # type-check in watch mode
```

### Backend only
```bash
cd backend && go mod tidy && go build -o backend .
cd backend && ./backend serve       # starts PocketBase on :8090
```

## Architecture

PocketLedger is a two-tier app: a Go/PocketBase backend serving a static SvelteKit SPA.

### Backend (`backend/`)

Built on [PocketBase](https://pocketbase.io/) (v0.37). PocketBase provides the SQLite database, auth, and a REST API. All custom business logic lives under `/api/custom/*`, registered in `main.go`.

**Key design patterns:**
- `collections/schema.go` — idempotent schema bootstrap. `CreateCollections` runs at startup and creates/extends PocketBase collections only if they don't exist. Each `ensure*` function uses a two-branch pattern: if the collection already exists, check for missing fields and add them; if not, create fresh. `EnsureDefaultLocations` runs after all schema setup to seed the default warehouse/shop and back-fill existing rows.
- `handlers/` — one file per domain (billing, stock, barcode, stats, logs, locations, transfers). Each handler is a closure receiving `core.App`, returning a `func(*core.RequestEvent) error`.
- `services/` — pure business logic with no HTTP concerns: `stats.go` runs raw SQL for dashboard/low-stock queries and provides `NextBillNumber`/`NextTransferNumber`; `barcode.go` generates Code128 PNG images.
- `middleware/roles.go` — `RequireRole(...roles)` middleware checks the `role` field on the authenticated PocketBase user. Must be chained after `apis.RequireAuth()`.
- Transactional writes: billing (`CreateBill`), stock adjustment (`AdjustStock`), and transfer completion (`CompleteTransfer`) all use `app.RunInTransaction`. Any failure rolls back atomically.
- **System logging pattern:** handlers write a `system_logs` record *inside* their transaction (using `_ = txApp.Save(logRec)`) so the log is rolled back together with the main operation on failure.
- All raw SQL uses `dbx.Params` binding — never string-concatenate user input (shop_id, location_id) into queries.
- `backend/pb_data/` — live SQLite databases (data.db, auxiliary.db). Do not edit directly.
- `backend/pb_public/` — where the built frontend is served from as a static site.

**Roles:** `admin`, `manager`, `pos` (maps to `billing` on frontend), `stock_entry` (maps to `stock` on frontend). Access control is enforced both in PocketBase collection rules and via `RequireRole` middleware on custom routes.
- `pos` users are restricted to their `assigned_shop` — billing loads only that shop's stock and sends `shop_id` from `assigned_shop`.
- `manager` and `stock_entry` are unrestricted — they can adjust stock at any location, and access all transfer/stats routes. `assigned_shop` is not used for these roles.

**Bill numbering:** Sequential `INV-XXXX` via `services.NextBillNumber`. Transfer numbering: sequential `TRF-XXXX` via `services.NextTransferNumber`. Neither is gap-safe under concurrent writes — acceptable for single-store use.

**Custom API routes** (all under `/api/custom`, all require auth):

| Method | Path | Roles |
|---|---|---|
| GET | `/barcode/{productId}` | all |
| POST | `/barcode/generate` | admin, manager, stock_entry |
| POST | `/bills/create` | admin, manager, pos, stock_entry |
| GET | `/locations` | all |
| POST | `/locations` | admin, manager |
| PATCH | `/locations/{id}` | admin, manager |
| POST | `/stock/adjust` | admin, manager, stock_entry |
| GET | `/stock/alerts` | admin, manager, stock_entry |
| GET | `/transfers` | admin, manager, stock_entry |
| POST | `/transfers/create` | admin, manager, stock_entry |
| POST | `/transfers/{id}/complete` | admin, manager, stock_entry |
| POST | `/transfers/{id}/cancel` | admin, manager, stock_entry |
| GET | `/stats/dashboard` | all |
| POST | `/logs` | all |
| GET | `/logs` | admin |

`GET /stats/dashboard` accepts an optional `?shop_id=` query param — omit for the all-shops aggregate (manager overview), pass a location ID for the per-shop stats page. `GET /transfers` accepts optional `?status=`, `?from_location=`, `?to_location=` filters.

### Frontend (`frontend/`)

SvelteKit app in **static adapter mode** (prerendered, `fallback: index.html` for SPA routing). Uses Svelte 5 runes mode enforced project-wide via `svelte.config.js`.

**Key files:**
- `src/lib/pb.ts` — PocketBase client singleton, `customFetch` helper for `/api/custom/*` calls (injects auth token), and `mapRole` (PocketBase role → frontend role).
- `src/routes/+page.svelte` — login page; redirects to role-specific dashboard after auth.
- Routes are organized by role: `/admin`, `/manager`, `/billing`, `/stock`, `/stats`.
- `src/lib/components/` — shared UI primitives (Button, Card, DataTable, etc.).
- `src/lib/index.ts` — barrel export for components.

**Key frontend dependencies:** Tailwind CSS v4 (via `@tailwindcss/vite`, theme defined in `src/styles/theme.css`), `lucide-svelte` for icons, `chart.js` + `svelte-chartjs` for stats charts, `date-fns` for date formatting.

**Dynamic routes require `+page.ts`:** The root `+layout.ts` sets `prerender = true` and `trailingSlash = 'always'`. Any route with dynamic params (e.g. `/stats/[shopId]/`) needs a companion `+page.ts` with `export const prerender = false; export const ssr = false;` or the build will fail. The `/admin` and `/stats/overview` routes also carry their own `+page.ts` for this reason.

**Role-aware sidebars:** Stats pages (`/stats/overview`, `/stats/[shopId]`) read `pb.authStore.record.role` at init and switch between the manager menu and the stock_entry menu at the same URL — no separate routes needed.

**Env config:** Create `frontend/.env` with `VITE_PB_URL=http://localhost:8090` for local dev. Defaults to `http://localhost:8090` if unset.

**Build output** (`frontend/build/`) is copied to `backend/pb_public/` by `make copy` so the Go binary serves the SPA.

**PWA setup:** The app is a PWA via `vite-plugin-pwa`. Three non-obvious constraints:
- `injectRegister: null` is required — the SvelteKit static adapter re-processes HTML after Vite's build phase, so the plugin's auto-injection never runs. The manifest `<link>` and `<script src="/registerSW.js">` are hardcoded in `app.html` instead.
- `frontend/.npmrc` sets `legacy-peer-deps=true` because `vite-plugin-pwa` declares peer support only up to Vite 7 while this project uses Vite 8.
- `package.json` pins `"serialize-javascript": "^7.0.5"` under `overrides` to patch 4 high CVEs in the `workbox-build → @rollup/plugin-terser` transitive dep chain.

**Offline caching strategy** (Workbox rules in `vite.config.ts`):
- `products`, `categories`, `locations` → `StaleWhileRevalidate` (reference data, safe to serve stale)
- `stock` collection → `NetworkOnly` (quantities must be live to prevent overselling at POS)
- `/api/custom/*` → `NetworkOnly` (billing writes, transfers, stats — stale financial data is misleading)
- The billing page (`/billing`) disables checkout when offline; `OfflineIndicator.svelte` shows a fixed-bottom banner on all routes via the root layout.

### Data model summary

| Collection | Purpose |
|---|---|
| `locations` | Warehouse and shop locations (`type`: warehouse\|shop, `is_active`) |
| `users` | Extended PocketBase auth with `role` and `assigned_shop` (RelationField → locations, `pos` users only) |
| `categories` | Product categories |
| `products` | Product catalogue (SKU, barcode, prices, tax rate) |
| `stock` | Current quantity per **(product, location)** pair + low-stock threshold |
| `stock_movements` | Audit log of every stock change; `type` includes `transfer_in`/`transfer_out`; scoped to a `location` |
| `stock_transfers` | Transfer header (transfer_number `TRF-XXXX`, from/to locations, `status`: pending\|completed\|cancelled) |
| `stock_transfer_items` | Line items per transfer (product snapshot, quantity) |
| `bills` | Invoice header scoped to a `shop` (RelationField → locations); payment_method includes `credit` |
| `bill_items` | Line items per bill (price snapshot at sale time) |
| `system_logs` | Application-level event log (INFO/WARNING/ERROR) |

**Stock is keyed by `(product, location)`** — there is no DB-level unique constraint; uniqueness is enforced in handler logic. `CompleteTransfer` does a find-then-update (not blind insert) for the destination stock record, and returns a 422 if the source has insufficient quantity.
