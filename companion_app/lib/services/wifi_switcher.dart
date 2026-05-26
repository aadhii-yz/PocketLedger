import 'dart:async';
import 'dart:io';
import 'package:wifi_iot/wifi_iot.dart' show WiFiForIoTPlugin, NetworkSecurity;

/// Result of a WiFi switch operation.
class WifiSwitchResult {
  final bool success;
  final String? error;
  const WifiSwitchResult.ok() : success = true, error = null;
  const WifiSwitchResult.err(this.error) : success = false;
}

/// Programmatic WiFi switching for all three desktop/mobile platforms.
///
/// Android  — wifi_iot (API 29+: bound network, system WiFi unchanged;
///             API 28–: actually changes system WiFi connection)
/// Linux    — nmcli (NetworkManager CLI)
/// Windows  — netsh wlan (creates a temporary WLAN profile when needed)
class WifiSwitcher {
  static bool get isSupported =>
      Platform.isAndroid || Platform.isLinux || Platform.isWindows;

  /// Current WiFi SSID, or null if not connected / undetectable.
  static Future<String?> currentSsid() async {
    try {
      if (Platform.isLinux) return await _linuxSsid();
      if (Platform.isWindows) return await _windowsSsid();
      if (Platform.isAndroid) return await _androidSsid();
    } catch (_) {}
    return null;
  }

  /// Connect to [ssid] with optional [password].
  /// On Android 10+, this binds the app's traffic only (no system-wide switch).
  static Future<WifiSwitchResult> connect(String ssid, {String? password}) async {
    try {
      if (Platform.isLinux) return await _linuxConnect(ssid, password: password);
      if (Platform.isWindows) return await _windowsConnect(ssid, password: password);
      if (Platform.isAndroid) return await _androidConnect(ssid, password: password);
    } catch (e) {
      return WifiSwitchResult.err(e.toString());
    }
    return const WifiSwitchResult.err('Unsupported platform');
  }

  /// Restore [previousSsid]. Safe to call fire-and-forget (callers may `.ignore()`).
  /// On Android, releases the bound network — system reconnects automatically.
  static Future<void> reconnect(String? previousSsid) async {
    try {
      if (Platform.isAndroid) {
        await WiFiForIoTPlugin.disconnect();
      } else if (Platform.isLinux && previousSsid != null) {
        await _linuxReconnect(previousSsid);
      } else if (Platform.isWindows && previousSsid != null) {
        await _windowsReconnect(previousSsid);
      }
    } catch (_) {}
  }

  /// Polls [host]:[port] via TCP until a connection is accepted or [timeout] elapses.
  static Future<bool> waitForHost(
    String host, {
    int port = 80,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      try {
        final s = await Socket.connect(
          host, port, timeout: const Duration(seconds: 2),
        );
        await s.close();
        return true;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
    return false;
  }

  // ── Linux (nmcli) ──────────────────────────────────────────────────────────

  static Future<String?> _linuxSsid() async {
    final r = await Process.run(
      'nmcli', ['-t', '-f', 'active,ssid', 'dev', 'wifi'],
    );
    if (r.exitCode != 0) return null;
    for (final line in (r.stdout as String).split('\n')) {
      if (line.startsWith('yes:')) return line.substring(4).trim();
    }
    return null;
  }

  static Future<WifiSwitchResult> _linuxConnect(
    String ssid, {
    String? password,
  }) async {
    final args = ['dev', 'wifi', 'connect', ssid];
    if (password != null && password.isNotEmpty) {
      args.addAll(['password', password]);
    }
    final r = await Process.run('nmcli', args)
        .timeout(const Duration(seconds: 30));
    if (r.exitCode == 0) return const WifiSwitchResult.ok();
    final err = (r.stderr as String).trim();
    return WifiSwitchResult.err(
        err.isEmpty ? 'nmcli exit ${r.exitCode}' : err);
  }

  static Future<void> _linuxReconnect(String ssid) async {
    // Try restoring via the saved connection profile name first.
    final r = await Process.run('nmcli', ['connection', 'up', 'id', ssid])
        .timeout(const Duration(seconds: 30));
    if (r.exitCode != 0) {
      // Fall back to a fresh wifi connect (re-scans and connects by SSID).
      await Process.run('nmcli', ['dev', 'wifi', 'connect', ssid])
          .timeout(const Duration(seconds: 30));
    }
  }

  // ── Windows (netsh wlan) ───────────────────────────────────────────────────

  static Future<String?> _windowsSsid() async {
    final r = await Process.run('netsh', ['wlan', 'show', 'interfaces']);
    if (r.exitCode != 0) return null;
    for (final line in (r.stdout as String).split('\n')) {
      // Skip the BSSID line which also matches "SSID :"
      if (RegExp(r'BSSID', caseSensitive: false).hasMatch(line)) continue;
      final m = RegExp(r'SSID\s*:\s*(.+)').firstMatch(line);
      if (m != null) return m.group(1)!.trim();
    }
    return null;
  }

  static Future<WifiSwitchResult> _windowsConnect(
    String ssid, {
    String? password,
  }) async {
    if (password != null && password.isNotEmpty) {
      final tmp = File('${Directory.systemTemp.path}\\pl_wlan.xml');
      await tmp.writeAsString(_wlanProfileXml(ssid, password));
      // Add the profile to the user store (no admin required).
      await Process.run(
          'netsh', ['wlan', 'add', 'profile', 'filename=${tmp.path}']);
      try {
        await tmp.delete();
      } catch (_) {}
    }
    final r = await Process.run(
      'netsh', ['wlan', 'connect', 'ssid=$ssid', 'name=$ssid'],
    ).timeout(const Duration(seconds: 30));
    if (r.exitCode == 0) return const WifiSwitchResult.ok();
    final err = (r.stderr as String).trim();
    return WifiSwitchResult.err(
        err.isEmpty ? 'netsh exit ${r.exitCode}' : err);
  }

  static Future<void> _windowsReconnect(String ssid) async {
    await Process.run('netsh', ['wlan', 'connect', 'ssid=$ssid', 'name=$ssid'])
        .timeout(const Duration(seconds: 30));
    // Remove the temporary printer AP profile now that we no longer need it.
    await Process.run(
            'netsh', ['wlan', 'delete', 'profile', 'name=DEFAULT_AP_CB8F29'])
        .timeout(const Duration(seconds: 5));
  }

  // WPA2-Personal profile XML for netsh wlan add profile.
  static String _wlanProfileXml(String ssid, String password) => '''<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
  <name>$ssid</name>
  <SSIDConfig><SSID><name>$ssid</name></SSID></SSIDConfig>
  <connectionType>ESS</connectionType>
  <connectionMode>manual</connectionMode>
  <MSM>
    <security>
      <authEncryption>
        <authentication>WPA2PSK</authentication>
        <encryption>AES</encryption>
      </authEncryption>
      <sharedKey>
        <keyType>passPhrase</keyType>
        <protected>false</protected>
        <keyMaterial>$password</keyMaterial>
      </sharedKey>
    </security>
  </MSM>
</WLANProfile>''';

  // ── Android (wifi_iot) ─────────────────────────────────────────────────────

  static Future<String?> _androidSsid() async {
    try {
      final ssid = await WiFiForIoTPlugin.getSSID();
      if (ssid == null || ssid.isEmpty || ssid == '<unknown ssid>') return null;
      // wifi_iot wraps some SSIDs in quotes on certain devices.
      return ssid.replaceAll('"', '');
    } catch (_) {
      return null;
    }
  }

  static Future<WifiSwitchResult> _androidConnect(
    String ssid, {
    String? password,
  }) async {
    // withInternet: false — on API 29+ uses WifiNetworkSpecifier which binds
    // only this app's traffic to the printer AP without changing system WiFi.
    // joinOnce: true — releases the bound network when we call disconnect().
    final ok = await WiFiForIoTPlugin.connect(
      ssid,
      password: password ?? '',
      security: (password != null && password.isNotEmpty)
          ? NetworkSecurity.WPA
          : NetworkSecurity.NONE,
      withInternet: false,
      joinOnce: true,
    );
    if (ok) return const WifiSwitchResult.ok();
    return const WifiSwitchResult.err('Could not connect to printer hotspot');
  }
}
