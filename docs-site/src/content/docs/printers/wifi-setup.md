---
title: WiFi Setup — LP46 Label Printer
description: Configure the TVS LP 46 label printer to join your office WiFi network.
---

import { Aside, Steps } from '@astrojs/starlight/components';

The TVS LP 46 ships in **SoftAP mode** — it creates its own WiFi hotspot (`DEFAULT_AP_CB8F29`) instead of joining your office network. To print over WiFi, you must configure it once to connect as a Station (client) to your router.

The companion app has a built-in WiFi setup wizard that guides you through this.

<Aside type="tip">
The **Configure WiFi** button appears on the label printer card in the companion app's Settings tab when the printer status is "SoftAP" or "Not found". You don't need to find this guide — the wizard guides you step by step.
</Aside>

## Prerequisites

- The companion app installed on your Android or desktop device
- The TVS LP 46 powered on (in its default SoftAP mode)
- Your office WiFi SSID and password

## Setup steps

<Steps>
1. **Open the companion app → Settings tab**

   The label printer card should show status **SoftAP** or **Not found**. Tap **Configure WiFi**.

2. **Connect to the printer's hotspot**

   The wizard instructs you to go to your device's WiFi settings and connect to:
   - SSID: `DEFAULT_AP_CB8F29`
   - Password: `12345678`

   Come back to the app and tap **Continue**.

3. **Scan for available networks**

   The app sends `GET http://192.168.4.1/scanap` to the printer's built-in web server. A dropdown appears with all WiFi networks the printer can see.

4. **Select your network and enter the password**

   Pick your office SSID from the dropdown and enter the password.

5. **Connect**

   The app posts the credentials to the printer (`POST http://192.168.4.1/connap`). On success, the printer reboots into Station mode and joins your office network.

6. **Switch back to your office WiFi**

   The wizard reminds you to reconnect your device to the office network. Tap **Done** — the app immediately scans the LAN to find the printer at its new IP and saves the connection.
</Steps>

## What if the wizard fails?

If the POST to the printer fails (wrong endpoint for your firmware version, or network timeout), the wizard shows a fallback URL:

```
http://192.168.4.1/pages/wifi/station.html
```

Copy this URL, open it in a browser while still connected to `DEFAULT_AP_CB8F29`, and configure the WiFi manually through the printer's built-in web page.

## After setup

Once the printer has joined your office network:
- The companion app finds it automatically via TCP port 9100 scan on the LAN
- The detected IP is saved in the app's preferences and restored on next launch
- The **Configure WiFi** button disappears — the printer card shows its connection status normally

If the printer is later moved to a different network or reset to factory defaults, its SoftAP mode returns and the button reappears.

## Factory reset

To reset the printer to SoftAP mode, hold the printer's feed button for 5 seconds while powering on (consult your printer manual for the exact sequence). After reset, the WiFi setup wizard is available again.
