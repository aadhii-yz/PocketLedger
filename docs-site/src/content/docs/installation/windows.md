---
title: Windows Installation
description: Install the PocketLedger companion app on Windows and register USB printers.
---

import { Aside, Steps } from '@astrojs/starlight/components';

## 1. Install the printers in Windows

Both printers must be registered in Windows before the companion app can detect them. This is a one-time setup.

<Steps>
1. Open **Settings → Bluetooth & devices → Printers & scanners**
2. Click **Add device** and wait for the scan
3. If the printer appears, select it and install it

   If not found automatically, click **Add manually** (the small link under the scan results):
   - Select **"Add a local printer or network printer with manual settings"**
   - **Port:** choose **Use an existing port** → select `USB001` (or `USB002` for the second printer). If no USB port appears, select **Create a new port** → type `USB001`
   - **Driver:** click **Windows Update** to load the full list → search **Generic** → select **Generic / Text Only**
   - **Printer name:** enter exactly:
     - `TVS RP 3230` for the receipt printer
     - `TVS LP 46` for the label printer
   - Click **Next → Finish**

4. Repeat for the second printer using `USB002` as the port
</Steps>

<Aside type="caution">
The printer name must contain `3230` or `rp3230` (receipt) and `lp46` or `dlite` (label). The companion app matches on these strings. Typos in the name will cause "Not found" in the app.
</Aside>

**Verify:** Open **Printers & scanners** and confirm both printers appear. Right-click → **Printer properties → Print Test Page** to confirm Windows can reach them (the test page will be garbled — that's expected for Generic / Text Only with a thermal printer).

## 2. Download and run the companion app

Download the latest `pocketledger-companion-windows.zip` from [GitHub Releases](https://github.com/aadhii-yz/PocketLedger/releases), extract it, and run `pocketledger_print.exe`.

No installation required — just run the exe directly.

## 3. First-time configuration

1. Open the companion app → **Settings tab**
2. Both printers should show as **USB @ TVS RP 3230** / **USB @ TVS LP 46 DLITE**
3. Enter the **PocketLedger URL** (e.g. `https://your-app.example.com`)
4. Click **Save & Open App** — the built-in WebView loads the PWA

## 4. Detection behaviour

The companion app uses PowerShell's `Win32_Printer` to find printers by display name. Raw bytes are sent via the Win32 spooler API (`OpenPrinterA` / `WritePrinter` in `winspool.drv`) — this bypasses the `copy /b` approach which fails silently on modern Windows.

Fallback chain: USB name match → generic USB port probe → TCP port 9100 LAN scan.

## Troubleshooting detection

If detection fails, expand **Debug Logs** at the bottom of the Settings tab:

| Log entry | Meaning | Fix |
|---|---|---|
| `Win PS stdout="<empty>"` | Printer not registered in Windows | Repeat Step 1 |
| `Win printer: name="..." port="..."` | Printer found but name doesn't match | Rename the printer in Windows to match |
| `Win: matched receipt → TVS RP 3230` | Detected correctly | — |
| `OpenPrinter('TVS RP 3230') failed` | Printer paused or spooler error | Right-click printer → Resume |

If both printers are assigned to the same port name (plugged in simultaneously), unplug one, install it alone, then plug in the second.
