import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/settings_service.dart';
import '../services/tspl_printer.dart';
import '../services/escpos_printer.dart';

class WebScreen extends StatefulWidget {
  const WebScreen({super.key});

  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> {
  late final WebViewController _ctrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('FlutterPrint', onMessageReceived: _onPrint)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
        onWebResourceError: (_) => setState(() => _loading = false),
      ));
    _load();
  }

  void _load() {
    final url = SettingsService.instance.pocketledgerUrl;
    if (url.isNotEmpty) _ctrl.loadRequest(Uri.parse(url));
  }

  void _onPrint(JavaScriptMessage msg) async {
    try {
      final data = jsonDecode(msg.message) as Map<String, dynamic>;
      final s = SettingsService.instance;
      if (data['type'] == 'barcode' && s.barcodePrinterIp.isNotEmpty) {
        await TsplPrinter.printBarcode(
          ip: s.barcodePrinterIp,
          port: s.barcodePrinterPort,
          name: data['name'] as String? ?? '',
          barcode: data['barcode'] as String? ?? '',
          sku: data['sku'] as String? ?? '',
          price: (data['selling_price'] as num? ?? 0).toDouble(),
          showSku: data['show_sku'] as bool? ?? true,
          showPrice: data['show_price'] as bool? ?? true,
          shopName: data['shop_name'] as String? ?? '',
          details: Map<String, String>.from(data['details'] as Map? ?? {}),
        );
      } else if (data['type'] == 'receipt' && s.receiptPrinterIp.isNotEmpty) {
        await EscPosPrinter.printReceipt(
          ip: s.receiptPrinterIp,
          port: s.receiptPrinterPort,
          data: data,
        );
      }
    } catch (e) {
      debugPrint('[FlutterPrint] $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = SettingsService.instance.pocketledgerUrl;
    if (url.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.web_asset_off, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Enter your PocketLedger URL in Settings to get started.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
    return Stack(children: [
      WebViewWidget(controller: _ctrl),
      if (_loading) const LinearProgressIndicator(),
    ]);
  }
}
