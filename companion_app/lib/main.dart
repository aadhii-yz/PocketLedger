import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/settings_service.dart';
import 'services/background_service.dart';
import 'services/printer_discovery.dart';
import 'screens/home_screen.dart';
import 'screens/web_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.load();

  if (Platform.isAndroid) {
    // When discovery auto-finds a printer and saves new IPs to SharedPreferences,
    // notify the background service isolate to reload its copy of settings.
    PrinterDiscovery.onSettingsUpdated = () {
      FlutterBackgroundService().invoke('reload_settings');
    };

    await Permission.notification.request();
    await initBackgroundService();
    if (SettingsService.instance.backgroundServiceEnabled) {
      await FlutterBackgroundService().startService();
    }
  }

  runApp(const CompanionApp());
}

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PocketLedger Print',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E40AF)),
        useMaterial3: true,
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 0;
  int _webKey = 0;

  void _onSettingsSaved() {
    setState(() {
      _webKey++;
      _tab = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          WebScreen(key: ValueKey(_webKey)),
          HomeScreen(onSaved: _onSettingsSaved),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.web), label: 'App'),
          NavigationDestination(
              icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
