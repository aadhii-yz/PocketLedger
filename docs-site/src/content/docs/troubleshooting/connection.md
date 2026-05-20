---
title: Connection Issues
description: Fix network, HTTPS, and API connection problems.
---

## Backend unreachable

Test the backend directly:

```bash
curl https://your-app.example.com/api/health
# Expected: {"code":200,"message":"API is healthy.","data":{}}
```

If this fails:
- Check that the backend process is running (`ps aux | grep pocketledger` or check your process manager)
- Check the firewall — port 8090 (or your reverse proxy port 80/443) must be open
- Check the reverse proxy config (nginx/Caddy) — the `proxy_pass` must point to `http://127.0.0.1:8090`

## PWA shows offline banner

The **offline indicator** at the bottom of the screen appears when `navigator.onLine` is false or when the API call to PocketBase fails.

Common causes:
- No network connection on the device
- Backend is down (see above)
- CORS error — if you're accessing the backend from a different origin, check PocketBase's CORS settings in the admin UI (`/_/` → Settings → Application → Allowed origins)

## Camera barcode scanning not working

Camera access requires a **secure context** (HTTPS or `localhost`). Plain `http://` on a local IP is blocked by Chrome/Safari on Android.

Fix options:
1. Set up HTTPS via a reverse proxy with Let's Encrypt (recommended for production)
2. Use `localhost` — only works if the backend is on the same device
3. On Android: you can enable `chrome://flags/#unsafely-treat-insecure-origin-as-secure` for testing only

## Barcode scanner falls back to ZXing on iOS

The native `BarcodeDetector` API is Android-only. On iOS, PocketLedger dynamically loads `@zxing/browser` on first scan. This is expected — it adds ~200 KB on first use but caches afterward.

## Companion app can't reach localhost:8765

If you're using the browser PWA alongside the companion app and prints aren't going through:

1. Make sure the companion app is open and running (not just installed)
2. On Android, the companion app must have started the background service — check the persistent notification in the status bar
3. Try `curl http://localhost:8765/status` from a terminal on the same device

## PocketBase admin UI (/\_/) not loading

The `/_/` admin panel is served directly by PocketBase. If it's not loading:
- Check that the backend process is running
- The admin panel requires a superadmin account — created on first launch via the initial setup page
- If you lost access, you can reset via the PocketBase CLI: `./pocketledger superuser upsert email@example.com newpassword`

## Auth token expired / auto-logout

PocketBase tokens expire after the configured duration (default: 7 days). After expiry, API calls return 401 and the frontend redirects to the login page. This is expected — log in again.

If users are being logged out too frequently, increase the auth token duration in the PocketBase admin UI → Collections → users → Edit collection → Auth options → Token duration.
