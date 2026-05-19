import 'dart:io';
import 'printer_connection.dart';

// TSPL commands for TVS LP 46 dlite (203 DPI, 1mm = 8 dots)
// Default label: 50mm x 30mm with 2mm gap
class TsplPrinter {
  static Future<void> printBarcode({
    required PrinterConnection connection,
    required String name,
    required String barcode,
    required String sku,
    required double price,
    bool showSku = true,
    bool showPrice = true,
    String shopName = '',
    Map<String, String> details = const {},
  }) async {
    final cmds = _build(
      name: name,
      barcode: barcode,
      sku: sku,
      price: price,
      showSku: showSku,
      showPrice: showPrice,
      shopName: shopName,
      details: details,
    );
    await _sendToConnection(connection, cmds);
  }

  static Future<void> testPrint({required PrinterConnection connection}) async {
    const cmds = 'SIZE 50 mm, 30 mm\r\n'
        'GAP 2 mm, 0 mm\r\n'
        'DIRECTION 0\r\n'
        'CLS\r\n'
        'TEXT 10,5,"3",0,1,1,"TEST PRINT"\r\n'
        'TEXT 10,30,"2",0,1,1,"PocketLedger"\r\n'
        'TEXT 10,55,"1",0,1,1,"Label Printer OK"\r\n'
        'PRINT 1,1\r\n';
    await _sendToConnection(connection, cmds);
  }

  static String _build({
    required String name,
    required String barcode,
    required String sku,
    required double price,
    bool showSku = true,
    bool showPrice = true,
    String shopName = '',
    Map<String, String> details = const {},
  }) {
    final b = StringBuffer();

    b.writeln('SIZE 50 mm, 30 mm');
    b.writeln('GAP 2 mm, 0 mm');
    b.writeln('DIRECTION 0');
    b.writeln('REFERENCE 0,0');
    b.writeln('CLS');

    if (shopName.isNotEmpty) {
      final sn = shopName.length > 48 ? shopName.substring(0, 48) : shopName;
      b.writeln('TEXT 10,2,"1",0,1,1,"$sn"');
    }

    final displayName = name.length > 44 ? '${name.substring(0, 43)}>' : name;
    final nameY = shopName.isNotEmpty ? 18 : 5;
    b.writeln('TEXT 10,$nameY,"2",0,1,1,"$displayName"');

    final bcY = nameY + 22;
    b.writeln('BARCODE 10,$bcY,"128",48,1,0,2,2,"$barcode"');

    final bottomY = bcY + 68;
    if (showSku && sku.isNotEmpty) {
      b.writeln('TEXT 10,$bottomY,"1",0,1,1,"SKU: $sku"');
    }
    if (showPrice) {
      final priceStr = 'Rs.${price.toStringAsFixed(2)}';
      b.writeln('TEXT 300,$bottomY,"1",0,1,1,"$priceStr"');
    }

    var detailY = bottomY + 16;
    for (final e in details.entries) {
      if (e.key.trim().isEmpty) continue;
      b.writeln('TEXT 10,$detailY,"1",0,1,1,"${e.key}: ${e.value}"');
      detailY += 14;
    }

    b.writeln('PRINT 1,1');
    return b.toString();
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  static Future<void> _sendToConnection(
      PrinterConnection connection, String tspl) async {
    switch (connection) {
      case TcpConnection(:final ip, :final port):
        await _sendTcp(ip, port, tspl);
      case UsbConnection(:final path):
        if (Platform.isLinux) {
          await _sendLinuxUsb(path, tspl);
        } else if (Platform.isWindows) {
          await _sendWindowsUsb(path, tspl);
        } else {
          throw UnsupportedError(
              'USB label printing not supported on ${Platform.operatingSystem}');
        }
    }
  }

  static Future<void> _sendTcp(String ip, int port, String tspl) async {
    final socket =
        await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
    socket.write(tspl);
    await socket.flush();
    await socket.close();
  }

  // Linux: CUPS queue name (no leading '/') → lp -d queue -o raw file
  //        device path (/dev/usb/lp*) → write bytes directly
  static Future<void> _sendLinuxUsb(String path, String tspl) async {
    if (!path.startsWith('/')) {
      await _sendCups(path, tspl);
      return;
    }
    try {
      final sink = File(path).openWrite(mode: FileMode.writeOnlyAppend);
      sink.write(tspl);
      await sink.flush();
      await sink.close();
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 13) {
        throw Exception(
          'Permission denied on $path\n'
          'Fix: sudo usermod -aG lp \$USER  (then log out and back in)\n'
          'Or register the printer in CUPS and it will be used automatically.',
        );
      }
      rethrow;
    }
  }

  static Future<void> _sendCups(String queueName, String tspl) async {
    final tempPath =
        '${Directory.systemTemp.path}/pl_${DateTime.now().millisecondsSinceEpoch}.tspl';
    await File(tempPath).writeAsString(tspl);
    try {
      final result = await Process.run(
          'lp', ['-d', queueName, '-o', 'raw', tempPath]);
      if (result.exitCode != 0) {
        throw Exception('lp failed (${result.exitCode}): ${result.stderr}');
      }
    } finally {
      try {
        await File(tempPath).delete();
      } catch (_) {}
    }
  }

  static Future<void> _sendWindowsUsb(String portName, String tspl) async {
    final tempPath =
        '${Directory.systemTemp.path}\\pl_${DateTime.now().millisecondsSinceEpoch}.tspl';
    await File(tempPath).writeAsString(tspl);
    try {
      await Process.run('cmd', ['/c', 'copy', '/b', tempPath, portName]);
    } finally {
      try {
        await File(tempPath).delete();
      } catch (_) {}
    }
  }
}
