import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/printer_discovery.dart';

enum _Step { instructions, scanning, credentials, saving, success, error }

class WifiConfigScreen extends StatefulWidget {
  const WifiConfigScreen({super.key});

  @override
  State<WifiConfigScreen> createState() => _WifiConfigScreenState();
}

class _WifiConfigScreenState extends State<WifiConfigScreen> {
  _Step _step = _Step.instructions;
  List<Map<String, String>> _networks = []; // {ssid, mac}
  String? _selectedSsid;
  String? _selectedBssid;
  final _passwordCtrl = TextEditingController();
  bool _passwordVisible = false;
  String? _errorMsg;
  String? _debugPayload;
  String? _debugResponse;
  String? _sessionCookie; // captured from /scanap response, relayed to /connap

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _scanNetworks() async {
    setState(() => _step = _Step.scanning);
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      // Hit the root page first so the firmware can issue a session cookie,
      // then relay that cookie to the POST /connap request later.
      try {
        final homeReq = await client.getUrl(Uri.parse('http://192.168.4.1/'));
        final homeRes = await homeReq.close().timeout(const Duration(seconds: 5));
        final cookies = homeRes.headers['set-cookie'];
        if (cookies != null && cookies.isNotEmpty) {
          _sessionCookie = cookies.map((c) => c.split(';')[0]).join('; ');
        }
        await homeRes.drain<void>();
      } catch (_) {}
      final req = await client.getUrl(Uri.parse('http://192.168.4.1/scanap'));
      final res = await req.close().timeout(const Duration(seconds: 15));
      // Also capture any cookie set on /scanap itself.
      final scanCookies = res.headers['set-cookie'];
      if (scanCookies != null && scanCookies.isNotEmpty) {
        final extra = scanCookies.map((c) => c.split(';')[0]).join('; ');
        _sessionCookie = _sessionCookie != null ? '$_sessionCookie; $extra' : extra;
      }
      final body = await res.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['state'] == 0) {
        final seen = <String>{};
        final networks = (json['wifilist'] as List)
            .map((e) => {'ssid': e['ssid'] as String, 'mac': e['mac'] as String? ?? ''})
            .where((e) => e['ssid']!.isNotEmpty && seen.add(e['ssid']!))
            .toList();
        setState(() {
          _networks = networks;
          _selectedSsid = networks.isNotEmpty ? networks.first['ssid'] : null;
          _selectedBssid = networks.isNotEmpty ? networks.first['mac'] : null;
          _step = _Step.credentials;
        });
      } else {
        setState(() {
          _errorMsg = 'Printer returned error ${json['state']} on /scanap.';
          _step = _Step.error;
        });
      }
    } catch (e) {
      setState(() {
        _errorMsg = 'Cannot reach printer at 192.168.4.1.\n\n'
            'Make sure your device is connected to DEFAULT_AP_CB8F29.\n\n'
            'Detail: $e';
        _step = _Step.error;
      });
    }
  }

  // Raw TCP so we control exact header name capitalisation.
  // Dart's HttpClient lowercases all header names; some ESP firmware HTTP parsers
  // are case-sensitive and won't recognise 'content-type' instead of 'Content-Type'.
  Future<String> _rawPost(String payload) async {
    final bodyBytes = utf8.encode(payload);
    // Build request with exact mixed-case header names that jQuery/browser sends.
    final reqLines = StringBuffer()
      ..write('POST /connap HTTP/1.1\r\n')
      ..write('Host: 192.168.4.1\r\n')
      ..write('Content-Type: application/json\r\n')
      ..write('X-Requested-With: XMLHttpRequest\r\n')
      ..write('Accept: application/json, text/javascript, */*; q=0.01\r\n')
      ..write('Origin: http://192.168.4.1\r\n')
      ..write('Referer: http://192.168.4.1/pages/wifi/station.html\r\n')
      ..write('Content-Length: ${bodyBytes.length}\r\n');
    if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
      reqLines.write('Cookie: $_sessionCookie\r\n');
    }
    reqLines.write('Connection: close\r\n\r\n');

    final socket = await Socket.connect('192.168.4.1', 80,
        timeout: const Duration(seconds: 8));
    try {
      // Start accumulating response before sending so no bytes are missed.
      final responseFuture = socket.fold<List<int>>(
          [], (acc, chunk) { acc.addAll(chunk); return acc; });
      socket.add(utf8.encode(reqLines.toString()));
      socket.add(bodyBytes);
      await socket.flush();

      final responseBytes =
          await responseFuture.timeout(const Duration(seconds: 10));
      final response = utf8.decode(responseBytes, allowMalformed: true);
      // Strip HTTP response headers — body starts after the blank line.
      final sep = response.indexOf('\r\n\r\n');
      return sep >= 0 ? response.substring(sep + 4).trim() : response.trim();
    } finally {
      socket.destroy();
    }
  }

  Future<void> _saveConfig() async {
    if (_selectedSsid == null) return;
    setState(() => _step = _Step.saving);
    try {
      final bssid = _selectedBssid ?? '';
      // autoconn=undefined: station.html has no radio button for this field, so the
      // reference web UI produces the literal JS string "autoconn=undefined".
      final payload = 'ssid=$_selectedSsid'
          '&pwd=${_passwordCtrl.text}'
          '&bssid=$bssid'
          '&autoconn=undefined';

      final body = await _rawPost(payload);
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['state'] == 0) {
        setState(() => _step = _Step.success);
      } else {
        final code = json['error_code'] ?? json['state'];
        const codeMap = {
          400: 'bad params',
          406: 'wrong request type',
          500: 'server error',
          600: 'wrong password',
        };
        final detail = codeMap[code] ?? 'unknown';
        setState(() {
          _debugPayload = payload;
          _debugResponse = body;
          _errorMsg = 'Printer returned error $code ($detail).\n\n'
              '400 = bad params, 406 = wrong request type, '
              '500 = server error, 600 = wrong password.';
          _step = _Step.error;
        });
      }
    } catch (e) {
      setState(() {
        _errorMsg = 'Request failed: $e';
        _step = _Step.error;
      });
    }
  }

  void _done() {
    PrinterDiscovery.instance.scanBarcodeNow();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configure Printer WiFi'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: switch (_step) {
          _Step.instructions => _buildInstructions(),
          _Step.scanning => _buildSpinner('Scanning available networks…'),
          _Step.credentials => _buildCredentials(),
          _Step.saving => _buildSpinner('Configuring printer…'),
          _Step.success => _buildSuccess(),
          _Step.error => _buildError(),
        },
      ),
    );
  }

  Widget _buildInstructions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.wifi_find, size: 48, color: Colors.blue),
        const SizedBox(height: 16),
        const Text(
          'Connect to the printer hotspot',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _infoBox(
          'Go to your device\'s WiFi settings and connect to:\n\n'
          '  Network: DEFAULT_AP_CB8F29\n'
          '  Password: 12345678\n\n'
          'Come back to this app once connected.',
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _scanNetworks,
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continue'),
          ),
        ),
      ],
    );
  }

  Widget _buildCredentials() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.wifi, size: 48, color: Colors.blue),
        const SizedBox(height: 16),
        const Text(
          'Enter WiFi credentials',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'Select the network you want the printer to join.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          value: _selectedSsid,
          decoration: const InputDecoration(
            labelText: 'Network (SSID)',
            border: OutlineInputBorder(),
          ),
          items: _networks
              .map((n) => DropdownMenuItem(value: n['ssid'], child: Text(n['ssid']!)))
              .toList(),
          onChanged: (v) => setState(() {
            _selectedSsid = v;
            _selectedBssid = _networks
                .firstWhere((n) => n['ssid'] == v, orElse: () => {'mac': ''})['mac'];
          }),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordCtrl,
          obscureText: !_passwordVisible,
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(
                  _passwordVisible ? Icons.visibility_off : Icons.visibility),
              onPressed: () =>
                  setState(() => _passwordVisible = !_passwordVisible),
            ),
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _selectedSsid != null ? _saveConfig : null,
            icon: const Icon(Icons.save),
            label: const Text('Save & Configure'),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, size: 48, color: Colors.green),
        const SizedBox(height: 16),
        const Text(
          'Printer configured!',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _infoBox(
          'The printer is now connecting to "$_selectedSsid".\n\n'
          'Switch your device back to your regular WiFi network, '
          'then tap Done — the app will scan and discover the printer\'s new IP.',
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _done,
            icon: const Icon(Icons.check),
            label: const Text('Done'),
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline, size: 48, color: Colors.red),
        const SizedBox(height: 16),
        const Text(
          'Something went wrong',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Text(
            _errorMsg ?? 'Unknown error',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (_debugPayload != null) ...[
          const SizedBox(height: 12),
          const Text('Sent payload:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          SelectableText(
            _debugPayload!,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
        if (_debugResponse != null) ...[
          const SizedBox(height: 8),
          const Text('Raw response:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          SelectableText(
            _debugResponse!,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Manual fallback',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        const Text(
          'While connected to DEFAULT_AP_CB8F29, open this URL in your browser '
          'to configure the printer manually:',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        SelectableText(
          'http://192.168.4.1/pages/wifi/station.html',
          style: TextStyle(
            fontSize: 13,
            fontFamily: 'monospace',
            color: Colors.blue.shade700,
          ),
        ),
        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => setState(() {
              _step = _Step.instructions;
              _errorMsg = null;
              _debugPayload = null;
              _debugResponse = null;
            }),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ),
      ],
    );
  }

  Widget _buildSpinner(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(message, style: const TextStyle(fontSize: 15)),
        ],
      ),
    );
  }

  Widget _infoBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Text(text, style: const TextStyle(fontSize: 14)),
    );
  }
}
