---
title: Printing Issues
description: Diagnose and fix problems with receipt and label printing.
---

## Nothing prints — no error message

The print fallback chain runs silently. To know which path was taken, open the browser console (F12 → Console) and look for `[print]` log entries.

**Path 1 (Flutter channel):** Only active inside the companion app WebView. If you're in a regular browser, this path is skipped.

**Path 2 (localhost:8765):** Check that the companion app is running. Test: `curl http://localhost:8765/status` — should return `{ "ok": true }`. If connection refused, the companion app's HTTP server isn't running.

**Path 3 (QZ Tray):** Only active if a printer name is set in Print Settings and QZ Tray is installed. Check that QZ Tray is running in your system tray.

**Path 4 (browser dialog):** A new browser window opens — check if it was blocked by a popup blocker.

---

## Linux

### Printer shows "Permission denied" in the Settings tab

Your user doesn't have write permission to `/dev/usb/lp*`. The Settings tab shows the exact fix command — usually:

```bash
sudo usermod -aG lp $USER
```

Log out and back in (or run `newgrp lp` in the current terminal), then click **Scan Now**.

### CUPS queue detected but test print is garbled

The CUPS queue must be set to **raw** mode (no driver filtering). Re-register with `-m raw`:

```bash
sudo lpadmin -p TVS_RP3230 -m raw
```

### `lpstat -v` shows the queue but the companion app says "Not found"

The companion app matches queue names and URIs against `3230`, `rp3230`, `lp46`, `dlite`. If your queue name is something else (e.g. `Printer1`), rename it or add a new queue with a matching name.

```bash
# Check current names
lpstat -v

# Rename a queue (delete and re-add)
sudo lpadmin -x OldName
sudo lpadmin -p TVS_RP3230 -E -v "usb://..." -m raw
```

---

## Windows

### Printer detected but nothing prints

Check that the printer is not paused. In Printers & scanners, right-click the printer → **See what's printing** → **Printer → Resume Printing**.

Look for `OpenPrinter('TVS RP 3230') failed` in the Debug Logs — this means the Windows spooler can't open the printer by that name. The name in the log must exactly match the installed name (case-insensitive but substring match must include `3230`/`rp3230` or `lp46`/`dlite`).

### Test print shows garbled text

The printer is configured with a non-raw driver. The companion app sends raw ESC/POS or TSPL bytes. The printer must be installed with **Generic / Text Only** driver — reinstall it (see [Windows installation](/PocketLedger/installation/windows/)).

### Both printers show as same type

Both USB devices were plugged in simultaneously and Windows assigned them to the same port. Unplug one printer, reinstall just that one, then plug in the second.

---

## Android

### Label printer "Not found" after WiFi setup

After configuring WiFi on the LP46, the app scans the LAN for the printer. If your LAN is large or the scan times out:
- Tap **Scan Now** on the label printer card
- Check your router's DHCP lease table for the printer's new IP
- In the companion app's **Manual override** section (collapsible), enter the IP directly

### Receipt printer "Not found"

The RP 3230's Ethernet interface shows `IP Configuration is ERROR` when no DHCP lease is assigned. Make sure:
- The printer's Ethernet cable is connected to your network
- Your router has a DHCP server active
- Assign a static IP via DHCP reservation (using the printer's MAC `6C:C1:47:45:A1:DC`)

---

## Label printer — wrong size / clipped output

The companion app sends TSPL with `SIZE 50 mm, 30 mm` (50×30 mm label). If your labels are a different size, this isn't configurable yet — open an issue on GitHub.

## Barcode PNG not generating

`GET /api/custom/barcode/{productId}` requires auth. If the barcode image doesn't appear on the label, check that:
1. The product has a barcode value set
2. The auth token is still valid (re-login if expired)
3. The backend server is reachable

You can test directly: `curl -H "Authorization: Bearer TOKEN" https://your-app.example.com/api/custom/barcode/PRODUCT_ID`.
