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
- `src/lib/print.ts` — Print utility: `loadPrintSettings()` (fetches singleton from `print_settings` collection), `printReceipt(bill, settings)` (80mm thermal receipt), `printBarcode(product, settings)` (single barcode label), `listQZPrinters()` (returns all printers visible to QZ Tray). Both print functions follow a **four-step fallback chain**: (1) Flutter JS channel (`window.flutter_inappwebview`) — fire-and-forget, present only when running inside the companion app's WebView; `print.ts` calls `window.flutter_inappwebview.callHandler('FlutterPrint', {type, ...data})`; (2) companion app HTTP at `localhost:8765` — 800 ms availability check, then POST (for browser users running companion app alongside Chrome); (3) QZ Tray raw/HTML print (if a printer name is set in `print_settings`); (4) `window.open` + browser print dialog. QZ Tray is lazy-loaded via dynamic `import('qz-tray')` and uses unsigned security mode. Barcode PNG is fetched from `/api/custom/barcode/{id}` and converted to a base64 data URL. `PrintSettings` type re-exported from `schemas.ts`.
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

Flutter app that serves a dual purpose: (1) it **embeds the SvelteKit PWA in a WebView** so users have a single native app instead of separate browser + companion, and (2) it runs a local HTTP server on `localhost:8765` for browser-based users. Required because the backend is cloud-hosted (can't reach LAN printers) and browsers can't open raw TCP sockets.

**Why it exists:** Cloud backend → can't reach LAN printers. Browser PWA → can't open raw TCP. Companion app runs locally on the same device/network as the printers.

**App structure (two tabs):**
- **App tab** (`lib/screens/web_screen.dart`) — `flutter_inappwebview` WebView loading the configured PocketLedger URL. The plugin injects `window.flutter_inappwebview` into the page; `print.ts` calls `window.flutter_inappwebview.callHandler('FlutterPrint', {type, ...data})` which triggers `_onPrint()` in Dart → USB/TCP print directly. No HTTP round-trip needed.
- **Settings tab** (`lib/screens/home_screen.dart`) — PocketLedger URL field + auto-detect status cards for each printer. Saving the URL reloads the WebView. Printer connections are discovered automatically (see below); manual IP override is available as a collapsible fallback. A collapsible "Debug Logs" panel at the bottom shows timestamped entries from `PrinterDiscovery.logs` (last 200, newest-first) with copy-all and clear buttons — useful for diagnosing USB detection failures. The label printer card shows a **"Configure WiFi"** button when the printer is in SoftAP mode (`DiscoveryStatus.softAp`) or not found (`failed`) — opens `WifiConfigScreen`.

**WiFi config wizard** (`lib/screens/wifi_config_screen.dart`) — guides the user through connecting the label printer to the office network. On Android, Linux, and Windows the wizard **auto-switches WiFi** via `lib/services/wifi_switcher.dart` (see below); on unsupported platforms it falls back to manual instructions. Steps: (1) **auto-switch** to `DEFAULT_AP_CB8F29` (password `12345678`) — if already in `softAp` status, skip to step 2; if auto-switch fails, show manual instructions with error note; (2) poll 192.168.4.1:80 until reachable, then GET `http://192.168.4.1/` (root) and GET `http://192.168.4.1/scanap` — captures any `Set-Cookie` headers from both responses into `_sessionCookie` to relay to the POST; scan returns `{ state: 0, wifilist: [{ssid, mac}] }`; (3) SSID dropdown + password field; (4) **`POST http://192.168.4.1/connap`** — **must use a raw `dart:io Socket`**, not `HttpClient`: Dart's `HttpClient` lowercases all header names (e.g. `content-type`) but the firmware's ESP HTTP parser is case-sensitive and only recognises mixed-case names (`Content-Type`). The raw socket sends headers with the exact capitalisation that jQuery uses: `Content-Type: application/json`, `X-Requested-With: XMLHttpRequest`, `Accept: application/json, text/javascript, */*; q=0.01`, `Origin: http://192.168.4.1`, `Referer: http://192.168.4.1/pages/wifi/station.html`, `Connection: close`, plus the relayed `Cookie` if captured. Body is form-encoded (firmware quirk — form body with JSON Content-Type): `ssid=X&pwd=Y&bssid={mac}&autoconn=undefined`. Values are sent **raw/unencoded**. `autoconn=undefined` is the literal string — the reference `station.html` has no radio button wired to `autoconn`, so JS produces `"autoconn=" + undefined = "autoconn=undefined"`; sending `autoconn=0` or `autoconn=1` triggers additional firmware validation that rejects the request with error 400. BSSID comes from the `mac` field in the `/scanap` response (sent as empty string if absent). Response: `{ state: 0|1, error_code: 400|406|500|600 }` — `state` is the success flag (0 = ok), `error_code` has the failure detail (400 = bad params, 406 = wrong request type, 500 = server error, 600 = wrong password); (5) success screen — in auto mode "Done" fires `WifiSwitcher.reconnect()` fire-and-forget and immediately triggers `scanBarcodeNow()`; discovery's 30-second retry timer picks up the printer's new IP after the WiFi settles; in manual mode the user is instructed to switch back first; (6) on POST failure, shows the sent payload and raw response for debugging, plus a selectable fallback URL `http://192.168.4.1/pages/wifi/station.html` for manual browser config; "Try again" re-enters the auto path.

**Auto WiFi switcher** (`lib/services/wifi_switcher.dart`) — `WifiSwitcher` class handles programmatic WiFi connection on all three platforms:
- **Android** — `wifi_iot` (`WiFiForIoTPlugin.connect(withInternet: false, joinOnce: true)`). On API 29+, this uses `WifiNetworkSpecifier` which binds only the app's traffic to the printer AP without changing the system WiFi; Android may show a system confirmation dialog. `disconnect()` releases the bind and Android auto-reconnects. Requires `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION` in `AndroidManifest.xml` (injected by `patch_manifest.py`).
- **Linux** — `nmcli dev wifi connect DEFAULT_AP_CB8F29 password 12345678` (blocks until connected, ≤30 s timeout). Reconnect uses `nmcli connection up id <ssid>` falling back to `nmcli dev wifi connect <ssid>`.
- **Windows** — writes a WPA2-Personal WLAN profile XML to `%TEMP%`, runs `netsh wlan add profile` then `netsh wlan connect ssid=... name=...`. Reconnect runs `netsh wlan connect` on the original SSID and deletes the temporary printer AP profile afterwards.
- `WifiSwitcher.isSupported` returns true on Android/Linux/Windows; false on macOS/iOS (wizard shows manual instructions).
- `WifiSwitcher.waitForHost(host, port, timeout)` polls TCP until the printer's web interface is reachable after the switch.

**Printer support** (see [`docs-site/src/content/docs/printers/`](docs-site/src/content/docs/printers/) for full hardware specs and WiFi setup, [`docs-site/src/content/docs/installation/linux.md`](docs-site/src/content/docs/installation/linux.md) for Linux CUPS/USB setup, and [`docs-site/src/content/docs/installation/windows.md`](docs-site/src/content/docs/installation/windows.md) for Windows printer installation):
- `lib/services/tspl_printer.dart` — TSPL commands for **TVS LP 46 dlite** (203 DPI). Supports three named templates selectable from print settings: `small` (40×20 mm), `standard` (50×30 mm, default), `large` (60×40 mm). `printBarcode()` accepts a `template` param; `_buildLabel()` dispatches to `_buildSmall/Standard/Large()`. All share the same transport layer (`_sendToConnection`).
- `lib/services/escpos_printer.dart` — ESC/POS bytes for **TVS RP 3230** (80 mm thermal receipt).
- `lib/services/printer_connection.dart` — sealed `PrinterConnection` type: `UsbConnection(path)` or `TcpConnection(ip, port)`. Both printer services accept this and dispatch to the correct transport.
- `lib/services/printer_discovery.dart` — auto-detection singleton (`ChangeNotifier`). Detection chain per platform:
  - **Linux:** CUPS queue via `lpstat -v` (matches `3230`/`lp46`/`dlite` in name or URI) → direct `/dev/usb/lp*` → TCP port 9100 LAN scan
  - **Windows:** Named USB printer via PowerShell `Win32_Printer` (matches `Name` against `3230`/`rp3230` for receipt, `lp46`/`dlite` for label) — stores the printer *display name* (e.g. `TVS RP 3230`), not the USB port name. Raw bytes are sent via the Win32 spooler API (`OpenPrinterA`/`WritePrinter` in `winspool.drv`) invoked through a temp PowerShell script using `Add-Type` P/Invoke — `copy /b` to USB port names fails silently on modern Windows. Falls back to generic USB port probe → TCP scan if no name match. Requires printers installed first (Settings → Printers & scanners → Add device; "Generic / Text Only" driver, name must contain `TVS RP 3230` / `TVS LP 46`). When no match is found, `Get-PnpDevice` is logged for diagnostics.
  - **Android:** TCP port 9100 LAN scan only
  - Label printer additionally recognises `192.168.4.1` (SoftAP mode) — sets `DiscoveryStatus.softAp` (not `found`) so the UI can show the "Configure WiFi" wizard. Connection is still persisted so test prints work while on the printer's AP. Retries every 30 s on failure. Discovered connections are persisted in `SharedPreferences` and restored immediately on next launch.

**HTTP API (all on `localhost:8765`) — used when accessing PocketLedger from a browser instead of the WebView:**
- `GET /status` → `{ ok: true }` — used by `print.ts` as the availability check
- `POST /print/barcode` — body: product fields + `show_sku`, `show_price`, `shop_name`, `label_template`
- `POST /print/receipt` — body: all `BillPrintData` fields merged with `PrintSettings` fields

Printer IPs are stored in the companion app's own `SharedPreferences` (configured via its settings screen), not passed in the request body.

**Android background service:** `lib/services/background_service.dart` uses `flutter_background_service` to run the HTTP server in a foreground-service isolate so Android does not kill it while a browser-based user uses the PWA in Chrome. The service is **opt-in** (default off) — controlled by a `background_service_enabled` boolean in `SharedPreferences` (via `SettingsService`). `initBackgroundService()` only configures the service (notification channel + `autoStart: false`); `main.dart` then calls `FlutterBackgroundService().startService()` conditionally. The Settings tab shows a "Keep running in background" toggle (Android only) that starts/stops the service immediately via `startService()` / `invoke('stopService')`. The service isolate listens for `reload_settings` (reload printer IPs after save) and `stopService` (call `service.stopSelf()`). When using the built-in WebView, the app is in the foreground so no background service is needed for the JS channel path.

**Building:** Triggered manually via GitHub Actions (`.github/workflows/build-companion.yml`). The workflow runs `flutter create . --no-pub` to generate platform boilerplate, restores our `lib/` and `pubspec.yaml` via `git checkout`, runs `patch_manifest.py` to inject the foreground-service permissions into `AndroidManifest.xml`, then builds APK (ubuntu runner), Windows exe (windows runner), and Linux binary (ubuntu runner). Per-platform boolean inputs (`build_android`, `build_windows`, `build_linux`) let you build only the platform you need. `version` is optional — omit it to produce downloadable artifacts without creating a GitHub Release; provide it to publish a full release. The Windows job caches pub packages (`%LOCALAPPDATA%\Pub\Cache`, keyed on `pubspec.lock`) and the CMake build output (`companion_app/build/windows`, same key) to cut subsequent builds from ~10 min to ~3-4 min when only Dart code changes. The Linux binary is distributed as a `.tar.gz` of `build/linux/x64/release/bundle/`. Linux users need `wpewebkit` and `libwpe` installed (`sudo pacman -S wpewebkit libwpe` on Arch). The `linux/runner/main.cc` sets `LIBGL_ALWAYS_SOFTWARE=true` at startup to work around a WPE EGL texture compositing issue on Intel/i915 hardware.

**First-time device setup:** Open companion app → Settings tab → enter PocketLedger URL → Save & Open App. Printer connections are detected automatically; no IP entry required. On Linux, register printers in CUPS first (see `docs/linux-setup.md`). On Windows, install each printer via Settings → Printers & scanners → Add device (Generic / Text Only driver, named `TVS RP 3230` and `TVS LP 46`). `window.flutter_inappwebview` is automatically available in the WebView; printing goes directly via the JS channel without any HTTP ping.

### Docs Site (`docs-site/`)

Starlight (Astro) documentation site deployed to GitHub Pages at `https://aadhii-yz.github.io/PocketLedger/`. Built with `npm run build` from `docs-site/`; deployed via `.github/workflows/docs.yml` on push to `master` when `docs-site/**` changes.

**Key files:**
- `astro.config.mjs` — site config: `base: '/PocketLedger'`, sidebar structure, Starlight Footer override that injects the AI prompt box on every page.
- `src/components/AiPromptBox.svelte` — interactive AI assistant widget. Textarea + platform selector (Claude / ChatGPT / Gemini / Perplexity). On submit, prepends a context prefix pointing to `llms-full.txt` and redirects to the chosen platform via `?q=` query param.
- `src/components/AiFooter.astro` — Starlight `Footer` component override; wraps `AiPromptBox` with `client:load` and renders above the default footer.
- `src/pages/llms.txt.ts` — generates `/llms.txt` at build time (standard llms.txt index format listing all pages with URLs).
- `src/pages/llms-full.txt.ts` — generates `/llms-full.txt` at build time by concatenating all docs pages via `import.meta.glob` with `query: '?raw'`; frontmatter stripped. Used as the AI context document.
- `src/content/docs/` — 17 Markdown/MDX content pages: landing (`index.mdx`), getting-started, installation (companion-app, linux, windows, android), user-guide (billing, stock, transfers, manager, admin, print-settings), printers (index, wifi-setup), troubleshooting (index, printing, connection).

**Build command (from `docs-site/`):**
```bash
npm run build   # outputs to docs-site/dist/
npm run dev     # dev server at localhost:4321/PocketLedger
```

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
| `print_settings` | Singleton — shop info, receipt/label template toggles, and QZ Tray printer names (shop_name, shop_address, shop_phone, gst_number, receipt_footer, show_customer_info, show_tax_breakdown, barcode_show_sku, barcode_show_price, receipt_printer, label_printer, label_template). Read by all authenticated users; write by admin/manager only. |
| `system_logs` | Application-level event log (INFO/WARNING/ERROR) |

**Stock is keyed by `(product, location)`** — there is no DB-level unique constraint; uniqueness is enforced in handler logic. `CompleteTransfer` does a find-then-update (not blind insert) for the destination stock record, and returns a 422 if the source has insufficient quantity.

**Indexes:** `idx_stock_product_location` on `stock(product, location)`, `idx_bills_shop_created` on `bills(shop, created DESC)`, `idx_movements_product_location` on `stock_movements(product, location, created DESC)`, `idx_logs_created` on `system_logs(created DESC)`. All applied idempotently via the schema upgrade path.
