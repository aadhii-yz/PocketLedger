import 'dart:io';
import 'dart:typed_data';

// ESC/POS for TVS RP 3230 (80mm, 42-char line width)
class EscPosPrinter {
  static Future<void> printReceipt({
    required String ip,
    required int port,
    required Map<String, dynamic> data,
  }) async {
    final bytes = _build(data);
    await _send(ip, port, bytes);
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
    if (addr.isNotEmpty) { p.text(addr); p.lf(); }
    final phone = d['shop_phone'] as String? ?? '';
    if (phone.isNotEmpty) { p.text('Ph: $phone'); p.lf(); }
    final gst = d['gst_number'] as String? ?? '';
    if (gst.isNotEmpty) { p.text('GST: $gst'); p.lf(); }

    p.cmd([0x1b, 0x61, 0x00]); // LEFT
    p.sep();
    p.text('Date   : ${_fmtDate(d['date'] as String? ?? '')}'); p.lf();
    p.text('Bill No: ${d['bill_number'] ?? ''}'); p.lf();
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
      p.text(_lpad(_n(qty % 1 == 0 ? qty.toInt().toString() : _fmt(qty)), qw));
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
      p.text(_rpad('Subtotal', lw)); p.text(_lpad('Rs.${_fmt(subtotal)}', 10)); p.lf();
      p.text(_rpad('GST', lw));      p.text(_lpad('Rs.${_fmt(tax)}', 10));      p.lf();
      if (disc > 0) {
        p.text(_rpad('Discount', lw)); p.text(_lpad('-Rs.${_fmt(disc)}', 10)); p.lf();
      }
    }
    final grand = (d['grand_total'] as num? ?? 0).toDouble();
    p.cmd([0x1b, 0x45, 0x01]);
    p.text(_rpad('TOTAL', lw)); p.text(_lpad('Rs.${_fmt(grand)}', 10)); p.lf();
    p.cmd([0x1b, 0x45, 0x00]);

    p.sep();
    p.text('Payment: ${((d['payment_method'] as String? ?? '')).toUpperCase()}'); p.lf();

    final showCust = d['show_customer_info'] as bool? ?? true;
    final cName = d['customer_name'] as String? ?? '';
    final cPhone = d['customer_phone'] as String? ?? '';
    if (showCust && (cName.isNotEmpty || cPhone.isNotEmpty)) {
      final cust = [if (cName.isNotEmpty) cName, if (cPhone.isNotEmpty) cPhone].join(' / ');
      p.sep();
      p.text('Customer: $cust'); p.lf();
    }

    final footer = d['receipt_footer'] as String? ?? '';
    if (footer.isNotEmpty) {
      p.sep();
      p.cmd([0x1b, 0x61, 0x01]);
      p.text(footer); p.lf();
      p.cmd([0x1b, 0x61, 0x00]);
    }

    p.lf(); p.lf(); p.lf();
    p.cmd([0x1d, 0x56, 0x00]); // FULL CUT
    return p.build();
  }

  static String _fmt(double n) => n.toStringAsFixed(2);
  static String _n(String s) => s;

  static String _fmtDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
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

  static Future<void> _send(String ip, int port, Uint8List data) async {
    final socket = await Socket.connect(
      ip,
      port,
      timeout: const Duration(seconds: 5),
    );
    socket.add(data);
    await socket.flush();
    await socket.close();
  }
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
