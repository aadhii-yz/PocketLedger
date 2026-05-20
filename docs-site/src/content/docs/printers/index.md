---
title: Printer Hardware
description: Specifications and connectivity details for the TVS LP 46 and TVS RP 3230 thermal printers.
---

PocketLedger supports two TVS thermal printers. Both are auto-detected by the companion app — USB first, then TCP/IP on the local network.

## TVS LP 46 Dlite Plus — Label Printer

Prints barcode labels at 50 mm × 30 mm.

### Specs

| | |
|---|---|
| Command language | TSPL (BPLZ — TSPL with ZPL compatibility) |
| Resolution | 203 DPI (864 dots / ~108 mm printhead) |
| Print width | 864 dots |
| Print speed | 5.1 IPS |
| Label size | 50 mm × 30 mm (configured) |
| Max label length | 1100 mm |
| Media type | Gap/Notch, thermal transfer / direct thermal |
| RAM | 32 MB |
| Flash | 64 MB |

### Connectivity

| Interface | Details |
|---|---|
| USB | USB 2.0, device node `/dev/usb/lp*` on Linux. Requires user in `lp` group. |
| Ethernet | TCP port **9100**. DHCP (default `192.168.1.251`) |
| WiFi | **Default: SoftAP mode** — printer creates hotspot `DEFAULT_AP_CB8F29` (password `12345678`), IP `192.168.4.1:9100`. Switch to Station mode via the [WiFi setup wizard](/PocketLedger/printers/wifi-setup/) |

### Default SoftAP behaviour

Out of the box, the LP46 creates its own WiFi hotspot. To use it on your office network, you must configure it to join as a Station. The companion app shows a **Configure WiFi** button on the label printer card when the printer is in SoftAP mode.

### USB test (Linux)

```bash
printf 'SIZE 50 mm,30 mm\nGAP 3 mm,0\nCLS\nTEXT 10,10,"3",0,1,1,"HELLO"\nPRINT 1\n' > /dev/usb/lp0
```

---

## TVS RP 3230 — Receipt Printer

Prints 80 mm thermal receipts with auto-cutter.

### Specs

| | |
|---|---|
| Command language | ESC/POS |
| Resolution | 203 DPI |
| Paper width | 80 mm |
| Print speed | 230 mm/s max |
| Characters per line | 48 (Font A) / 64 (Font B) |
| Auto cutter | Yes |
| Barcode support | UPC-A/E, EAN-13/8, Code 39/93/128, QR, PDF417 |
| Drawer support | Yes |

### Connectivity

| Interface | Details |
|---|---|
| USB | USB 2.0, device node `/dev/usb/lp*` on Linux |
| Serial | 115200 baud, 8N1, DTR/DSR handshake |
| Ethernet | TCP port **9100**, DHCP enabled. Assign a static IP via router DHCP reservation for reliable detection |

### Static IP recommendation

The RP 3230 uses DHCP by default. Assign it a static IP via your router's DHCP reservation (using its MAC address) so the companion app can reliably find it after restarts.

### USB test (Linux)

```bash
# ESC @ (init) + text + LF + GS V A 0 (full cut)
printf '\x1b\x40Hello RP3230\x0a\x1d\x56\x41\x00' > /dev/usb/lp0
```

---

## Auto-detection summary

| Platform | Receipt (RP 3230) | Label (LP 46) |
|---|---|---|
| Linux | CUPS queue → `/dev/usb/lp*` → TCP 9100 scan | CUPS queue → `/dev/usb/lp*` → TCP 9100 scan → SoftAP `192.168.4.1` |
| Windows | Win32_Printer by name → USB port fallback → TCP scan | Win32_Printer by name → USB port fallback → TCP scan → SoftAP |
| Android | TCP 9100 scan | TCP 9100 scan → SoftAP `192.168.4.1` |

Connections are persisted in SharedPreferences and restored on next launch.
