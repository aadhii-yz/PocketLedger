import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService instance = SettingsService._();
  SettingsService._();

  String pocketledgerUrl = '';
  String barcodePrinterIp = '';
  int barcodePrinterPort = 9100;
  String receiptPrinterIp = '';
  int receiptPrinterPort = 9100;
  int serverPort = 8765;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    pocketledgerUrl = p.getString('pocketledger_url') ?? '';
    barcodePrinterIp = p.getString('barcode_ip') ?? '';
    barcodePrinterPort = p.getInt('barcode_port') ?? 9100;
    receiptPrinterIp = p.getString('receipt_ip') ?? '';
    receiptPrinterPort = p.getInt('receipt_port') ?? 9100;
    serverPort = p.getInt('server_port') ?? 8765;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('pocketledger_url', pocketledgerUrl);
    await p.setString('barcode_ip', barcodePrinterIp);
    await p.setInt('barcode_port', barcodePrinterPort);
    await p.setString('receipt_ip', receiptPrinterIp);
    await p.setInt('receipt_port', receiptPrinterPort);
    await p.setInt('server_port', serverPort);
  }
}
