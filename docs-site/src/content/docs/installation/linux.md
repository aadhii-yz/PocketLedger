---
title: Linux Installation
description: Install the PocketLedger companion app on Linux and configure USB printers via CUPS.
---

import { Aside } from '@astrojs/starlight/components';

## 1. Install system dependencies

The companion app requires WebKit for the embedded browser and WPE for rendering.

**Arch / Manjaro:**
```bash
sudo pacman -S wpewebkit libwpe
```

**Ubuntu / Debian:**
```bash
sudo apt install libwpewebkit-6.0-dev libwpe-1.0-dev
```

<Aside type="note">
The companion app forces software rendering (`LIBGL_ALWAYS_SOFTWARE=true`) at startup to work around a WPE EGL compositing issue on Intel/i915 hardware. No manual configuration needed.
</Aside>

## 2. Download and run the companion app

Download the latest `pocketledger-companion-linux.tar.gz` from [GitHub Releases](https://github.com/aadhii-yz/PocketLedger/releases), then extract and run:

```bash
tar -xzf pocketledger-companion-linux.tar.gz
cd pocketledger_print
./pocketledger_print
```

## 3. Printer setup

Both printers are auto-detected at launch — USB first (via CUPS or direct device node), then the local network. No manual IP entry is needed in most cases.

### Option A — CUPS (recommended)

CUPS is the cleanest path. Once a printer is registered, the companion app detects it automatically via `lpstat -v` and uses `lp -d <queue> -o raw` for printing.

**Find the USB URI for each printer** (with the printer plugged in):

```bash
lpinfo -v | grep -i tvs
# Example output:
#   direct usb://TVS-E/RP3230?serial=YAN75T033985&interface=1
#   direct usb://TVS-E/LP46dlite?serial=CB8F29&interface=1
```

**Register the receipt printer (TVS RP 3230):**
```bash
sudo lpadmin -p TVS_RP3230 -E \
  -v "usb://TVS-E/RP3230?serial=YAN75T033985&interface=1" \
  -m raw
```

**Register the label printer (TVS LP 46):**
```bash
sudo lpadmin -p TVS_LP46 -E \
  -v "usb://TVS-E/LP46dlite?serial=CB8F29&interface=1" \
  -m raw
```

Replace the URI with the exact string from `lpinfo -v`. After registering, restart the companion app — both printers should show as **USB @ TVS_RP3230** / **USB @ TVS_LP46** in the Settings tab.

### Option B — Direct USB device

If you prefer to skip CUPS, add your user to the `lp` group. This is permanent — done once.

```bash
sudo usermod -aG lp $USER
newgrp lp   # apply to the current shell without logging out
```

Or log out and back in. After that, the companion app writes directly to `/dev/usb/lp0`, `/dev/usb/lp1`, etc.

## 4. Detection behaviour

| Connection type | How it's detected |
|---|---|
| CUPS queue | `lpstat -v` — matches `3230`, `rp3230`, `lp46`, `dlite` in queue name or URI |
| Direct USB | `/dev/usb/lp*` with write permission check |
| TCP / WiFi | Port 9100 scan on LAN; label printer also checked at `192.168.4.1` (SoftAP) |

If two USB printers are found, `lp0` → receipt printer, `lp1` → label printer. Use **Manual override** in the Settings tab if they're plugged in the wrong order.

If the USB device is detected but can't be written to, the Settings tab shows a **permission denied** card with the exact fix command.

## 5. First-time configuration

1. Open the companion app → **Settings tab**
2. Enter the **PocketLedger URL** (e.g. `https://your-app.example.com`)
3. Tap **Save & Open App** — the built-in WebView loads the PWA
4. Printer status cards update automatically as devices are detected

Printer connections persist across restarts; the app restores the last known connection immediately and re-verifies in the background.

## USB quick test

Before starting the companion app, verify the raw printer path works:

```bash
# Label printer — sends a TSPL test label
printf 'SIZE 50 mm,30 mm\nGAP 3 mm,0\nCLS\nTEXT 10,10,"3",0,1,1,"TEST"\nPRINT 1\n' > /dev/usb/lp0

# Receipt printer — sends ESC/POS init + text + full cut
printf '\x1b\x40Hello\x0a\x1d\x56\x41\x00' > /dev/usb/lp0
```
