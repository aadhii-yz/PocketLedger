import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

class UpdateInfo {
  final String version;
  final String releasePageUrl;
  final String? apkDownloadUrl;

  const UpdateInfo({
    required this.version,
    required this.releasePageUrl,
    this.apkDownloadUrl,
  });
}

class UpdateService {
  // Fetch the list so we can filter for companion-only tags (v{n}.*).
  // /releases/latest returns the most recently published release across all
  // tag formats, which would miss companion releases when a backend release
  // is newer.
  static const _listUrl =
      'https://api.github.com/repos/aadhii-yz/PocketLedger/releases?per_page=20';

  static final _companionTag = RegExp(r'^v\d+\.\d+');

  static Future<UpdateInfo?> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version;

      final response = await http.get(
        Uri.parse(_listUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final releases = jsonDecode(response.body) as List;
      // Find the first non-draft, non-prerelease companion release (v{n}.*)
      final data = releases.cast<Map<String, dynamic>>().firstWhere(
            (r) =>
                r['draft'] != true &&
                r['prerelease'] != true &&
                _companionTag.hasMatch(r['tag_name'] as String? ?? ''),
            orElse: () => {},
          );

      if (data.isEmpty) return null;

      final tag =
          (data['tag_name'] as String).replaceFirst(RegExp(r'^v'), '');

      if (!_isNewer(current, tag)) return null;

      final assets = (data['assets'] as List? ?? []);
      String? apkUrl;
      for (final asset in assets) {
        final name = asset['name'] as String? ?? '';
        final url = asset['browser_download_url'] as String? ?? '';
        if (name.endsWith('-android.apk')) apkUrl = url;
      }

      return UpdateInfo(
        version: tag,
        releasePageUrl: data['html_url'] as String? ?? '',
        apkDownloadUrl: apkUrl,
      );
    } catch (_) {
      return null;
    }
  }

  static bool _isNewer(String current, String latest) {
    final c = _parts(current);
    final l = _parts(latest);
    for (var i = 0; i < 3; i++) {
      final ci = i < c.length ? c[i] : 0;
      final li = i < l.length ? l[i] : 0;
      if (li > ci) return true;
      if (li < ci) return false;
    }
    return false;
  }

  static List<int> _parts(String v) =>
      v.split('.').map((s) => int.tryParse(s) ?? 0).toList();

  // Android only: stream-download the APK and trigger the system install prompt.
  static Future<void> downloadAndInstallApk(
    String url,
    void Function(double progress) onProgress,
  ) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/update.apk';
    final file = File(path);

    final request = http.Request('GET', Uri.parse(url));
    final streamed = await http.Client().send(request);
    final total = streamed.contentLength ?? 0;
    var received = 0;

    final sink = file.openWrite();
    await for (final chunk in streamed.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total);
    }
    await sink.close();

    await OpenFilex.open(path);
  }
}
