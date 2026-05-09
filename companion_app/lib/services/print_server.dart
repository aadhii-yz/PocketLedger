import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'settings_service.dart';
import 'tspl_printer.dart';
import 'escpos_printer.dart';

class PrintServer {
  static HttpServer? _server;

  static bool get isRunning => _server != null;

  static Future<void> start(int port) async {
    if (_server != null) return;

    final router = Router()
      ..get('/status', _status)
      ..post('/print/barcode', _printBarcode)
      ..post('/print/receipt', _printReceipt);

    final handler = Pipeline().addMiddleware(_cors()).addHandler(router.call);

    _server = await shelf_io.serve(handler, '127.0.0.1', port);
  }

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ── Middleware ──────────────────────────────────────────────────────────────

  static Middleware _cors() => (Handler inner) => (Request req) async {
        if (req.method == 'OPTIONS') {
          return Response.ok('', headers: _ch);
        }
        final res = await inner(req);
        return res.change(headers: _ch);
      };

  static const _ch = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Content-Type': 'application/json',
  };

  // ── Handlers ────────────────────────────────────────────────────────────────

  static Response _status(Request _) =>
      Response.ok(jsonEncode({'ok': true, 'version': '1.0.0'}));

  static Future<Response> _printBarcode(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final s = SettingsService.instance;

      if (s.barcodePrinterIp.isEmpty) {
        return Response(422,
            body: jsonEncode({'error': 'Barcode printer IP not configured in companion app'}));
      }

      await TsplPrinter.printBarcode(
        ip: s.barcodePrinterIp,
        port: s.barcodePrinterPort,
        name: body['name'] as String? ?? '',
        barcode: body['barcode'] as String? ?? '',
        sku: body['sku'] as String? ?? '',
        price: (body['selling_price'] as num? ?? 0).toDouble(),
        showSku: body['show_sku'] as bool? ?? true,
        showPrice: body['show_price'] as bool? ?? true,
        shopName: body['shop_name'] as String? ?? '',
        details: (body['details'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, v.toString())),
      );

      return Response.ok(jsonEncode({'ok': true}));
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}));
    }
  }

  static Future<Response> _printReceipt(Request req) async {
    try {
      final body = jsonDecode(await req.readAsString()) as Map<String, dynamic>;
      final s = SettingsService.instance;

      if (s.receiptPrinterIp.isEmpty) {
        return Response(422,
            body: jsonEncode({'error': 'Receipt printer IP not configured in companion app'}));
      }

      await EscPosPrinter.printReceipt(
        ip: s.receiptPrinterIp,
        port: s.receiptPrinterPort,
        data: body,
      );

      return Response.ok(jsonEncode({'ok': true}));
    } catch (e) {
      return Response(500, body: jsonEncode({'error': e.toString()}));
    }
  }
}
