// Android-only: keeps the HTTP server alive as a foreground service so the
// OS does not kill the companion app while the warehouse worker uses the PWA.
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'settings_service.dart';
import 'print_server.dart';

const _kChannelId = 'pocketledger_print';
const _kNotificationId = 888;

Future<void> initBackgroundService() async {
  // Create the notification channel before the foreground service calls
  // startForeground(). On Android 14, startForeground() throws
  // CannotPostForegroundServiceNotificationException if the channel is missing.
  await FlutterLocalNotificationsPlugin()
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          _kChannelId,
          'PocketLedger Print Service',
          description: 'Keeps the silent print server running in the background',
          importance: Importance.low,
        ),
      );

  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: _onStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: _kChannelId,
      initialNotificationTitle: 'PocketLedger Print',
      initialNotificationContent: 'Print service active — ready to print',
      foregroundServiceNotificationId: _kNotificationId,
    ),
    iosConfiguration: IosConfiguration(autoStart: false),
  );

  if (!await service.isRunning()) {
    await service.startService();
  }
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
