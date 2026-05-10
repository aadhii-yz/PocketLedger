import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/settings_service.dart';
import 'services/background_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.load();

  if (Platform.isAndroid) {
    // Android 13+ (API 33+) requires POST_NOTIFICATIONS to be granted at
    // runtime before a foreground service can post its persistent notification.
    await Permission.notification.request();
    await initBackgroundService();
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
      home: const HomeScreen(),
    );
  }
}
