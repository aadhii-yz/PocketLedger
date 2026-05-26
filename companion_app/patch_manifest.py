"""
Patches the Flutter-generated AndroidManifest.xml to add the permissions
and background service declaration required by flutter_background_service.
Run from the companion_app/ directory.
"""

path = 'android/app/src/main/AndroidManifest.xml'

with open(path) as f:
    content = f.read()

permissions = (
    '    <uses-permission android:name="android.permission.INTERNET"/>\n'
    '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>\n'
    '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_DATA_SYNC"/>\n'
    '    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>\n'
    '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
    # wifi_iot: required for programmatic WiFi connection (auto WiFi switcher)
    '    <uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>\n'
    '    <uses-permission android:name="android.permission.CHANGE_WIFI_STATE"/>\n'
    '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n'
    '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n'
    '    '
)

service = (
    '\n        <service\n'
    '            android:name="id.flutter.flutter_background_service.BackgroundService"\n'
    '            android:foregroundServiceType="dataSync"\n'
    '            android:exported="false"\n'
    '            tools:replace="android:exported"/>'
)

content = content.replace('    <application', permissions + '<application', 1)
content = content.replace('</application>', service + '\n    </application>', 1)
# Add tools namespace to <manifest> if not already present
if 'xmlns:tools' not in content:
    content = content.replace(
        '<manifest xmlns:android=',
        '<manifest xmlns:android=',
        1,
    )
    content = content.replace(
        'xmlns:android="http://schemas.android.com/apk/res/android"',
        'xmlns:android="http://schemas.android.com/apk/res/android"\n    xmlns:tools="http://schemas.android.com/tools"',
        1,
    )

with open(path, 'w') as f:
    f.write(content)

print('Patched AndroidManifest.xml')
