---
title: Getting Started
description: Overview of PocketLedger and how to deploy it for your business.
---

PocketLedger is a two-tier web app: a **Go/PocketBase backend** that handles the database, auth, and REST API, and a **SvelteKit PWA frontend** that runs in any browser or as an installable app on Android, Windows, and Linux.

A separate **Flutter companion app** runs locally on your device to bridge the cloud backend to your LAN printers.

## Architecture at a glance

```
          ┌─────────────────────────────────┐
          │   PocketLedger Backend           │
          │   Go + PocketBase (SQLite)       │
          │   Hosted on your server / VPS    │
          └────────────┬────────────────────┘
                       │ HTTPS REST API
          ┌────────────▼────────────────────┐
          │   SvelteKit PWA (browser / PWA) │
          │   Billing · Inventory · Reports │
          └────────────┬────────────────────┘
                       │ localhost:8765 or JS channel
          ┌────────────▼────────────────────┐
          │   Companion App (Flutter)        │
          │   Linux / Windows / Android      │
          │   USB + TCP/IP printer access   │
          └────────────┬────────────────────┘
                       │ USB / TCP 9100
          ┌────────────▼────────────────────┐
          │   Thermal Printers               │
          │   TVS RP 3230 (receipt, 80 mm)  │
          │   TVS LP 46 (label, 50×30 mm)  │
          └─────────────────────────────────┘
```

## Prerequisites

- A server or VPS to host the backend (Linux recommended). The pre-built binary is self-contained — no external database or runtime needed.
- A domain or static IP so the PWA can reach the backend over HTTPS (required for camera barcode scanning on Android).
- Optionally: one or both TVS thermal printers connected via USB or the local network.

## Deployment steps

### 1. Run the backend

Download the latest release binary for your platform from [GitHub Releases](https://github.com/aadhii-yz/PocketLedger/releases), then:

```bash
chmod +x pocketledger
./pocketledger serve --http 0.0.0.0:8090
```

The first launch opens the PocketBase admin UI at `http://localhost:8090/_/`. Create your superadmin account there.

For production, put it behind a reverse proxy (nginx/Caddy) with TLS.

### 2. Bootstrap the schema

On first launch PocketLedger automatically creates all database collections (products, stock, bills, etc.) and seeds a default Warehouse and Shop location. No manual migration needed.

### 3. Create users

In the PocketBase admin UI → **Collections → users**, create accounts with the appropriate role:

| Role | Access |
|---|---|
| `admin` | Full access, system logs, user management |
| `manager` | Reports, stock, billing, locations, users |
| `stock_entry` | Inventory adjustments and transfers only |
| `pos` | Billing at their assigned shop only |

For `pos` users, set the `assigned_shop` field to the location they operate at.

### 4. Install the companion app (if using printers)

See the platform-specific guides:
- [Linux installation](/PocketLedger/installation/linux/)
- [Windows installation](/PocketLedger/installation/windows/)
- [Android installation](/PocketLedger/installation/android/)

### 5. Open the app

Navigate to your backend URL in any browser, or open it in the companion app's built-in WebView. Log in with the account you created, and you'll be routed to the dashboard for your role.

## User roles overview

| Role | Dashboard | What they do |
|---|---|---|
| `admin` | `/admin` | View system logs, manage users |
| `manager` | `/manager` | Reports, all stock operations, user/location management |
| `stock_entry` | `/stock` | Inventory adjustments, products, transfers |
| `pos` | `/billing` | Create bills at their assigned shop |

All roles share the stats overview at `/stats`.
