import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../services/settings_service.dart';
import '../services/print_server.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _barcodeIpCtrl = TextEditingController();
  final _barcodePortCtrl = TextEditingController();
  final _receiptIpCtrl = TextEditingController();
  final _receiptPortCtrl = TextEditingController();

  bool _serverRunning = false;
  String _statusMsg = 'Starting…';

  @override
  void initState() {
    super.initState();
    final s = SettingsService.instance;
    _barcodeIpCtrl.text = s.barcodePrinterIp;
    _barcodePortCtrl.text = s.barcodePrinterPort.toString();
    _receiptIpCtrl.text = s.receiptPrinterIp;
    _receiptPortCtrl.text = s.receiptPrinterPort.toString();

    if (Platform.isAndroid) {
      // Server runs in background service isolate — just show status
      setState(() {
        _serverRunning = true;
        _statusMsg = 'Print service active on localhost:${s.serverPort}';
      });
    } else {
      _startDesktopServer();
    }
  }

  @override
  void dispose() {
    _barcodeIpCtrl.dispose();
    _barcodePortCtrl.dispose();
    _receiptIpCtrl.dispose();
    _receiptPortCtrl.dispose();
    super.dispose();
  }

  Future<void> _startDesktopServer() async {
    try {
      await PrintServer.start(SettingsService.instance.serverPort);
      setState(() {
        _serverRunning = true;
        _statusMsg = 'Print server running on localhost:${SettingsService.instance.serverPort}';
      });
    } catch (e) {
      setState(() {
        _serverRunning = false;
        _statusMsg = 'Failed to start server: $e';
      });
    }
  }

  Future<void> _save() async {
    final s = SettingsService.instance;
    s.barcodePrinterIp = _barcodeIpCtrl.text.trim();
    s.barcodePrinterPort = int.tryParse(_barcodePortCtrl.text.trim()) ?? 9100;
    s.receiptPrinterIp = _receiptIpCtrl.text.trim();
    s.receiptPrinterPort = int.tryParse(_receiptPortCtrl.text.trim()) ?? 9100;
    await s.save();

    if (Platform.isAndroid) {
      // Notify background service isolate to re-read SharedPreferences
      FlutterBackgroundService().invoke('reload_settings');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PocketLedger Print'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status
            Card(
              color: _serverRunning ? Colors.green.shade50 : Colors.red.shade50,
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
            const SizedBox(height: 8),
            Card(
              color: Colors.blue.shade50,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Keep this app open (or minimised) while using the PocketLedger web app. '
                  'The web app will print silently through this service.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Barcode printer
            const Text(
              'Barcode Printer (TVS LP 46)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _barcodeIpCtrl,
              decoration: const InputDecoration(
                labelText: 'IP Address',
                hintText: '192.168.1.100',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _barcodePortCtrl,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '9100',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),

            // Receipt printer
            const Text(
              'Receipt Printer (TVS RP 3230)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _receiptIpCtrl,
              decoration: const InputDecoration(
                labelText: 'IP Address',
                hintText: '192.168.1.101',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _receiptPortCtrl,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '9100',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save),
                label: const Text('Save Settings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
