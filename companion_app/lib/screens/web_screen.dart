import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../services/settings_service.dart';
import '../services/tspl_printer.dart';
import '../services/escpos_printer.dart';

class WebScreen extends StatefulWidget {
  const WebScreen({super.key});

  @override
  State<WebScreen> createState() => _WebScreenState();
}

class _WebScreenState extends State<WebScreen> {
  bool _loading = false;
  String? _errorMessage;

  Future<void> _onPrint(List<dynamic> args) async {
    if (args.isEmpty) return;
    try {
      final data = Map<String, dynamic>.from(args[0] as Map);
      final s = SettingsService.instance;
      if (data['type'] == 'barcode') {
        final conn = s.barcodeConnection;
        if (conn == null) return;
        await TsplPrinter.printBarcode(
          connection: conn,
          name: data['name'] as String? ?? '',
          barcode: data['barcode'] as String? ?? '',
          sku: data['sku'] as String? ?? '',
          price: (data['selling_price'] as num? ?? 0).toDouble(),
          showSku: data['show_sku'] as bool? ?? true,
          showPrice: data['show_price'] as bool? ?? true,
          shopName: data['shop_name'] as String? ?? '',
          details: Map<String, String>.from(data['details'] as Map? ?? {}),
        );
      } else if (data['type'] == 'receipt') {
        final conn = s.receiptConnection;
        if (conn == null) return;
        await EscPosPrinter.printReceipt(
          connection: conn,
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
      InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
        onWebViewCreated: (controller) => controller.addJavaScriptHandler(
          handlerName: 'FlutterPrint',
          callback: _onPrint,
        ),
        onLoadStart: (controller, url) => setState(() {
          _loading = true;
          _errorMessage = null;
        }),
        onLoadStop: (controller, url) => setState(() => _loading = false),
        onReceivedError: (controller, request, error) => setState(() {
          _loading = false;
          _errorMessage =
              '${error.type.name}: ${error.description}\n${request.url}';
        }),
      ),
      if (_loading) const LinearProgressIndicator(),
      if (_errorMessage != null)
        Positioned.fill(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Failed to load',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
    ]);
  }
}
