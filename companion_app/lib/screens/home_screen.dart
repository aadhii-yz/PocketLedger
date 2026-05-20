import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../services/settings_service.dart';
import '../services/print_server.dart';
import '../services/printer_connection.dart';
import '../services/printer_discovery.dart';
import '../services/escpos_printer.dart';
import '../services/tspl_printer.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback? onSaved;
  const HomeScreen({super.key, this.onSaved});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlCtrl = TextEditingController();
  final _receiptManualIpCtrl = TextEditingController();
  final _barcodeManualIpCtrl = TextEditingController();

  bool _serverRunning = false;
  String _statusMsg = 'Starting…';
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    final s = SettingsService.instance;
    _urlCtrl.text = s.pocketledgerUrl;
    _receiptManualIpCtrl.text = s.receiptPrinterIp;
    _barcodeManualIpCtrl.text = s.barcodePrinterIp;

    PrinterDiscovery.instance.addListener(_onDiscoveryUpdate);
    PrinterDiscovery.instance.startDiscovery();

    _countdownTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => _tick());

    if (Platform.isAndroid) {
      setState(() {
        _serverRunning = true;
        _statusMsg =
            'Print service active on localhost:${s.serverPort}';
      });
    } else {
      _startDesktopServer();
    }
  }

  @override
  void dispose() {
    PrinterDiscovery.instance.removeListener(_onDiscoveryUpdate);
    _countdownTimer?.cancel();
    _urlCtrl.dispose();
    _receiptManualIpCtrl.dispose();
    _barcodeManualIpCtrl.dispose();
    super.dispose();
  }

  void _onDiscoveryUpdate() {
    if (mounted) setState(() {});
  }

  void _tick() {
    if (!mounted) return;
    final d = PrinterDiscovery.instance;
    final hasCountdown = d.receiptNextRetry != null || d.barcodeNextRetry != null;
    if (hasCountdown) setState(() {});
  }

  Future<void> _startDesktopServer() async {
    try {
      await PrintServer.start(SettingsService.instance.serverPort);
      setState(() {
        _serverRunning = true;
        _statusMsg =
            'Print server running on localhost:${SettingsService.instance.serverPort}';
      });
    } catch (e) {
      setState(() {
        _serverRunning = false;
        _statusMsg = 'Failed to start server: $e';
      });
    }
  }

  Future<void> _saveUrl() async {
    final s = SettingsService.instance;
    s.pocketledgerUrl = _urlCtrl.text.trim();
    await s.save();

    if (Platform.isAndroid) {
      FlutterBackgroundService().invoke('reload_settings');
    }

    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settings saved')));
      widget.onSaved?.call();
    }
  }

  // ── Manual IP overrides ────────────────────────────────────────────────────

  Future<void> _setReceiptManual() async {
    final ip = _receiptManualIpCtrl.text.trim();
    if (ip.isEmpty) return;
    final s = SettingsService.instance;
    s.receiptUsbPath = '';
    s.receiptPrinterIp = ip;
    s.receiptPrinterPort = 9100;
    await s.save();
    if (Platform.isAndroid) {
      FlutterBackgroundService().invoke('reload_settings');
    }
    PrinterDiscovery.instance
        .overrideReceiptConnection(TcpConnection(ip, 9100));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Receipt printer set to $ip')));
    }
  }

  Future<void> _setBarcodeManual() async {
    final ip = _barcodeManualIpCtrl.text.trim();
    if (ip.isEmpty) return;
    final s = SettingsService.instance;
    s.barcodePrinterIp = ip;
    s.barcodePrinterPort = 9100;
    await s.save();
    if (Platform.isAndroid) {
      FlutterBackgroundService().invoke('reload_settings');
    }
    PrinterDiscovery.instance
        .overrideBarcodeConnection(TcpConnection(ip, 9100));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Label printer set to $ip')));
    }
  }

  // ── Test prints ────────────────────────────────────────────────────────────

  Future<void> _testReceipt() async {
    final conn = SettingsService.instance.receiptConnection;
    if (conn == null) return;
    try {
      await EscPosPrinter.testPrint(connection: conn);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Test receipt sent')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Test failed: $e')));
      }
    }
  }

  Future<void> _testBarcode() async {
    final conn = SettingsService.instance.barcodeConnection;
    if (conn == null) return;
    try {
      await TsplPrinter.testPrint(connection: conn);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Test label sent')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Test failed: $e')));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final d = PrinterDiscovery.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Server status
            Card(
              color: _serverRunning
                  ? Colors.green.shade50
                  : Colors.red.shade50,
              child: ListTile(
                leading: Icon(
                  _serverRunning ? Icons.check_circle : Icons.error,
                  color: _serverRunning ? Colors.green : Colors.red,
                ),
                title: Text(
                  _serverRunning ? 'Server Running' : 'Server Stopped',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(_statusMsg),
              ),
            ),
            const SizedBox(height: 16),

            // PocketLedger URL
            const Text('PocketLedger',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'App URL',
                hintText: 'https://your-app.pockethost.io',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saveUrl,
                icon: const Icon(Icons.save),
                label: const Text('Save & Open App'),
              ),
            ),
            const SizedBox(height: 24),

            // Receipt printer
            _PrinterCard(
              title: 'Receipt Printer (TVS RP 3230)',
              state: d.receiptState,
              nextRetry: d.receiptNextRetry,
              onScanNow: () => PrinterDiscovery.instance.scanReceiptNow(),
              onAssign: (ip) =>
                  PrinterDiscovery.instance.assignReceiptIp(ip),
              onTestPrint: d.receiptState.status == DiscoveryStatus.found
                  ? _testReceipt
                  : null,
              manualIpCtrl: _receiptManualIpCtrl,
              onSaveManual: _setReceiptManual,
              usbNote: Platform.isLinux || Platform.isWindows,
            ),
            const SizedBox(height: 16),

            // Label printer
            _PrinterCard(
              title: 'Label Printer (TVS LP 46)',
              state: d.barcodeState,
              nextRetry: d.barcodeNextRetry,
              onScanNow: () => PrinterDiscovery.instance.scanBarcodeNow(),
              onAssign: (ip) =>
                  PrinterDiscovery.instance.assignBarcodeIp(ip),
              onTestPrint: d.barcodeState.status == DiscoveryStatus.found
                  ? _testBarcode
                  : null,
              manualIpCtrl: _barcodeManualIpCtrl,
              onSaveManual: _setBarcodeManual,
            ),

            const SizedBox(height: 24),

            // Debug logs
            _DebugLogPanel(logs: d.logs, onClear: d.clearLogs),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Debug log panel ────────────────────────────────────────────────────────

class _DebugLogPanel extends StatelessWidget {
  final List<String> logs;
  final VoidCallback onClear;

  const _DebugLogPanel({required this.logs, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Row(
        children: [
          const Icon(Icons.bug_report_outlined, size: 16, color: Colors.grey),
          const SizedBox(width: 6),
          const Text('Debug Logs',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
          const Spacer(),
          if (logs.isNotEmpty)
            Text('${logs.length} entries',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
      children: [
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 300),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(6),
          ),
          child: logs.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('No logs yet.',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                )
              : ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: logs.length,
                  itemBuilder: (_, i) {
                    final line = logs[logs.length - 1 - i];
                    return Text(
                      line,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: line.contains('exception') ||
                                line.contains('error') ||
                                line.contains('stderr')
                            ? Colors.red.shade300
                            : line.contains('matched') ||
                                    line.contains('→')
                                ? Colors.green.shade300
                                : Colors.grey.shade300,
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: logs.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(
                          ClipboardData(text: logs.join('\n')));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Logs copied')),
                      );
                    },
              icon: const Icon(Icons.copy, size: 14),
              label: const Text('Copy all'),
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: logs.isEmpty ? null : onClear,
              icon: const Icon(Icons.delete_outline, size: 14),
              label: const Text('Clear'),
              style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Printer card widget ────────────────────────────────────────────────────

class _PrinterCard extends StatelessWidget {
  final String title;
  final PrinterState state;
  final DateTime? nextRetry;
  final VoidCallback onScanNow;
  final void Function(String ip) onAssign;
  final VoidCallback? onTestPrint;
  final TextEditingController manualIpCtrl;
  final VoidCallback onSaveManual;
  final bool usbNote;

  const _PrinterCard({
    required this.title,
    required this.state,
    required this.nextRetry,
    required this.onScanNow,
    required this.onAssign,
    required this.onTestPrint,
    required this.manualIpCtrl,
    required this.onSaveManual,
    this.usbNote = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),
            _statusRow(),
            if (state.status == DiscoveryStatus.failed && Platform.isWindows) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: const Text(
                  'Printer not found in Windows.\n'
                  'One-time setup: Settings → Bluetooth & devices → Printers & scanners → Add device.\n'
                  'If not listed, add manually with driver "Generic / Text Only" and name it '
                  '"TVS RP 3230" (receipt) or "TVS LP 46" (label).',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
            if (state.status == DiscoveryStatus.noPermission) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device: ${state.candidates?.join(', ') ?? ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Fix option A — add to lp group (one-time):',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    SelectableText(
                      '  sudo usermod -aG lp \$USER\n  newgrp lp',
                      style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.grey.shade700),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Fix option B — register in CUPS (auto-detected next launch):',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    SelectableText(
                      '  sudo lpadmin -p QUEUE_NAME -E \\\n'
                      '    -v usb://TVS-E/MODEL -m raw',
                      style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ],
            if (state.status == DiscoveryStatus.needsSelection) ...[
              const SizedBox(height: 8),
              ...state.candidates!.map(
                (ip) => Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.circle_outlined,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(ip,
                              style: const TextStyle(fontSize: 13))),
                      TextButton(
                        onPressed: () => onAssign(ip),
                        child: const Text('Use this'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: state.status == DiscoveryStatus.searching
                      ? null
                      : onScanNow,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Scan Now'),
                ),
                if (onTestPrint != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onTestPrint,
                    icon: const Icon(Icons.print, size: 16),
                    label: const Text('Test'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Manual override',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              children: [
                if (usbNote)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'USB is auto-detected on Linux/Windows. '
                      'Enter an IP only to force a network connection.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                TextField(
                  controller: manualIpCtrl,
                  decoration: const InputDecoration(
                    labelText: 'IP Address',
                    hintText: '192.168.1.100',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onSaveManual,
                    child: const Text('Set'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow() {
    final Color color;
    final IconData icon;
    final String label;

    switch (state.status) {
      case DiscoveryStatus.found:
        color = Colors.green;
        icon = Icons.check_circle;
        label = state.connection.toString();
      case DiscoveryStatus.searching:
        color = Colors.amber.shade700;
        icon = Icons.search;
        label = 'Searching…';
      case DiscoveryStatus.needsSelection:
        color = Colors.orange;
        icon = Icons.help_outline;
        label = 'Multiple printers found — select one:';
      case DiscoveryStatus.noPermission:
        color = Colors.orange;
        icon = Icons.lock_outline;
        label = 'USB device found — no write permission';
      case DiscoveryStatus.failed:
        final secs = nextRetry != null
            ? nextRetry!.difference(DateTime.now()).inSeconds
            : 0;
        color = Colors.red;
        icon = Icons.error_outline;
        label = secs > 0
            ? 'Not found — retrying in ${secs}s'
            : 'Not found';
    }

    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              style: TextStyle(color: color, fontSize: 13)),
        ),
      ],
    );
  }
}
