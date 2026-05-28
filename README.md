# PocketLedger

A minimal yet powerful web-based **Inventory** and **Billing** system for small businesses, with silent thermal and label printing support.

> [!CAUTION]
> Currently under development

---

## Table of Contents

- [Stack](#stack)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation & Running](#installation--running)
  - [Development](#development)
- [Project Structure](#project-structure)
- [User Roles](#user-roles)
- [Data Model](#data-model)
- [API Reference](#api-reference)
- [Architecture Notes](#architecture-notes)
- [Companion App](#companion-app)
- [Documentation](#documentation)
- [License](#license)

---

## Stack

| Layer | Technology |
|---|---|
| Backend | Go + [PocketBase](https://pocketbase.io/) (SQLite, auth, REST API) |
| Frontend | [SvelteKit](https://svelte.dev/) — static SPA, Svelte 5 runes, PWA |
| Companion App | Flutter — silent printing + embedded WebView |
| Docs Site | [Starlight](https://starlight.astro.build/) (Astro) |

---

## Getting Started

### Prerequisites

- Go 1.26+
- Node.js 18+
- `make`
- Flutter SDK 3.x _(companion app only)_

### Installation & Running

```bash
make run         # build frontend + backend, then serve at http://localhost:8090
```

Other make targets:

```bash
make build       # build only (frontend + backend + copy assets)
make clean       # remove build artifacts
```

### Development

```bash
# frontend — hot reload, no backend needed
make dev-frontend

# backend — build and serve
cd backend && go build -o backend . && ./backend serve
```

Create `frontend/.env` for local dev:

```env
VITE_PB_URL=http://localhost:8090
```

---

## Project Structure

```
PocketLedger/
├── backend/          # Go/PocketBase backend
├── frontend/         # SvelteKit PWA
├── companion_app/    # Flutter companion app (silent printing)
├── docs-site/        # Starlight documentation site
└── docs/             # Setup guides (Linux, Windows, VPS, printers)
```

---

## User Roles

| Role | Dashboard | Access |
|---|---|---|
| `admin` | `/admin` | User management, system config, logs |
| `manager` | `/manager` | Reports, sales, stock overview, transfers, stats, print settings |
| `pos` | `/billing` | Create bills for their assigned shop only |
| `stock_entry` | `/stock` | Inventory, products, stock movements, transfers, stats |

- `pos` users are restricted to their `assigned_shop` — billing loads only that shop's stock
- `manager` and `stock_entry` are unrestricted — they pick a shop at bill time and can access all locations
- `stock_entry` cannot update stock quantities directly via the REST API — all changes must go through `POST /api/custom/stock/adjust`

---

## Data Model

| Collection | Purpose |
|---|---|
| `locations` | Warehouse and shop locations (`type`: warehouse\|shop, `is_active`) |
| `users` | PocketBase auth extended with `role` and `assigned_shop` (RelationField → locations) |
| `categories` | Product categories |
| `products` | Catalogue — SKU, barcode, prices, tax rate, `details` (JSON key-value attributes) |
| `stock` | Current quantity + low-stock threshold per **(product, location)** pair |
| `stock_movements` | Audit log of every stock change; scoped to a `location` |
| `stock_transfers` | Transfer headers (`TRF-XXXX`, from/to locations, status: pending\|completed\|cancelled) |
| `stock_transfer_items` | Line items per transfer (product snapshot, quantity) |
| `bills` | Invoice headers scoped to a `shop`; payment_method includes `credit` |
| `bill_items` | Line items with price snapshot at sale time |
| `print_settings` | Singleton — shop info, receipt/label template toggles, QZ Tray printer names |
| `system_logs` | Application event log (INFO / WARNING / ERROR) |

---

## API Reference

All custom routes are under `/api/custom` and require authentication.

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

---

## Architecture Notes

- Custom API routes registered in `backend/main.go`; one handler file per domain under `backend/handlers/`
- Schema bootstrap in `backend/collections/schema.go` — idempotent, runs at startup; seeds default warehouse/shop locations
- Billing, stock adjustments, and transfer completion are fully transactional (SQLite, rolled back on failure)
- Bill numbering: sequential `INV-XXXX`; transfer numbering: sequential `TRF-XXXX`
- All raw SQL uses parameterised queries — no string-concatenated user input
- Built frontend (`frontend/build/`) is copied to `backend/pb_public/` and served as a static site
- PWA with Workbox offline caching: reference data is `StaleWhileRevalidate`; stock and billing routes are `NetworkOnly`
- Barcode scanning via native `BarcodeDetector` (Android) with `@zxing/browser` fallback (iOS)
- Barcode labels: Code128 PNG generated server-side (`services/barcode.go`); three label templates (small/standard/large) for TVS LP 46 dlite

---

## Companion App

The Flutter companion app (`companion_app/`) bridges the browser PWA to local USB/TCP printers — something a cloud-hosted backend and browser alone cannot do.

**Two operating modes:**

| Mode | How it works |
|---|---|
| Embedded WebView | Loads the SvelteKit PWA; print calls go via `window.flutter_inappwebview` JS channel directly to the printer — no HTTP round-trip |
| Browser sidecar | Runs a local HTTP server on `localhost:8765`; exposes `POST /print/receipt` and `POST /print/barcode` for browser users |

**Supported printers:**

| Printer | Protocol | Notes |
|---|---|---|
| TVS RP 3230 | ESC/POS | 80 mm thermal receipt |
| TVS LP 46 dlite | TSPL | Label printer; small / standard / large templates |

**Key features:**
- **Auto printer discovery** — USB (CUPS on Linux, Win32 spooler on Windows), TCP LAN scan on all platforms. Connections are persisted and restored on next launch.
- **WiFi config wizard** — step-by-step SoftAP setup for the label printer; auto-switches WiFi on Android, Linux, and Windows.
- **Background service** (Android, opt-in) — keeps the HTTP server alive when using the PWA in Chrome instead of the built-in WebView.

**CI builds** are triggered via GitHub Actions (`.github/workflows/build-companion.yml`). Per-platform toggles (`build_android`, `build_windows`, `build_linux`). Provide a `version` input to publish a GitHub Release.

---

## Documentation

Full documentation is available at **[https://aadhii-yz.github.io/PocketLedger/](https://aadhii-yz.github.io/PocketLedger/)**.

Covers installation, printer setup, user guides, and troubleshooting. Each page includes an AI assistant widget (Claude / ChatGPT / Gemini / Perplexity) backed by an auto-generated `llms-full.txt`.

To run the docs site locally:

```bash
cd docs-site && npm run dev    # dev server at localhost:4321/PocketLedger
cd docs-site && npm run build  # output to docs-site/dist/
```

---

## License

[MIT](LICENSE) © Adithya and Nitheshkumar
