import 'package:shared_preferences/shared_preferences.dart';
import 'printer_connection.dart';

class SettingsService {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  String pocketledgerUrl = '';
  // USB path on Linux (/dev/usb/lp0) or CUPS queue name (TVS_RP3230)
  // or Windows port name (USB001). Empty when using TCP.
  String receiptUsbPath = '';
  String barcodeUsbPath = '';
  String barcodePrinterIp = '';
  int barcodePrinterPort = 9100;
  String receiptPrinterIp = '';
  int receiptPrinterPort = 9100;
  int serverPort = 8765;

  PrinterConnection? get receiptConnection {
    if (receiptUsbPath.isNotEmpty) return UsbConnection(receiptUsbPath);
    if (receiptPrinterIp.isNotEmpty) {
      return TcpConnection(receiptPrinterIp, receiptPrinterPort);
    }
    return null;
  }

  PrinterConnection? get barcodeConnection {
    if (barcodeUsbPath.isNotEmpty) return UsbConnection(barcodeUsbPath);
    if (barcodePrinterIp.isNotEmpty) {
      return TcpConnection(barcodePrinterIp, barcodePrinterPort);
    }
    return null;
  }

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    pocketledgerUrl = p.getString('pocketledger_url') ?? '';
    receiptUsbPath = p.getString('receipt_usb_path') ?? '';
    barcodeUsbPath = p.getString('barcode_usb_path') ?? '';
    barcodePrinterIp = p.getString('barcode_ip') ?? '';
    barcodePrinterPort = p.getInt('barcode_port') ?? 9100;
    receiptPrinterIp = p.getString('receipt_ip') ?? '';
    receiptPrinterPort = p.getInt('receipt_port') ?? 9100;
    serverPort = p.getInt('server_port') ?? 8765;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('pocketledger_url', pocketledgerUrl);
    await p.setString('receipt_usb_path', receiptUsbPath);
    await p.setString('barcode_usb_path', barcodeUsbPath);
    await p.setString('barcode_ip', barcodePrinterIp);
    await p.setInt('barcode_port', barcodePrinterPort);
    await p.setString('receipt_ip', receiptPrinterIp);
    await p.setInt('receipt_port', receiptPrinterPort);
    await p.setInt('server_port', serverPort);
  }
}
