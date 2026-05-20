# Windows Setup Guide

## 1. Download the companion app

Download the latest `pocketledger-companion-windows.zip` from the [GitHub Releases](../../releases) page, then extract and run `pocketledger_print.exe` from the extracted folder.

No installation required — just run the exe directly.

---

## 2. Printer setup

Both printers must be registered in Windows before the companion app can detect them. This is a one-time setup.

### Step 1 — Install the printers in Windows

1. Open **Settings → Bluetooth & devices → Printers & scanners**
2. Click **Add device** and wait for the scan
3. If the printer appears in the list, select it and install it

If the printer is not found automatically:

1. Click **Add manually** (the small link under the scan results)
2. Select **"Add a local printer or network printer with manual settings"**
3. **Port:** choose **Use an existing port** → select `USB001` (or `USB002` for the second printer). If no USB port is listed, select **"Create a new port"** → type `USB001`
4. **Driver:** click **Windows Update** to load the full list, then search for **Generic** → select **Generic / Text Only**
   - Alternatively: click **Have Disk** → skip, then choose **Generic** in the manufacturer list
5. **Printer name:** enter exactly:
   - `TVS RP 3230` for the receipt printer
   - `TVS LP 46` for the label printer
6. Click **Next** → **Finish**

Repeat for the second printer, using `USB002` as the port.

> The printer name must contain `3230` or `rp3230` (receipt) and `lp46` or `dlite` (label) — the companion app matches on these strings to identify which printer is which.

### Step 2 — Verify

Open **Printers & scanners** and confirm both printers appear with the correct names. You can right-click → **Printer properties** → **Print Test Page** to confirm Windows can reach them, though the test page may be garbled (Generic / Text Only sends raw bytes, not formatted text).

---

## 3. Download and run the companion app

After the printers are installed:

1. Extract `pocketledger-companion-windows.zip`
2. Run `pocketledger_print.exe`
3. Go to the **Settings tab**
4. Both printers should show as **USB @ TVS RP 3230** / **USB @ TVS LP 46 DLITE** (the printer display name, not the port)

If detection still fails, expand **Debug Logs** at the bottom of the Settings tab. Look for:

- `Win PS stdout="<empty>"` → printer not registered in Windows (repeat Step 1)
- `Win printer: name="..." port="..."` → printer found but name doesn't match — the name shown in the log must contain `3230` / `rp3230` (receipt) or `lp46` / `dlite` (label). Rename the printer in Windows to match.
- `Win: matched receipt → TVS RP 3230 (port USB001)` → detected correctly

---

## 4. Printer detection behaviour

| Platform | Detection chain |
|---|---|
| Linux | CUPS queue (`lpstat -v`) → `/dev/usb/lp*` → TCP port 9100 scan on LAN |
| Windows | Named USB printer (`Win32_Printer`, matched by name) → generic USB port fallback → TCP scan |
| Android | TCP port 9100 scan on LAN only |

On Windows, printer identity (receipt vs. label) is determined by the Windows printer name, not the port. If both printers are on the same port or assigned in the wrong order, use **Manual override** in the Settings tab.

The label printer also supports **WiFi auto-detect** — if no USB match is found, the app scans the LAN for a device on port 9100. It also checks `192.168.4.1` for the printer's default SoftAP mode. Network detection retries every 30 seconds.

---

## 5. First-time app configuration

1. Open the companion app → **Settings tab**
2. Enter the **PocketLedger URL** (e.g. `https://your-app.pockethost.io`)
3. Click **Save & Open App** — the built-in WebView loads the PWA
4. Printer status cards update automatically as devices are detected

Printer connections are persisted across restarts; the app restores the last known connection immediately and re-verifies in the background.

---

## Troubleshooting

**Printer detected but nothing prints**

The app sends raw bytes via the Windows spooler API (`OpenPrinter`/`WritePrinter`). If detection shows the printer name correctly but test print fails, check that the printer is not paused (right-click the printer in Settings → Resume). If the error appears in Debug Logs (e.g. `OpenPrinter('TVS RP 3230') failed`), the printer name in the log must exactly match the installed name — rename it in Windows if needed.

**Both printers assigned to the same printer type**

Windows may assign both USB devices to the same port name if they were plugged in simultaneously. Unplug one, install it, then plug in the second.

**App shows "Not found" after printer is installed**

Click **Scan Now** on the printer card to re-run detection without restarting the app. Detection runs automatically at startup and after each 30-second retry cycle.
