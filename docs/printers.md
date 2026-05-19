# Printer Specifications

## TVS LP 46 Dlite Plus (Label Printer)

### Identity
| Field | Value |
|---|---|
| Model | TVSE LP 46 Dlite |
| Main Firmware | FV1.050 |
| Command Language | BPLZ (TSPL with ZPL compatibility) |
| Darkness | 15 |

### Print Hardware
| Field | Value |
|---|---|
| Resolution | 203 DPI (864 dots across ~108 mm printhead) |
| Print Width | 864 dots |
| Print Method | Thermal Transfer / Direct Thermal |
| Print Speed | 5.1 IPS |
| Feed / Backfeed Speed | 5 IPS |
| Print Mode | Tear-off |
| Media Type | Gap/Notch |
| Sensor Type | Web (transmissive) |
| Max Label Length | 43" / 1100 mm |
| Label Size (configured) | 50 mm × 30 mm |

### Memory
| Field | Value |
|---|---|
| RAM | 32 MB |
| Onboard Flash | 64 MB |

### Connectivity
| Interface | Details |
|---|---|
| USB | USB 2.0, Baud 115200, 8N1, DTR/DSR handshake. Device node on Linux: `/dev/usb/lp0`. Requires user in `lp` group. |
| Ethernet | Raw TCP port **9100**. IP via DHCP (default `192.168.1.251`). |
| WiFi | Default mode: **SoftAP** — printer creates its own hotspot. SSID: `DEFAULT_AP_CB8F29`, IP: `192.168.4.1:9100`. Can be switched to Station mode via printer web UI at `192.168.4.1` while connected to the AP. |

### USB Test (Linux)
```bash
# Verify device is detected
lsusb | grep -i tvs

# Check device node
ls /dev/usb/

# Add user to lp group if needed
sudo usermod -aG lp $USER && newgrp lp

# Send a raw TSPL test label
printf 'SIZE 50 mm,30 mm\nGAP 3 mm,0\nCLS\nTEXT 10,10,"3",0,1,1,"HELLO WORLD"\nPRINT 1\n' > /dev/usb/lp0
```

### Companion App Integration
- Handled by `companion_app/lib/services/tspl_printer.dart`
- Sends TSPL commands over TCP to the configured WiFi IP:9100
- Printer IP is stored in `SharedPreferences`, configured via the Settings tab
- The JS channel path (`window.FlutterPrint`) triggers the Dart TCP call directly — no HTTP round-trip

---

## TVS RP 3230 (Receipt Printer)

### Identity
| Field | Value |
|---|---|
| Model | TVS-E RP 3230 |
| FW Version | SV1.00.37 |
| CG Version | SV1.00.16 |
| Serial Number | YAN75T033985 |
| Command Language | ESC/POS |

### Print Hardware
| Field | Value |
|---|---|
| Resolution | 203 DPI |
| Paper Width | 80 mm |
| Print Speed | Max 230 mm/s |
| Print Density | Standard |
| Auto Cutter | Enabled |
| Characters Per Line | 48 (Font A) / 64 (Font B) |
| Drawer Support | Yes |
| Buzzer | Standard volume |
| Default Code Page | PC437 (U.S.A. / Standard Europe) |

### Connectivity
| Interface | Details |
|---|---|
| USB | USB 2.0. Device node on Linux: `/dev/usb/lp0`. Requires user in `lp` group. |
| Serial | 115200 baud, 8N1, DTR/DSR handshake |
| Ethernet | Raw TCP port **9100**. MAC: `6C:C1:47:45:A1:DC`. DHCP on — assign a static IP via router DHCP reservation for reliable printing. |

> **Note:** The self-test showed `IP Configuration is ERROR` — the printer had DHCP enabled but received no IP. Ensure the printer is on a network with a DHCP server, or configure a static IP via the printer's web interface / serial console.

### Supported Barcodes
UPC-A, UPC-E, EAN-13, EAN-8, CODE39, CODABAR, ITF, CODE93, CODE128, QRCode, PDF417

### USB Test (Linux)
```bash
# Verify device is detected
lsusb | grep -i tvs

# Check device node
ls /dev/usb/

# Add user to lp group if needed
sudo usermod -aG lp $USER && newgrp lp

# Send a raw ESC/POS test print
printf '\x1b\x40Hello RP3230\x0a\x1d\x56\x41\x00' > /dev/usb/lp0
# ESC @ (init) + text + LF + GS V A 0 (full cut)
```

### Companion App Integration
- Handled by `companion_app/lib/services/escpos_printer.dart`
- Sends ESC/POS bytes over TCP to the configured Ethernet/WiFi IP:9100
- Printer IP stored in `SharedPreferences`, configured via the Settings tab
- The JS channel path (`window.FlutterPrint`) triggers the Dart TCP call directly — no HTTP round-trip
