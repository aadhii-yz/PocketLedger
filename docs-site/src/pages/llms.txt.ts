import type { APIRoute } from 'astro';

// llms.txt — standard index format for AI discovery.
// See https://llmstxt.org for the specification.
const BASE = 'https://aadhii-yz.github.io/PocketLedger';

export const GET: APIRoute = () => {
    const content = `\
# PocketLedger
> Multi-location inventory and billing system for retail businesses.
> Backend: Go/PocketBase. Frontend: SvelteKit PWA. Companion app: Flutter (USB/WiFi printing).

## Docs

- [Getting Started](${BASE}/getting-started/): What PocketLedger is and how to deploy it
- [Companion App Overview](${BASE}/installation/companion-app/): What the companion app does and when you need it
- [Linux Installation](${BASE}/installation/linux/): Companion app setup, CUPS printer registration, USB permissions
- [Windows Installation](${BASE}/installation/windows/): Companion app setup, printer install via Windows Printers & scanners
- [Android Installation](${BASE}/installation/android/): APK install, WiFi printing setup
- [Billing / POS](${BASE}/user-guide/billing/): Point-of-sale operations — scanning, cart, payment, receipts
- [Inventory](${BASE}/user-guide/stock/): Stock levels, adjustments, product catalogue, barcode generation
- [Stock Transfers](${BASE}/user-guide/transfers/): Moving stock between warehouse and shops
- [Manager Guide](${BASE}/user-guide/manager/): Dashboard, sales reports, user management, locations
- [Admin Guide](${BASE}/user-guide/admin/): System logs, user roles, maintenance
- [Print Settings](${BASE}/user-guide/print-settings/): Receipt and label template options, QZ Tray, printer names
- [Printer Hardware](${BASE}/printers/index/): TVS LP 46 (label) and TVS RP 3230 (receipt) specs and connectivity
- [Printer WiFi Setup](${BASE}/printers/wifi-setup/): Configuring the LP46 label printer to join your WiFi network
- [Troubleshooting Overview](${BASE}/troubleshooting/index/): Common issues and diagnostic steps
- [Printing Troubleshooting](${BASE}/troubleshooting/printing/): Printer not found, garbled output, test print failures
- [Connection Troubleshooting](${BASE}/troubleshooting/connection/): Network, HTTPS, camera access issues

## Full Documentation (for AI context)

- [llms-full.txt](${BASE}/llms-full.txt): All pages concatenated into a single file
`;

    return new Response(content, {
        headers: { 'Content-Type': 'text/plain; charset=utf-8' },
    });
};
