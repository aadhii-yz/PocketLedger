// Android-only: keeps the HTTP server alive as a foreground service so the
// OS does not kill the companion app while the warehouse worker uses the PWA.
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'settings_service.dart';
import 'print_server.dart';

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'pocketledger_print',
      initialNotificationTitle: 'PocketLedger Print',
      initialNotificationContent: 'Print service active — ready to print',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );

  await service.startService();
}

// Runs in a separate Dart isolate as an Android foreground service.
// SharedPreferences is accessible cross-isolate via platform channels.
@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.load();
  await PrintServer.start(SettingsService.instance.serverPort);

  // Reload settings when the UI saves new printer IPs
  service.on('reload_settings').listen((_) async {
    await SettingsService.instance.load();
  });
}
