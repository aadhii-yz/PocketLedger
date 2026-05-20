import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'printer_connection.dart';
import 'settings_service.dart';

enum DiscoveryStatus { searching, found, softAp, noPermission, needsSelection, failed }

class PrinterState {
  final DiscoveryStatus status;
  final PrinterConnection? connection;
  final List<String>? candidates; // ips for needsSelection, paths for noPermission

  const PrinterState(this.status, {this.connection, this.candidates});
  const PrinterState.searching() : this(DiscoveryStatus.searching);
  const PrinterState.found(PrinterConnection c)
      : this(DiscoveryStatus.found, connection: c);
  const PrinterState.needsSelection(List<String> c)
      : this(DiscoveryStatus.needsSelection, candidates: c);
  const PrinterState.noPermission(List<String> paths)
      : this(DiscoveryStatus.noPermission, candidates: paths);
  const PrinterState.failed() : this(DiscoveryStatus.failed);
  const PrinterState.softAp(PrinterConnection c)
      : this(DiscoveryStatus.softAp, connection: c);
}

typedef _CupsQueues = ({String? receipt, String? label});
typedef _UsbProbe = ({List<String> usable, List<String> noPermission});

class PrinterDiscovery extends ChangeNotifier {
  static final PrinterDiscovery instance = PrinterDiscovery._();
  PrinterDiscovery._();

  // Set by main.dart on Android to reload the background service's settings
  static VoidCallback? onSettingsUpdated;

  PrinterState receiptState = const PrinterState.searching();
  PrinterState barcodeState = const PrinterState.searching();
  DateTime? receiptNextRetry;
  DateTime? barcodeNextRetry;

  final List<String> logs = [];

  Timer? _receiptRetryTimer;
  Timer? _barcodeRetryTimer;
  bool _initialBusy = false;
  bool _receiptBusy = false;
  bool _barcodeBusy = false;

  void _log(String msg) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    logs.add('[$ts] $msg');
    if (logs.length > 200) logs.removeAt(0);
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  void startDiscovery() {
    _restoreFromSettings();
    _runInitialDetection();
  }

  void addLog(String msg) => _log(msg);

  void stopDiscovery() {
    _receiptRetryTimer?.cancel();
    _barcodeRetryTimer?.cancel();
    _receiptRetryTimer = null;
    _barcodeRetryTimer = null;
  }

  void scanReceiptNow() {
    if (_receiptBusy) return;
    _receiptRetryTimer?.cancel();
    _receiptRetryTimer = null;
    receiptNextRetry = null;
    _runReceiptFull();
  }

  void scanBarcodeNow() {
    if (_barcodeBusy) return;
    _barcodeRetryTimer?.cancel();
    _barcodeRetryTimer = null;
    barcodeNextRetry = null;
    _runBarcodeFull();
  }

  void assignReceiptIp(String ip) {
    _persistReceipt(TcpConnection(ip, 9100));
    _cancelReceiptRetry();
    receiptState = PrinterState.found(TcpConnection(ip, 9100));
    notifyListeners();
  }

  void assignBarcodeIp(String ip) {
    _persistBarcode(TcpConnection(ip, 9100));
    _cancelBarcodeRetry();
    barcodeState = PrinterState.found(TcpConnection(ip, 9100));
    notifyListeners();
  }

  void overrideReceiptConnection(PrinterConnection conn) {
    _persistReceipt(conn);
    _cancelReceiptRetry();
    receiptState = PrinterState.found(conn);
    notifyListeners();
  }

  void overrideBarcodeConnection(PrinterConnection conn) {
    _persistBarcode(conn);
    _cancelBarcodeRetry();
    barcodeState = PrinterState.found(conn);
    notifyListeners();
  }

  // ── Initial detection (shared probe, runs at startup) ─────────────────────

  void _restoreFromSettings() {
    final s = SettingsService.instance;
    if (s.receiptUsbPath.isNotEmpty) {
      receiptState = PrinterState.found(UsbConnection(s.receiptUsbPath));
    } else if (s.receiptPrinterIp.isNotEmpty) {
      receiptState = PrinterState.found(
          TcpConnection(s.receiptPrinterIp, s.receiptPrinterPort));
    }
    if (s.barcodeUsbPath.isNotEmpty) {
      barcodeState = PrinterState.found(UsbConnection(s.barcodeUsbPath));
    } else if (s.barcodePrinterIp.isNotEmpty) {
      barcodeState = PrinterState.found(
          TcpConnection(s.barcodePrinterIp, s.barcodePrinterPort));
    }
    notifyListeners();
  }

  Future<void> _runInitialDetection() async {
    if (_initialBusy) return;
    _initialBusy = true;

    _setReceiptState(const PrinterState.searching());
    _setBarcodeState(const PrinterState.searching());

    _log('Detection started (${Platform.operatingSystem})');

    try {
      // ── Step 1: CUPS queues (Linux) / named USB printers (Windows) ──────
      _CupsQueues cups = (receipt: null, label: null);
      if (Platform.isLinux) {
        cups = await _detectLinuxCupsQueues();
        _log('CUPS: receipt=${cups.receipt ?? 'none'} label=${cups.label ?? 'none'}');
      } else if (Platform.isWindows) {
        cups = await _detectWindowsPrinters();
        _log('Win named: receipt=${cups.receipt ?? 'none'} label=${cups.label ?? 'none'}');
      }

      // ── Step 2: Direct USB probe (Linux/Windows, fast ~50ms) ─────────────
      _UsbProbe usb = (usable: [], noPermission: []);
      if (!Platform.isAndroid && !Platform.isMacOS) {
        usb = await _probeAllUsb();
        _log('USB probe: usable=${usb.usable} noPerm=${usb.noPermission}');
      }

      // ── Step 3: Assign receipt ────────────────────────────────────────────
      if (cups.receipt != null) {
        _log('Receipt → named USB ${cups.receipt}');
        _setReceiptFound(UsbConnection(cups.receipt!));
      } else if (usb.usable.isNotEmpty) {
        _log('Receipt → generic USB ${usb.usable.first}');
        _setReceiptFound(UsbConnection(usb.usable.first));
      } else if (usb.noPermission.isNotEmpty) {
        _log('Receipt → USB found but no permission: ${usb.noPermission}');
        _setReceiptState(PrinterState.noPermission(usb.noPermission));
      } else {
        _log('Receipt → no USB found, will network scan');
      }

      // ── Step 4: Assign barcode (exclude receipt's claimed USB path) ───────
      final receiptUsb = switch (receiptState.connection) {
        UsbConnection(:final path) => path,
        _ => null,
      };
      final remainingUsable =
          usb.usable.where((p) => p != receiptUsb).toList();
      final remainingNoPerm =
          usb.noPermission.where((p) => p != receiptUsb).toList();

      if (cups.label != null) {
        _log('Barcode → named USB ${cups.label}');
        _setBarcodeFound(UsbConnection(cups.label!));
      } else if (remainingUsable.isNotEmpty) {
        _log('Barcode → generic USB ${remainingUsable.first}');
        _setBarcodeFound(UsbConnection(remainingUsable.first));
      } else if (remainingNoPerm.isNotEmpty) {
        _log('Barcode → USB found but no permission: $remainingNoPerm');
        _setBarcodeState(PrinterState.noPermission(remainingNoPerm));
      } else {
        _log('Barcode → no USB found, will network scan');
      }

      // ── Step 5: Network scan for anything still searching ─────────────────
      final networkFutures = <Future>[];
      if (receiptState.status == DiscoveryStatus.searching) {
        _log('Starting receipt network scan');
        networkFutures.add(_receiptNetworkScan());
      }
      if (barcodeState.status == DiscoveryStatus.searching) {
        _log('Starting barcode network scan');
        networkFutures.add(_barcodeNetworkScan());
      }
      await Future.wait(networkFutures);
    } finally {
      _initialBusy = false;
      _log('Detection done — receipt=${receiptState.status.name} barcode=${barcodeState.status.name}');
    }
  }

  // ── Full chain for "Scan Now" buttons ──────────────────────────────────────

  Future<void> _runReceiptFull() async {
    if (_receiptBusy) return;
    _receiptBusy = true;
    _setReceiptState(const PrinterState.searching());
    try {
      if (Platform.isLinux) {
        final cups = await _detectLinuxCupsQueues();
        if (cups.receipt != null) {
          _setReceiptFound(UsbConnection(cups.receipt!));
          return;
        }
      } else if (Platform.isWindows) {
        final named = await _detectWindowsPrinters();
        if (named.receipt != null) {
          _setReceiptFound(UsbConnection(named.receipt!));
          return;
        }
      }
      if (!Platform.isAndroid && !Platform.isMacOS) {
        final usb = await _probeAllUsb();
        // Exclude any path claimed by barcode
        final barcodeUsb = switch (barcodeState.connection) {
          UsbConnection(:final path) => path,
          _ => null,
        };
        final candidates =
            usb.usable.where((p) => p != barcodeUsb).toList();
        if (candidates.isNotEmpty) {
          _setReceiptFound(UsbConnection(candidates.first));
          return;
        }
        if (usb.noPermission.isNotEmpty) {
          _setReceiptState(PrinterState.noPermission(usb.noPermission));
          return;
        }
      }
      await _receiptNetworkScan();
    } finally {
      _receiptBusy = false;
    }
  }

  Future<void> _runBarcodeFull() async {
    if (_barcodeBusy) return;
    _barcodeBusy = true;
    _setBarcodeState(const PrinterState.searching());
    try {
      if (Platform.isLinux) {
        final cups = await _detectLinuxCupsQueues();
        if (cups.label != null) {
          _setBarcodeFound(UsbConnection(cups.label!));
          return;
        }
      } else if (Platform.isWindows) {
        final named = await _detectWindowsPrinters();
        if (named.label != null) {
          _setBarcodeFound(UsbConnection(named.label!));
          return;
        }
      }
      if (!Platform.isAndroid && !Platform.isMacOS) {
        final usb = await _probeAllUsb();
        // Exclude any path claimed by receipt
        final receiptUsb = switch (receiptState.connection) {
          UsbConnection(:final path) => path,
          _ => null,
        };
        final candidates =
            usb.usable.where((p) => p != receiptUsb).toList();
        final noPerm =
            usb.noPermission.where((p) => p != receiptUsb).toList();
        if (candidates.isNotEmpty) {
          _setBarcodeFound(UsbConnection(candidates.first));
          return;
        }
        if (noPerm.isNotEmpty) {
          _setBarcodeState(PrinterState.noPermission(noPerm));
          return;
        }
      }
      await _barcodeNetworkScan();
    } finally {
      _barcodeBusy = false;
    }
  }

  // ── Network-only scans ─────────────────────────────────────────────────────

  Future<void> _receiptNetworkScan() async {
    final ips = await _scanPort9100();
    _log('Receipt net scan: found IPs=$ips');
    final candidates =
        ips.where((ip) => !ip.startsWith('192.168.4.')).toList();
    if (candidates.length == 1) {
      _log('Receipt → TCP ${candidates.first}');
      _setReceiptFound(TcpConnection(candidates.first, 9100));
    } else if (candidates.isEmpty) {
      _log('Receipt net scan: no devices on port 9100');
      _setReceiptState(const PrinterState.failed());
      _scheduleReceiptRetry();
    } else {
      _log('Receipt net scan: multiple candidates, needs selection');
      _setReceiptState(PrinterState.needsSelection(candidates));
    }
  }

  Future<void> _barcodeNetworkScan() async {
    final ips = await _scanPort9100();
    _log('Barcode net scan: found IPs=$ips');
    if (ips.contains('192.168.4.1')) {
      _log('Barcode → SoftAP 192.168.4.1');
      _cancelBarcodeRetry();
      _persistBarcode(const TcpConnection('192.168.4.1', 9100));
      _setBarcodeState(PrinterState.softAp(const TcpConnection('192.168.4.1', 9100)));
      return;
    }
    final receiptIp = switch (receiptState.connection) {
      TcpConnection(:final ip) => ip,
      _ => null,
    };
    final candidates = ips.where((ip) => ip != receiptIp).toList();
    if (candidates.length == 1) {
      _log('Barcode → TCP ${candidates.first}');
      _setBarcodeFound(TcpConnection(candidates.first, 9100));
    } else if (candidates.isEmpty) {
      _log('Barcode net scan: no devices on port 9100');
      _setBarcodeState(const PrinterState.failed());
      _scheduleBarcodeRetry();
    } else {
      _log('Barcode net scan: multiple candidates, needs selection');
      _setBarcodeState(PrinterState.needsSelection(candidates));
    }
  }

  // ── State helpers ──────────────────────────────────────────────────────────

  void _setReceiptFound(PrinterConnection conn) {
    _cancelReceiptRetry();
    _persistReceipt(conn);
    _setReceiptState(PrinterState.found(conn));
  }

  void _setBarcodeFound(PrinterConnection conn) {
    _cancelBarcodeRetry();
    _persistBarcode(conn);
    _setBarcodeState(PrinterState.found(conn));
  }

  void _persistReceipt(PrinterConnection conn) {
    final s = SettingsService.instance;
    if (conn is UsbConnection) {
      s.receiptUsbPath = conn.path;
      s.receiptPrinterIp = '';
    } else if (conn is TcpConnection) {
      s.receiptUsbPath = '';
      s.receiptPrinterIp = conn.ip;
      s.receiptPrinterPort = conn.port;
    }
    s.save();
    onSettingsUpdated?.call();
  }

  void _persistBarcode(PrinterConnection conn) {
    final s = SettingsService.instance;
    if (conn is UsbConnection) {
      s.barcodeUsbPath = conn.path;
      s.barcodePrinterIp = '';
    } else if (conn is TcpConnection) {
      s.barcodeUsbPath = '';
      s.barcodePrinterIp = conn.ip;
      s.barcodePrinterPort = conn.port;
    }
    s.save();
    onSettingsUpdated?.call();
  }

  void _setReceiptState(PrinterState state) {
    receiptState = state;
    notifyListeners();
  }

  void _setBarcodeState(PrinterState state) {
    barcodeState = state;
    notifyListeners();
  }

  void _cancelReceiptRetry() {
    _receiptRetryTimer?.cancel();
    _receiptRetryTimer = null;
    receiptNextRetry = null;
  }

  void _cancelBarcodeRetry() {
    _barcodeRetryTimer?.cancel();
    _barcodeRetryTimer = null;
    barcodeNextRetry = null;
  }

  void _scheduleReceiptRetry() {
    receiptNextRetry = DateTime.now().add(const Duration(seconds: 30));
    notifyListeners();
    _receiptRetryTimer = Timer(const Duration(seconds: 30), _runReceiptFull);
  }

  void _scheduleBarcodeRetry() {
    barcodeNextRetry = DateTime.now().add(const Duration(seconds: 30));
    notifyListeners();
    _barcodeRetryTimer = Timer(const Duration(seconds: 30), _runBarcodeFull);
  }

  // ── CUPS detection (Linux) ─────────────────────────────────────────────────

  // Parses `lpstat -v` to find queues for the receipt (RP 3230) and label (LP 46).
  // Matches on both queue name and USB device URI, case-insensitive.
  Future<_CupsQueues> _detectLinuxCupsQueues() async {
    try {
      final result = await Process.run('lpstat', ['-v']);
      if (result.exitCode != 0) return (receipt: null, label: null);

      String? receipt;
      String? label;
      for (final line in (result.stdout as String).split('\n')) {
        final m = RegExp(r'device for (\S+):\s*(.+)').firstMatch(line);
        if (m == null) continue;
        final name = m.group(1)!;
        final uri = m.group(2)!.toLowerCase();
        final combined = '${name.toLowerCase()} $uri';

        if (receipt == null &&
            (combined.contains('rp3230') ||
                combined.contains('rp-3230') ||
                combined.contains('rp_3230') ||
                combined.contains('3230'))) {
          receipt = name;
        }
        if (label == null &&
            (combined.contains('lp46') ||
                combined.contains('lp-46') ||
                combined.contains('lp_46') ||
                combined.contains('dlite'))) {
          label = name;
        }
      }
      return (receipt: receipt, label: label);
    } catch (_) {
      return (receipt: null, label: null);
    }
  }

  // Queries Win32_Printer for USB-connected printers and matches by name to
  // identify the receipt (RP 3230) and label (LP 46 dlite) ports.
  // Uses Get-CimInstance with a Get-WmiObject fallback for PS 5 compatibility.
  // Lists physically connected USB printer devices via PnP (even uninstalled
  // ones) — used only for diagnostic logging, not for detection.
  Future<void> _logWindowsPnpPrinters() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"Get-PnpDevice -PresentOnly | Where-Object { $_.Class -eq 'Printer' } | ForEach-Object { $_.FriendlyName + '|' + $_.Status }",
      ]);
      final out = (result.stdout as String).trim();
      _log('Win PnP devices: ${out.isEmpty ? '<none visible to Get-PnpDevice>' : out}');
    } catch (_) {}
  }

  Future<_CupsQueues> _detectWindowsPrinters() async {
    _log('Win: running Get-CimInstance Win32_Printer');
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$p = try { Get-CimInstance Win32_Printer } catch { Get-WmiObject Win32_Printer };'
        r' $p | Where-Object { $_.PortName -match "^USB" } |'
        r' ForEach-Object { "$($_.Name)|$($_.PortName)" }',
      ]);
      _log('Win PS exit=${result.exitCode} stderr="${(result.stderr as String).trim()}"');
      final stdout = (result.stdout as String).trim();
      _log('Win PS stdout="${stdout.isEmpty ? '<empty>' : stdout}"');
      if (result.exitCode != 0) return (receipt: null, label: null);

      String? receipt;
      String? label;
      for (final raw in stdout.split('\n')) {
        final line = raw.trim();
        final sep = line.indexOf('|');
        if (sep < 0) continue;
        final originalName = line.substring(0, sep).trim();
        final name = originalName.toLowerCase();
        final port = line.substring(sep + 1).trim();
        if (port.isEmpty) continue;
        _log('Win printer: name="$name" port="$port"');

        if (receipt == null &&
            (name.contains('3230') ||
                name.contains('rp3230') ||
                name.contains('rp-3230') ||
                name.contains('rp 3230'))) {
          receipt = originalName;
          _log('Win: matched receipt → $originalName (port $port)');
        }
        if (label == null &&
            (name.contains('lp46') ||
                name.contains('lp-46') ||
                name.contains('lp 46') ||
                name.contains('dlite'))) {
          label = originalName;
          _log('Win: matched label → $originalName (port $port)');
        }
      }
      if (receipt == null && label == null) {
        _log('Win: no model name matched — printers may not be installed in Windows');
        await _logWindowsPnpPrinters();
      }
      return (receipt: receipt, label: label);
    } catch (e) {
      _log('Win: exception: $e');
      return (receipt: null, label: null);
    }
  }

  // ── Direct USB probe ───────────────────────────────────────────────────────

  Future<_UsbProbe> _probeAllUsb() async {
    if (Platform.isLinux) return _probeLinuxUsb();
    if (Platform.isWindows) return _probeWindowsUsb();
    return (usable: <String>[], noPermission: <String>[]);
  }

  Future<_UsbProbe> _probeLinuxUsb() async {
    final usable = <String>[];
    final noPerm = <String>[];
    for (var i = 0; i <= 3; i++) {
      final path = '/dev/usb/lp$i';
      if (!await File(path).exists()) continue;
      try {
        // Attempt open for writing to confirm we have permission.
        // Character devices ignore O_TRUNC so FileMode.writeOnly is safe.
        final f = await File(path).open(mode: FileMode.writeOnly);
        await f.close();
        usable.add(path);
      } on FileSystemException catch (e) {
        if (e.osError?.errorCode == 13) noPerm.add(path);
        // EBUSY or other errors — skip this node
      }
    }
    return (usable: usable, noPermission: noPerm);
  }

  Future<_UsbProbe> _probeWindowsUsb() async {
    _log('Win USB probe: running Get-WmiObject Win32_Printer PortName');
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"Get-WmiObject -Class Win32_Printer | Where-Object { $_.PortName -match '^USB\d+' } | Select-Object -ExpandProperty PortName",
      ]);
      _log('Win USB probe: exit=${result.exitCode} stderr="${(result.stderr as String).trim()}"');
      final stdout = (result.stdout as String).trim();
      _log('Win USB probe: stdout="${stdout.isEmpty ? '<empty>' : stdout}"');
      if (result.exitCode == 0) {
        final ports = stdout
            .split('\n')
            .map((s) => s.trim())
            .where((s) => RegExp(r'^USB\d+$').hasMatch(s))
            .toList();
        _log('Win USB probe: matched ports=$ports');
        return (usable: ports, noPermission: <String>[]);
      }
    } catch (e) {
      _log('Win USB probe: exception: $e');
    }
    return (usable: <String>[], noPermission: <String>[]);
  }

  // ── Network scan ───────────────────────────────────────────────────────────

  Future<List<String>> _scanPort9100() async {
    final bases = await _getLocalSubnetBases();
    if (bases.isEmpty) return [];

    final futures = <Future<String?>>[];
    for (final base in bases) {
      if (base == '192.168.4.') {
        // SoftAP subnet — only the printer at .1 matters
        futures.add(_tryConnect('192.168.4.1', 9100));
        continue;
      }
      for (var i = 1; i <= 254; i++) {
        futures.add(_tryConnect('$base$i', 9100));
      }
    }

    final results = await Future.wait(futures);
    return results.whereType<String>().toSet().toList();
  }

  Future<List<String>> _getLocalSubnetBases() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final bases = <String>{};
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        if (_isPrivateIp(addr.address)) {
          final parts = addr.address.split('.');
          bases.add('${parts[0]}.${parts[1]}.${parts[2]}.');
        }
      }
    }
    return bases.toList();
  }

  bool _isPrivateIp(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final a = int.tryParse(parts[0]) ?? 0;
    final b = int.tryParse(parts[1]) ?? 0;
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  Future<String?> _tryConnect(String ip, int port) async {
    try {
      final socket = await Socket.connect(ip, port,
          timeout: const Duration(milliseconds: 400));
      await socket.close();
      return ip;
    } catch (_) {
      return null;
    }
  }
}
