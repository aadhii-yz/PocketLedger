import 'dart:io';

// TSPL commands for TVS LP 46 dlite (203 DPI, 1mm = 8 dots)
// Default label: 50mm x 30mm with 2mm gap
class TsplPrinter {
  static Future<void> printBarcode({
    required String ip,
    required int port,
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
    await _send(ip, port, cmds);
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

    // Shop name (optional, small)
    if (shopName.isNotEmpty) {
      final sn = shopName.length > 48 ? shopName.substring(0, 48) : shopName;
      b.writeln('TEXT 10,2,"1",0,1,1,"$sn"');
    }

    // Product name — font "2" is 8x16 dots; 50mm/8dpmm = 400 dots wide, fits ~44 chars
    final displayName = name.length > 44 ? '${name.substring(0, 43)}>' : name;
    final nameY = shopName.isNotEmpty ? 18 : 5;
    b.writeln('TEXT 10,$nameY,"2",0,1,1,"$displayName"');

    // Code128 barcode: x, y, type, height(dots), human-readable, rotation, narrow, wide, data
    final bcY = nameY + 22;
    b.writeln('BARCODE 10,$bcY,"128",48,1,0,2,2,"$barcode"');

    // SKU and price on the same line below the barcode
    // human-readable takes ~15 dots, barcode end ≈ bcY+48+15
    final bottomY = bcY + 68;
    if (showSku && sku.isNotEmpty) {
      b.writeln('TEXT 10,$bottomY,"1",0,1,1,"SKU: $sku"');
    }
    if (showPrice) {
      final priceStr = 'Rs.${price.toStringAsFixed(2)}';
      b.writeln('TEXT 300,$bottomY,"1",0,1,1,"$priceStr"');
    }

    // Key-value detail attributes (one per line, small font)
    var detailY = bottomY + 16;
    for (final e in details.entries) {
      if (e.key.trim().isEmpty) continue;
      b.writeln('TEXT 10,$detailY,"1",0,1,1,"${e.key}: ${e.value}"');
      detailY += 14;
    }

    b.writeln('PRINT 1,1');
    return b.toString();
  }

  static Future<void> _send(String ip, int port, String tspl) async {
    final socket = await Socket.connect(
      ip,
      port,
      timeout: const Duration(seconds: 5),
    );
    socket.write(tspl);
    await socket.flush();
    await socket.close();
  }
}
