---
title: Troubleshooting
description: Common issues with PocketLedger and how to diagnose them.
---

## Quick diagnosis

### Is the companion app running?

Open the companion app → **Settings tab**. Each printer card shows its current status:

| Status | Meaning |
|---|---|
| **USB @ queue-name** | Detected via CUPS queue (Linux) or Win32 printer (Windows) |
| **USB @ /dev/usb/lp0** | Detected via direct device node (Linux) |
| **TCP @ 192.168.x.x:9100** | Detected on the network |
| **SoftAP @ 192.168.4.1** | Label printer is in factory default AP mode |
| **Not found** | Auto-detection failed |
| **Permission denied** | USB device found but can't write (Linux — see fix command shown) |

### Check Debug Logs

Scroll to the bottom of the Settings tab and expand **Debug Logs**. This shows timestamped entries from the detection process. The most recent entry is at the top.

### Force re-detection

Click **Scan Now** on any printer card to re-run detection without restarting the app.

---

## Common issues

### App shows a blank white screen

The PocketLedger URL in Settings isn't reachable.

- Check that the backend is running (`curl https://your-app.example.com/api/health`)
- Verify the URL includes `https://` — plain `http://` is blocked for camera access
- Check your network connection

### Login fails / "Invalid credentials"

- Confirm the user exists in the PocketBase admin UI at `/_/`
- Check that the user's `role` field is set — accounts without a role get a generic dashboard with no content
- Password reset: in the PocketBase admin UI, edit the user and set a new password

### Stock quantity didn't update after billing

Billing and stock deduction happen in a single atomic transaction. If the bill shows as created but stock didn't decrease:
- Check System Logs (`/admin/logs`) for any `ERROR` entries around the bill creation time
- The transaction failure would have rolled back the bill too — so if the bill exists, the stock change happened

### Transfer failed with "insufficient stock"

`CompleteTransfer` checks source quantity before writing. Verify the source location has enough stock via the inventory page. The source quantity must be ≥ the transfer quantity at the time of completion (not at creation time).

---

## Platform-specific issues

- [Printing issues →](/PocketLedger/troubleshooting/printing/)
- [Connection / network issues →](/PocketLedger/troubleshooting/connection/)
