"""
Patches the Flutter-generated AndroidManifest.xml to add the permissions
and component declarations required by the companion app.
Run from the companion_app/ directory.
"""

import os

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
    # open_filex: required to prompt APK install for in-app updates
    '    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>\n'
    '    '
)

service = (
    '\n        <service\n'
    '            android:name="id.flutter.flutter_background_service.BackgroundService"\n'
    '            android:foregroundServiceType="dataSync"\n'
    '            android:exported="false"\n'
    '            tools:replace="android:exported"/>'
)

# open_filex FileProvider: required to share the downloaded APK URI on Android 7+
provider = (
    '\n        <provider\n'
    '            android:name="androidx.core.content.FileProvider"\n'
    '            android:authorities="${applicationId}.open_filex.provider"\n'
    '            android:exported="false"\n'
    '            android:grantUriPermissions="true">\n'
    '            <meta-data\n'
    '                android:name="android.support.FILE_PROVIDER_PATHS"\n'
    '                android:resource="@xml/open_filex_provider_paths"/>\n'
    '        </provider>'
)

content = content.replace('    <application', permissions + '<application', 1)
content = content.replace(
    '</application>',
    service + provider + '\n    </application>',
    1,
)
# Add tools namespace to <manifest> if not already present
if 'xmlns:tools' not in content:
    content = content.replace(
        'xmlns:android="http://schemas.android.com/apk/res/android"',
        'xmlns:android="http://schemas.android.com/apk/res/android"\n    xmlns:tools="http://schemas.android.com/tools"',
        1,
    )

with open(path, 'w') as f:
    f.write(content)

print('Patched AndroidManifest.xml')

# Create the FileProvider paths resource required by open_filex
xml_dir = 'android/app/src/main/res/xml'
os.makedirs(xml_dir, exist_ok=True)
with open(f'{xml_dir}/open_filex_provider_paths.xml', 'w') as f:
    f.write(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<paths>\n'
        '    <external-path name="external_files" path="."/>\n'
        '    <cache-path name="cache_files" path="."/>\n'
        '</paths>\n'
    )

print('Created open_filex_provider_paths.xml')
