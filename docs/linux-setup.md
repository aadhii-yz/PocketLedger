# Linux Setup Guide

## 1. Install system dependencies

### Arch / Manjaro
```bash
sudo pacman -S wpewebkit libwpe
```

### Ubuntu / Debian
```bash
sudo apt install libwpewebkit-6.0-dev libwpe-1.0-dev
```

> **Note:** The companion app forces software rendering (`LIBGL_ALWAYS_SOFTWARE=true`) at startup to work around a WPE EGL compositing issue on Intel/i915 hardware. No manual configuration needed.

---

## 2. Download the companion app

Download the latest `pocketledger-companion-linux.tar.gz` from the [GitHub Releases](../../releases) page, then extract and run:

```bash
tar -xzf pocketledger-companion-linux.tar.gz
cd pocketledger_print
./pocketledger_print
```

---

## 3. Printer setup

Both printers are auto-detected at launch — USB first (via CUPS or direct device), then the local network. No manual IP entry is needed in most cases.

### Option A — CUPS (recommended, no extra permissions needed)

CUPS is the cleanest path. Once a printer is registered, the companion app detects it automatically via `lpstat -v` and uses `lp -d <queue> -o raw` for printing.

**Find the USB URI for each printer (with the printer plugged in):**

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

---

### Option B — Direct USB device (requires `lp` group, one-time setup)

If you prefer to skip CUPS, add your user to the `lp` group. This is a permanent change — you only need to do it once, not on every plug/unplug.

```bash
sudo usermod -aG lp $USER
newgrp lp          # apply to the current shell without logging out
```

Or log out and back in. After that, the companion app writes directly to `/dev/usb/lp0`, `/dev/usb/lp1`, etc.

---

## 4. Printer detection behaviour

| Platform | Detection chain |
|---|---|
| Linux | CUPS queue (`lpstat -v`) → `/dev/usb/lp*` → TCP port 9100 scan on LAN |
| Windows | Named USB printer (`Win32_Printer`, matched by name) → generic USB port fallback → TCP scan (see [windows-setup.md](windows-setup.md)) |
| Android | TCP port 9100 scan on LAN only |

If **two USB printers** are found, the first device (`lp0`) is assigned to the receipt printer and the second (`lp1`) to the label printer. Use **Manual override** in the Settings tab to swap them if plugged in the wrong order.

If the USB device is detected but can't be written to, the Settings tab shows a **permission denied** card with the exact fix command.

The label printer falls back to **WiFi auto-detect** (TCP scan finds it on the LAN if in Station mode, or at `192.168.4.1` if in its default SoftAP mode). Network detection retries automatically every 30 seconds.

---

## 5. First-time app configuration

1. Open the companion app → **Settings tab**
2. Enter the **PocketLedger URL** (e.g. `https://your-app.pockethost.io`)
3. Tap **Save & Open App** — the built-in WebView loads the PWA
4. Printer status cards update automatically as devices are detected

Printer connections are persisted across restarts; the app restores the last known connection immediately and re-verifies in the background.
