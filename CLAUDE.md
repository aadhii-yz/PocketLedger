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
- `collections/schema.go` — idempotent schema bootstrap. `CreateCollections` runs at startup and creates/extends PocketBase collections only if they don't exist. Each `ensure*` function uses a two-branch pattern: if the collection already exists, check for missing fields, tighten access rules, and add indexes; if not, create fresh. `EnsureDefaultLocations` runs after all schema setup to seed the default warehouse/shop and back-fill existing rows.
- `handlers/` — one file per domain (billing, stock, barcode, stats, logs, locations, transfers). Each handler is a closure receiving `core.App`, returning a `func(*core.RequestEvent) error`.
- `services/` — pure business logic with no HTTP concerns: `stats.go` runs raw SQL for dashboard/low-stock queries and provides `NextBillNumber`/`NextTransferNumber`; `barcode.go` generates Code128 PNG images.
- `middleware/roles.go` — `RequireRole(...roles)` middleware checks the `role` field on the authenticated PocketBase user. Must be chained after `apis.RequireAuth()`.
- Transactional writes: billing (`CreateBill`), stock adjustment (`AdjustStock`), and transfer completion (`CompleteTransfer`) all use `app.RunInTransaction`. Any failure rolls back atomically.
- **System logging pattern:** handlers write a `system_logs` record *inside* their transaction (using `_ = txApp.Save(logRec)`) so the log is rolled back together with the main operation on failure. Logs older than 90 days are pruned at startup.
- **Pre-delete hooks** in `main.go` block deletion of `products` that have stock records and `locations` that are referenced by stock, bills, or transfers.
- All raw SQL uses `dbx.Params` binding — never string-concatenate user input (shop_id, location_id) into queries.
- `backend/pb_data/` — live SQLite databases (data.db, auxiliary.db). Do not edit directly.
- `backend/pb_public/` — where the built frontend is served from as a static site.

**Roles:** `admin`, `manager`, `pos` (maps to `billing` on frontend), `stock_entry` (maps to `stock` on frontend). Access control is enforced both in PocketBase collection rules and via `RequireRole` middleware on custom routes.
- `pos` users are restricted to their `assigned_shop` — billing loads only that shop's stock and sends `shop_id` from `assigned_shop`. The `bills` collection rule enforces this at the DB level: pos users can only create bills for their `assigned_shop`.
- `manager` and `stock_entry` are unrestricted — they can adjust stock at any location, and access all transfer/stats routes. `assigned_shop` is not used for these roles.
- `stock_entry` **cannot** update `stock` quantities directly via the PocketBase REST API (`PATCH /api/collections/stock/records/{id}`) — the collection `updateRule` is admin/manager only. All stock quantity changes must go through `POST /api/custom/stock/adjust`, which writes the `stock_movements` audit row. The adjust endpoint only accepts `type` values of `purchase | adjustment | return`; the other movement types (`sale`, `transfer_in`, `transfer_out`) are written exclusively by the billing and transfer handlers.
- `bill_items` and `stock_movements` have locked `createRule`s (pos/admin/manager and stock roles respectively) — direct REST inserts that bypass the custom handlers are rejected.

**Bill numbering:** Sequential `INV-XXXX` via `services.NextBillNumber`. Transfer numbering: sequential `TRF-XXXX` via `services.NextTransferNumber`. Neither is gap-safe under concurrent writes — acceptable for single-store use.

**Product details (key-value attributes):** Stored as a JSON object in the `details` field (e.g. `{"Color":"Red","Size":"XL"}`). The products form renders a dynamic row list — each row has a key input and a value input; rows with blank keys are silently dropped on save. Converted to/from `{ key, value }[]` in the frontend.

**SKU auto-generation:** Done client-side in `stock/products/+page.svelte` via `generateSku()`. Format: `{CAT}-{NAME}-{NNNN}` — first 3 chars of the category name + first 3 chars of the product's first word (plus first 2 chars of the second word if present) + count of products in that category zero-padded to 4 digits. Auto-fills reactively as the user types the product name; user can override at any point (sets `skuIsAutoGenerated = false`). SKU has a DB-level unique index (`idx_products_sku`).

**Barcode auto-generation:** 10-digit zero-padded integer strings (e.g. `"0000000042"`). Two paths: (1) at product create time — if the user leaves barcode blank, the frontend queries `MAX(barcode)` from the `products` collection, increments, and saves it; (2) on-demand for existing products via `POST /api/custom/barcode/generate` — same `MAX(CAST(barcode AS INTEGER))+1` logic, but executed in the backend handler. `GET /api/custom/barcode/{productId}` returns a Code128 PNG (300×80 px) generated by `services.GenerateBarcodePNG`. Barcode has a partial unique index (`idx_products_barcode WHERE barcode != ''`).

**Custom API routes** (all under `/api/custom`, all require auth):

| Method | Path | Roles |
|---|---|---|
| GET | `/barcode/{productId}` | all |
| POST | `/barcode/generate` | admin, manager, stock_entry |
| POST | `/bills/create` | admin, manager, pos |
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
- `src/lib/schemas.ts` — **Single source of truth for all types.** Zod schemas for every PocketBase collection (snake_case, matching `backend/pb_schema.json`) plus exported `z.infer<>` TypeScript types and form input schemas with validation messages. Do not define PocketBase record types elsewhere — import from here. Also exports `firstError(ZodError)` utility.
- `src/lib/pb.ts` — PocketBase client singleton, `customFetch` helper for `/api/custom/*` calls (injects auth token), `mapRole` (PocketBase role → frontend role), and the exported `PB_URL` constant. `AuthUser` type re-exported from `schemas.ts`. Always import `PB_URL` from here — never re-derive it from the `pb` instance.
- `src/lib/print.ts` — Print utility: `loadPrintSettings()` (fetches singleton from `print_settings` collection), `printReceipt(bill, settings)` (80mm thermal receipt), `printBarcode(product, settings)` (single barcode label), `listQZPrinters()` (returns all printers visible to QZ Tray). Both print functions follow a **three-step fallback chain**: (1) companion app at `localhost:8765` — 800 ms availability check, then POST; (2) QZ Tray raw/HTML print (if a printer name is set in `print_settings`); (3) `window.open` + browser print dialog. QZ Tray is lazy-loaded via dynamic `import('qz-tray')` and uses unsigned security mode. Barcode PNG is fetched from `/api/custom/barcode/{id}` and converted to a base64 data URL. `PrintSettings` type re-exported from `schemas.ts`.
- `src/routes/+page.svelte` — login page; on success calls `mapRole` and `goto`s to the role dashboard.
- Routes are organized by role: `/admin` (logs, users), `/manager` (reports, sales, stock, users, print-settings), `/billing` (history), `/stock` (inventory, products, shops, transfers, warehouse), `/stats` (overview, [shopId]).
- `src/lib/components/` — shared UI primitives (Button, Card, DataTable, etc.).
- `src/lib/index.ts` — barrel export for components.

**Zod schema pattern:** `schemas.ts` contains collection schemas (reference only, not used to parse API responses — PocketBase expanded relations return nested objects that won't match flat-ID schemas) and form input schemas (used with `safeParse()` before API calls). Form handlers follow this pattern:
```typescript
import { XFormSchema, firstError } from '$lib/schemas';

const parsed = XFormSchema.safeParse({ ...formValues });
if (!parsed.success) { errorMsg = firstError(parsed.error); return; }
// use parsed.data in the try block
```
Form schemas using `z.coerce.number()` handle `<input type="number">` string values automatically. API responses are typed via `z.infer<>` but never runtime-parsed.

**Key frontend dependencies:** Tailwind CSS v4 (via `@tailwindcss/vite`, theme defined in `src/styles/theme.css`), `lucide-svelte` for icons, `chart.js` + `svelte-chartjs` for stats charts, `date-fns` for date formatting, `zod` for runtime form validation and type inference, `qz-tray` + `@types/qz-tray` for silent printing via QZ Tray (lazy-loaded, falls back gracefully if not installed).

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

**Camera barcode scanning (`BarcodeScanner.svelte`):** Renders a camera button only on touch devices (`navigator.maxTouchPoints > 0`). On tap, opens a full-screen camera modal. Uses the native `BarcodeDetector` API on Android (zero extra JS); falls back to dynamically imported `@zxing/browser` on iOS (lazy-loaded only on first use). Integrated in billing, stock inventory, and stock transfers pages. `@zxing/browser` requires `@zxing/library` as a peer dep — both must be installed explicitly (`npm install @zxing/browser @zxing/library`), since npm does not auto-install peer deps. Camera access requires HTTPS or `localhost`; plain HTTP on a local IP will be blocked by Android Chrome.

### Companion App (`companion_app/`)

Flutter app that runs a local HTTP server on `localhost:8765`, bridging the SvelteKit PWA to thermal printers via raw TCP. Required because the backend is cloud-hosted and cannot reach printers on the shop/warehouse LAN, and browsers cannot open raw TCP sockets.

**Why it exists:** Cloud backend → can't reach LAN printers. Browser PWA → can't open raw TCP. Companion app runs locally on the same device/network as the printers and accepts print jobs from the PWA over localhost.

**Printer support:**
- `lib/services/tspl_printer.dart` — TSPL commands for **TVS LP 46 dlite** (barcode labels, 50 mm × 30 mm, 203 DPI). Sends over TCP to the printer's WiFi IP:9100.
- `lib/services/escpos_printer.dart` — ESC/POS bytes for **TVS RP 3230** (80 mm thermal receipt). Same TCP approach.

**HTTP API (all on `localhost:8765`):**
- `GET /status` → `{ ok: true }` — used by `print.ts` as the availability check
- `POST /print/barcode` — body: product fields + `show_sku`, `show_price`, `shop_name`
- `POST /print/receipt` — body: all `BillPrintData` fields merged with `PrintSettings` fields

Printer IPs are stored in the companion app's own `SharedPreferences` (configured via its settings screen), not passed in the request body.

**Android background service:** `lib/services/background_service.dart` uses `flutter_background_service` to run the HTTP server in a foreground-service isolate so Android does not kill it while the worker uses the PWA in Chrome. The UI isolate notifies the service isolate to reload settings via `service.invoke('reload_settings')` after a save.

**Building:** Triggered manually via GitHub Actions (`.github/workflows/build-companion.yml`). The workflow runs `flutter create . --no-pub` to generate platform boilerplate, restores our `lib/` and `pubspec.yaml` via `git checkout`, runs `patch_manifest.py` to inject the foreground-service permissions into `AndroidManifest.xml`, then builds APK (ubuntu runner) and Windows exe (windows runner). Artifacts are retained for 30 days.

**First-time device setup:** Open companion app → enter barcode printer IP and receipt printer IP → Save. Minimise; keep running in background. The PWA detects it via the `/status` ping and uses it automatically.

### Data model summary

| Collection | Purpose |
|---|---|
| `locations` | Warehouse and shop locations (`type`: warehouse\|shop, `is_active`) |
| `users` | Extended PocketBase auth with `role` and `assigned_shop` (RelationField → locations, `pos` users only) |
| `categories` | Product categories |
| `products` | Product catalogue (SKU, barcode, prices, tax rate, `details` JSON object for arbitrary key-value attributes) |
| `stock` | Current quantity per **(product, location)** pair + low-stock threshold |
| `stock_movements` | Audit log of every stock change; `type` includes `transfer_in`/`transfer_out`; scoped to a `location` |
| `stock_transfers` | Transfer header (transfer_number `TRF-XXXX`, from/to locations, `status`: pending\|completed\|cancelled) |
| `stock_transfer_items` | Line items per transfer (product snapshot, quantity) |
| `bills` | Invoice header scoped to a `shop` (RelationField → locations); payment_method includes `credit` |
| `bill_items` | Line items per bill (price snapshot at sale time) |
| `print_settings` | Singleton — shop info, receipt/label template toggles, and QZ Tray printer names (shop_name, shop_address, shop_phone, gst_number, receipt_footer, show_customer_info, show_tax_breakdown, barcode_show_sku, barcode_show_price, receipt_printer, label_printer). Read by all authenticated users; write by admin/manager only. |
| `system_logs` | Application-level event log (INFO/WARNING/ERROR) |

**Stock is keyed by `(product, location)`** — there is no DB-level unique constraint; uniqueness is enforced in handler logic. `CompleteTransfer` does a find-then-update (not blind insert) for the destination stock record, and returns a 422 if the source has insufficient quantity.

**Indexes:** `idx_stock_product_location` on `stock(product, location)`, `idx_bills_shop_created` on `bills(shop, created DESC)`, `idx_movements_product_location` on `stock_movements(product, location, created DESC)`, `idx_logs_created` on `system_logs(created DESC)`. All applied idempotently via the schema upgrade path.
