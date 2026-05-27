import 'dart:io';
import 'printer_connection.dart';
import 'printer_discovery.dart';

// TSPL commands for TVS LP 46 dlite (203 DPI, 1mm = 8 dots)
// Default label: 50mm x 30mm with 2mm gap
class TsplPrinter {
  static Future<void> printBarcode({
    required PrinterConnection connection,
    String template = 'standard',
    required String name,
    required String barcode,
    required String sku,
    required double price,
    bool showSku = true,
    bool showPrice = true,
    String shopName = '',
    Map<String, String> details = const {},
  }) async {
    final cmds = _buildLabel(
      template,
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

  static String _buildLabel(
    String template, {
    required String name,
    required String barcode,
    required String sku,
    required double price,
    bool showSku = true,
    bool showPrice = true,
    String shopName = '',
    Map<String, String> details = const {},
  }) {
    switch (template) {
      case 'small':
        return _buildSmall(
          name: name, barcode: barcode, sku: sku, price: price,
          showSku: showSku, showPrice: showPrice, shopName: shopName,
        );
      case 'large':
        return _buildLarge(
          name: name, barcode: barcode, sku: sku, price: price,
          showSku: showSku, showPrice: showPrice, shopName: shopName,
          details: details,
        );
      default:
        return _buildStandard(
          name: name, barcode: barcode, sku: sku, price: price,
          showSku: showSku, showPrice: showPrice, shopName: shopName,
          details: details,
        );
    }
  }

  // 50 × 30 mm — default layout (current)
  static String _buildStandard({
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

  // 40 × 20 mm — compact layout for small tags and accessories
  static String _buildSmall({
    required String name,
    required String barcode,
    required String sku,
    required double price,
    bool showSku = true,
    bool showPrice = true,
    String shopName = '',
  }) {
    final b = StringBuffer();

    b.writeln('SIZE 40 mm, 20 mm');
    b.writeln('GAP 2 mm, 0 mm');
    b.writeln('DIRECTION 0');
    b.writeln('REFERENCE 0,0');
    b.writeln('CLS');

    if (shopName.isNotEmpty) {
      final sn = shopName.length > 32 ? shopName.substring(0, 32) : shopName;
      b.writeln('TEXT 5,2,"1",0,1,1,"$sn"');
    }

    final displayName = name.length > 36 ? '${name.substring(0, 35)}>' : name;
    final nameY = shopName.isNotEmpty ? 13 : 2;
    b.writeln('TEXT 5,$nameY,"1",0,1,1,"$displayName"');

    final bcY = nameY + 12;
    b.writeln('BARCODE 5,$bcY,"128",28,1,0,2,2,"$barcode"');

    final bottomY = bcY + 34;
    if (showSku && sku.isNotEmpty) {
      b.writeln('TEXT 5,$bottomY,"1",0,1,1,"SKU: $sku"');
    }
    if (showPrice) {
      final priceStr = 'Rs.${price.toStringAsFixed(2)}';
      b.writeln('TEXT 240,$bottomY,"1",0,1,1,"$priceStr"');
    }

    b.writeln('PRINT 1,1');
    return b.toString();
  }

  // 60 × 40 mm — spacious layout for hang tags and boxed items
  static String _buildLarge({
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

    b.writeln('SIZE 60 mm, 40 mm');
    b.writeln('GAP 2 mm, 0 mm');
    b.writeln('DIRECTION 0');
    b.writeln('REFERENCE 0,0');
    b.writeln('CLS');

    if (shopName.isNotEmpty) {
      final sn = shopName.length > 58 ? shopName.substring(0, 58) : shopName;
      b.writeln('TEXT 10,2,"1",0,1,1,"$sn"');
    }

    final displayName = name.length > 55 ? '${name.substring(0, 54)}>' : name;
    final nameY = shopName.isNotEmpty ? 18 : 5;
    b.writeln('TEXT 10,$nameY,"2",0,1,1,"$displayName"');

    final bcY = nameY + 22;
    b.writeln('BARCODE 10,$bcY,"128",60,1,0,2,2,"$barcode"');

    final bottomY = bcY + 76;
    if (showSku && sku.isNotEmpty) {
      b.writeln('TEXT 10,$bottomY,"1",0,1,1,"SKU: $sku"');
    }
    if (showPrice) {
      final priceStr = 'Rs.${price.toStringAsFixed(2)}';
      b.writeln('TEXT 380,$bottomY,"1",0,1,1,"$priceStr"');
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

  // Windows: send TSPL bytes via the Win32 spooler API (OpenPrinter/WritePrinter).
  // printerName is the installed printer display name (e.g. 'TVS LP 46 DLITE').
  static Future<void> _sendWindowsUsb(String printerName, String tspl) async {
    final log = PrinterDiscovery.instance.addLog;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final tmpBin = '${Directory.systemTemp.path}\\pl_$ts.bin';
    final tmpPs = '${Directory.systemTemp.path}\\pl_$ts.ps1';
    log('Win print: "$printerName" ${tspl.length} chars → $tmpBin');
    await File(tmpBin).writeAsString(tspl);
    final safeName = printerName.replaceAll("'", "''");
    final safeBin = tmpBin.replaceAll("'", "''");
    await File(tmpPs).writeAsString(_winSpoolerScript(safeName, safeBin));
    try {
      final r = await Process.run('powershell', [
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', tmpPs,
      ]);
      final out = (r.stdout as String).trim();
      final err = (r.stderr as String).trim();
      log('Win print: PS exit=${r.exitCode}'
          '${out.isNotEmpty ? ' stdout="$out"' : ''}'
          '${err.isNotEmpty ? ' stderr="$err"' : ''}');
      if (r.exitCode != 0) {
        throw Exception('Windows print failed (exit ${r.exitCode})'
            '${err.isNotEmpty ? ': $err' : ''}');
      }
    } finally {
      for (final p in [tmpBin, tmpPs]) {
        try {
          await File(p).delete();
        } catch (_) {}
      }
    }
  }

  static String _winSpoolerScript(String printerName, String binPath) => '''
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public class PL {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
  public class DI {
    [MarshalAs(UnmanagedType.LPStr)] public string n;
    [MarshalAs(UnmanagedType.LPStr)] public string o;
    [MarshalAs(UnmanagedType.LPStr)] public string t;
  }
  [DllImport("winspool.drv", EntryPoint = "OpenPrinterA", CharSet = CharSet.Ansi)]
  public static extern bool Open(string name, out IntPtr h, IntPtr d);
  [DllImport("winspool.drv", EntryPoint = "ClosePrinter")]
  public static extern bool Close(IntPtr h);
  [DllImport("winspool.drv", EntryPoint = "StartDocPrinterA", CharSet = CharSet.Ansi)]
  public static extern bool StartDoc(IntPtr h, int l, [In, MarshalAs(UnmanagedType.LPStruct)] DI di);
  [DllImport("winspool.drv", EntryPoint = "EndDocPrinter")]
  public static extern bool EndDoc(IntPtr h);
  [DllImport("winspool.drv", EntryPoint = "StartPagePrinter")]
  public static extern bool StartPage(IntPtr h);
  [DllImport("winspool.drv", EntryPoint = "EndPagePrinter")]
  public static extern bool EndPage(IntPtr h);
  [DllImport("winspool.drv", EntryPoint = "WritePrinter")]
  public static extern bool Write(IntPtr h, byte[] b, int n, out int w);
}
'@
\$ErrorActionPreference = 'Stop'
\$b = [IO.File]::ReadAllBytes('$binPath')
\$h = [IntPtr]::Zero
if (-not [PL]::Open('$printerName', [ref]\$h, [IntPtr]::Zero)) { throw "OpenPrinter('$printerName') failed" }
\$d = New-Object PL+DI; \$d.n = 'PL'; \$d.t = 'RAW'
[PL]::StartDoc(\$h, 1, \$d) | Out-Null
[PL]::StartPage(\$h) | Out-Null
\$w = 0; [PL]::Write(\$h, \$b, \$b.Length, [ref]\$w) | Out-Null
[PL]::EndPage(\$h) | Out-Null; [PL]::EndDoc(\$h) | Out-Null; [PL]::Close(\$h) | Out-Null
''';
}
