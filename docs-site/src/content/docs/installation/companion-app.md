---
title: Companion App
description: What the PocketLedger companion app does and when you need it.
---

The companion app is a **Flutter app** that runs locally on the same device (or same network) as your thermal printers. It exists because:

- The backend is cloud-hosted and can't reach printers on your local network.
- Browsers can't open raw TCP sockets or USB devices.

The companion app bridges this gap by exposing a local HTTP server on `localhost:8765` that the PWA can call, and by embedding the PocketLedger PWA in a WebView with a direct JavaScript channel for printing.

## Two printing paths

### Path 1 — Built-in WebView (preferred)

When you open PocketLedger inside the companion app's **App tab**, the page has access to `window.flutter_inappwebview`. When a receipt or label needs to print, the PWA calls:

```js
window.flutter_inappwebview.callHandler('FlutterPrint', { type: 'receipt', ...data })
```

The Dart code receives this and sends raw bytes to the printer over USB or TCP immediately — no HTTP round-trip, no port conflicts.

### Path 2 — Browser + companion app running alongside

If you prefer to use PocketLedger in a regular browser (Chrome, Firefox, etc.) while the companion app runs in the background, the PWA:

1. Checks `GET http://localhost:8765/status` — if OK, uses Path 2.
2. Posts to `POST http://localhost:8765/print/receipt` or `/print/barcode`.

The companion app's background service keeps the HTTP server alive on Android even when the app is backgrounded.

## App tabs

### App tab

Embeds the configured PocketLedger URL in a WebView with full JavaScript channel support. This is the simplest setup — one app, no browser needed.

### Settings tab

- **PocketLedger URL** — the address of your hosted backend. Save & Open App to load it in the WebView.
- **Printer status cards** — one card per printer, showing the detected connection (USB queue name, direct device path, or TCP IP:port). Each card has **Scan Now**, **Test Print**, and a collapsible **Manual override** section.
- **Debug Logs panel** — shows the last 200 timestamped detection log entries. Useful for diagnosing USB detection failures. Copy-all and clear buttons included.
- **Configure WiFi** button — appears on the label printer card when the printer is in SoftAP mode. Opens the [WiFi setup wizard](/PocketLedger/printers/wifi-setup/).

## When do you need the companion app?

| Scenario | Need companion app? |
|---|---|
| Using printers (USB or WiFi) | **Yes** — on every device that prints |
| Browser-only, no printing | No |
| Camera barcode scanning | No (built into the PWA) |
| Offline PWA caching | No |

## Supported platforms

| Platform | Receipt printer | Label printer | Notes |
|---|---|---|---|
| Linux | USB (CUPS or direct) + TCP | USB (CUPS or direct) + TCP | See [Linux setup](/PocketLedger/installation/linux/) |
| Windows | USB (Win32 spooler) + TCP | USB (Win32 spooler) + TCP | See [Windows setup](/PocketLedger/installation/windows/) |
| Android | TCP only | TCP only (+ WiFi config wizard) | See [Android setup](/PocketLedger/installation/android/) |
