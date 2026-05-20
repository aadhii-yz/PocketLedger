import 'dart:io';
import 'dart:typed_data';
import 'printer_connection.dart';
import 'printer_discovery.dart';

// ESC/POS for TVS RP 3230 (80mm, 42-char line width)
class EscPosPrinter {
  static Future<void> printReceipt({
    required PrinterConnection connection,
    required Map<String, dynamic> data,
  }) async {
    final bytes = _build(data);
    await _sendToConnection(connection, bytes);
  }

  static Future<void> testPrint({required PrinterConnection connection}) async {
    final p = _Buf();
    p.cmd([0x1b, 0x40]); // INIT
    p.cmd([0x1b, 0x61, 0x01]); // CENTER
    p.text('-- TEST PRINT --');
    p.lf();
    p.text('PocketLedger');
    p.lf();
    p.text('Receipt Printer OK');
    p.lf();
    p.lf();
    p.lf();
    p.lf();
    p.cmd([0x1d, 0x56, 0x00]); // FULL CUT
    await _sendToConnection(connection, p.build());
  }

  static Uint8List _build(Map<String, dynamic> d) {
    final p = _Buf();

    p.cmd([0x1b, 0x40]); // INIT

    // ── Header ──────────────────────────────────────────────────────────────
    final shopName = (d['shop_name'] as String? ?? 'Shop');
    p.cmd([0x1b, 0x61, 0x01]); // CENTER
    p.cmd([0x1b, 0x45, 0x01]); // BOLD ON
    p.cmd([0x1b, 0x21, 0x20]); // DOUBLE WIDTH
    p.text(shopName.length > 21 ? shopName.substring(0, 21) : shopName);
    p.lf();
    p.cmd([0x1b, 0x21, 0x00]); // NORMAL
    p.cmd([0x1b, 0x45, 0x00]); // BOLD OFF

    final addr = d['shop_address'] as String? ?? '';
    if (addr.isNotEmpty) {
      p.text(addr);
      p.lf();
    }
    final phone = d['shop_phone'] as String? ?? '';
    if (phone.isNotEmpty) {
      p.text('Ph: $phone');
      p.lf();
    }
    final gst = d['gst_number'] as String? ?? '';
    if (gst.isNotEmpty) {
      p.text('GST: $gst');
      p.lf();
    }

    p.cmd([0x1b, 0x61, 0x00]); // LEFT
    p.sep();
    p.text('Date   : ${_fmtDate(d['date'] as String? ?? '')}');
    p.lf();
    p.text('Bill No: ${d['bill_number'] ?? ''}');
    p.lf();
    p.sep();

    // ── Items ────────────────────────────────────────────────────────────────
    const nw = 20, qw = 4, rw = 9, aw = 9; // column widths (total = 42)
    p.cmd([0x1b, 0x45, 0x01]);
    p.text(_rpad('Item', nw));
    p.text(_lpad('Qty', qw));
    p.text(_lpad('Rate', rw));
    p.text(_lpad('Amt', aw));
    p.lf();
    p.cmd([0x1b, 0x45, 0x00]);
    p.sep();

    final items = d['items'] as List<dynamic>? ?? [];
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      var name = m['name'] as String? ?? '';
      if (name.length > nw) name = '${name.substring(0, nw - 1)}>';
      final qty = (m['qty'] as num? ?? 0).toDouble();
      final rate = (m['unit_price'] as num? ?? 0).toDouble();
      final amt = qty * rate;
      p.text(_rpad(name, nw));
      p.text(
          _lpad(_n(qty % 1 == 0 ? qty.toInt().toString() : _fmt(qty)), qw));
      p.text(_lpad(_fmt(rate), rw));
      p.text(_lpad(_fmt(amt), aw));
      p.lf();
    }

    p.sep();

    // ── Totals ───────────────────────────────────────────────────────────────
    const lw = 42 - 10;
    final showTax = d['show_tax_breakdown'] as bool? ?? true;
    if (showTax) {
      final subtotal = (d['subtotal'] as num? ?? 0).toDouble();
      final tax = (d['tax_total'] as num? ?? 0).toDouble();
      final disc = (d['discount'] as num? ?? 0).toDouble();
      p.text(_rpad('Subtotal', lw));
      p.text(_lpad('Rs.${_fmt(subtotal)}', 10));
      p.lf();
      p.text(_rpad('GST', lw));
      p.text(_lpad('Rs.${_fmt(tax)}', 10));
      p.lf();
      if (disc > 0) {
        p.text(_rpad('Discount', lw));
        p.text(_lpad('-Rs.${_fmt(disc)}', 10));
        p.lf();
      }
    }
    final grand = (d['grand_total'] as num? ?? 0).toDouble();
    p.cmd([0x1b, 0x45, 0x01]);
    p.text(_rpad('TOTAL', lw));
    p.text(_lpad('Rs.${_fmt(grand)}', 10));
    p.lf();
    p.cmd([0x1b, 0x45, 0x00]);

    p.sep();
    p.text(
        'Payment: ${((d['payment_method'] as String? ?? '')).toUpperCase()}');
    p.lf();

    final showCust = d['show_customer_info'] as bool? ?? true;
    final cName = d['customer_name'] as String? ?? '';
    final cPhone = d['customer_phone'] as String? ?? '';
    if (showCust && (cName.isNotEmpty || cPhone.isNotEmpty)) {
      final cust =
          [if (cName.isNotEmpty) cName, if (cPhone.isNotEmpty) cPhone]
              .join(' / ');
      p.sep();
      p.text('Customer: $cust');
      p.lf();
    }

    final footer = d['receipt_footer'] as String? ?? '';
    if (footer.isNotEmpty) {
      p.sep();
      p.cmd([0x1b, 0x61, 0x01]);
      p.text(footer);
      p.lf();
      p.cmd([0x1b, 0x61, 0x00]);
    }

    p.lf();
    p.lf();
    p.lf();
    p.cmd([0x1d, 0x56, 0x00]); // FULL CUT
    return p.build();
  }

  static String _fmt(double n) => n.toStringAsFixed(2);
  static String _n(String s) => s;

  static String _fmtDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      const m = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]} ${d.year}';
    } catch (_) {
      return iso;
    }
  }

  static String _rpad(String s, int w) {
    if (s.length > w) s = s.substring(0, w);
    return s.padRight(w);
  }

  static String _lpad(String s, int w) {
    if (s.length > w) s = s.substring(0, w);
    return s.padLeft(w);
  }

  // ── Transport ─────────────────────────────────────────────────────────────

  static Future<void> _sendToConnection(
      PrinterConnection connection, Uint8List data) async {
    switch (connection) {
      case TcpConnection(:final ip, :final port):
        await _sendTcp(ip, port, data);
      case UsbConnection(:final path):
        if (Platform.isLinux) {
          await _sendLinuxUsb(path, data);
        } else if (Platform.isWindows) {
          await _sendWindowsUsb(path, data);
        } else {
          throw UnsupportedError(
              'USB printing not supported on ${Platform.operatingSystem}');
        }
    }
  }

  static Future<void> _sendTcp(String ip, int port, Uint8List data) async {
    final socket =
        await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
    socket.add(data);
    await socket.flush();
    await socket.close();
  }

  // Linux: CUPS queue name (no leading '/') → lp -d queue -o raw file
  //        device path (/dev/usb/lp*) → write bytes directly
  static Future<void> _sendLinuxUsb(String path, Uint8List data) async {
    if (!path.startsWith('/')) {
      await _sendCups(path, data);
      return;
    }
    try {
      final sink = File(path).openWrite(mode: FileMode.writeOnlyAppend);
      sink.add(data);
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

  // Sends raw bytes via CUPS using `lp -d queueName -o raw tempFile`.
  static Future<void> _sendCups(String queueName, Uint8List data) async {
    final tempPath =
        '${Directory.systemTemp.path}/pl_${DateTime.now().millisecondsSinceEpoch}.bin';
    await File(tempPath).writeAsBytes(data);
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

  // Windows: send raw bytes via the Win32 spooler API (OpenPrinter/WritePrinter).
  // printerName is the installed printer display name (e.g. 'TVS RP 3230').
  static Future<void> _sendWindowsUsb(
      String printerName, Uint8List data) async {
    final log = PrinterDiscovery.instance.addLog;
    final ts = DateTime.now().millisecondsSinceEpoch;
    final tmpBin = '${Directory.systemTemp.path}\\pl_$ts.bin';
    final tmpPs = '${Directory.systemTemp.path}\\pl_$ts.ps1';
    log('Win print: "$printerName" ${data.length} B → $tmpBin');
    await File(tmpBin).writeAsBytes(data);
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

class _Buf {
  final List<int> _b = [];

  void cmd(List<int> bytes) => _b.addAll(bytes);

  void text(String s) {
    for (int i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      _b.add(c < 128 ? c : 0x3f); // '?' for non-ASCII
    }
  }

  void lf() => _b.add(0x0a);

  void sep([int width = 42]) {
    text('-' * width);
    lf();
  }

  Uint8List build() => Uint8List.fromList(_b);
}
