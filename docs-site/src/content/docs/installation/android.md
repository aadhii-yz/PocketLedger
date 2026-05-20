---
title: Android Installation
description: Install PocketLedger on Android — as a PWA or via the companion app APK.
---

import { Aside } from '@astrojs/starlight/components';

You have two options on Android:

| Option | Use case |
|---|---|
| **Browser PWA** (no install) | Billing and inventory without printing |
| **Companion app APK** | Full printing support (receipt + label via TCP/WiFi) |

## Option A — Install as a PWA

1. Open your PocketLedger URL in **Chrome** on Android
2. Tap the **"Add to Home Screen"** prompt (or Menu → Add to Home screen)
3. The app installs as a standalone PWA — it opens without browser chrome and caches data for offline use

<Aside type="caution">
Camera barcode scanning requires HTTPS. If your backend is on a plain `http://` local IP, Chrome will block camera access. Use a domain with a valid TLS certificate.
</Aside>

## Option B — Install the companion app APK

The companion APK gives you the PWA in a WebView plus local HTTP printing support.

1. Download the latest `pocketledger-companion.apk` from [GitHub Releases](https://github.com/aadhii-yz/PocketLedger/releases)
2. Enable **Install from unknown sources** in Settings → Apps → Special app access (Android 8+) and allow the file manager / browser
3. Tap the downloaded APK to install
4. Open the app → **Settings tab**
5. Enter the **PocketLedger URL** → **Save & Open App**

### Printer setup on Android

Android only supports **TCP/WiFi printing** (no USB). The companion app scans the local network for devices on port 9100 automatically.

For the **TVS LP 46 label printer:**
- If the printer is in its default SoftAP mode (`DEFAULT_AP_CB8F29` hotspot), the Settings tab shows a **Configure WiFi** button — use the [WiFi setup wizard](/PocketLedger/printers/wifi-setup/) to connect it to your office network
- Once on your WiFi, the printer is auto-detected on the LAN

For the **TVS RP 3230 receipt printer:**
- Connect it via Ethernet or WiFi to the same network as your Android device
- It will be auto-detected on port 9100 — no IP entry needed
- Assign it a static IP via your router's DHCP reservation for stable detection

### Background service

The companion app runs a foreground background service so Android doesn't kill the HTTP server when the app is backgrounded. This is needed if you use the PWA in Chrome and the companion app side-by-side. When using the built-in WebView (App tab), no background service is involved.

## Permissions

| Permission | Reason |
|---|---|
| Camera | Barcode scanning in billing and stock |
| Foreground service | Keep HTTP server alive for browser-based users |
| Internet | Connect to PocketLedger backend |
| Local network | Discover and connect to printers on LAN |

## Barcode scanning

The PWA uses the native `BarcodeDetector` API on Android (zero extra JS). A camera button appears automatically on touch devices. Tap it to open the full-screen scanner. No additional setup required.
