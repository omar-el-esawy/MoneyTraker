import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/services/app_update_logic.dart';

class VersionCheck {
  final String currentVersion;
  final int currentBuild;
  final String latestVersion;
  final int? latestBuild;
  final bool newer;
  final UpdateOffer? offer;

  const VersionCheck({
    required this.currentVersion,
    required this.currentBuild,
    required this.latestVersion,
    required this.latestBuild,
    required this.newer,
    required this.offer,
  });

  String get currentLabel => releaseLabel(currentVersion, currentBuild);
  String get latestLabel => releaseLabel(latestVersion, latestBuild);
}

class UpdateOffer {
  final String version;
  final int? buildNumber;
  final bool force;
  final String downloadUrl;
  final String changelog;

  const UpdateOffer({
    required this.version,
    required this.buildNumber,
    required this.force,
    required this.downloadUrl,
    required this.changelog,
  });
}

enum InstallStart { opened, needsPermission, failed }

class AppUpdateService {
  AppUpdateService._();

  /// A release file changes only when you publish, so a few hours is enough.
  static const cacheFor = Duration(hours: 6);
  static const _manifestKey = 'app_update.manifest';
  static const _fetchedAtKey = 'app_update.fetched_at';
  static const _channel = MethodChannel('com.example.money_traker/update');

  static UpdateOffer? _pending;

  /// Optional update kept for the home screen. A forced update is not stored.
  static UpdateOffer? takePendingOffer() {
    final offer = _pending;
    _pending = null;
    return offer;
  }

  /// Never throws. No network, a bad file, or a timeout leaves the app usable.
  /// Returns a forced offer when the home screen must stay hidden.
  static Future<UpdateOffer?> check() async {
    if (!Platform.isAndroid) return null;
    final result = await checkLatest();
    return result?.offer;
  }

  /// Fetches the published version. [refresh] skips the saved copy.
  /// Returns null when the version file cannot be read.
  static Future<VersionCheck?> checkLatest({bool refresh = false}) async {
    try {
      return await _checkLatest(
        refresh: refresh,
      ).timeout(const Duration(seconds: 10));
    } catch (e, stack) {
      debugPrint('App update check failed: $e\n$stack');
      return null;
    }
  }

  static Future<VersionCheck?> _checkLatest({required bool refresh}) async {
    final url = AppConstants.versionManifestUrl.trim();
    if (url.isEmpty) {
      debugPrint('App update check skipped: versionManifestUrl is empty.');
      return null;
    }

    final release = await _loadRelease(url, refresh: refresh);
    if (release == null) return null;

    final info = await PackageInfo.fromPlatform();
    final localBuild = int.tryParse(info.buildNumber) ?? 0;
    final newer = isRemoteNewer(
      localVersion: info.version,
      localBuild: localBuild,
      remoteVersion: release.version,
      remoteBuild: release.buildNumber,
    );
    UpdateOffer? offer;
    if (newer && Platform.isAndroid) {
      offer = UpdateOffer(
        version: release.version,
        buildNumber: release.buildNumber,
        force: release.forceUpdate,
        downloadUrl: release.downloadUrl,
        changelog: release.changelog,
      );
      if (!offer.force && !refresh) _pending = offer;
    }
    return VersionCheck(
      currentVersion: info.version,
      currentBuild: localBuild,
      latestVersion: release.version,
      latestBuild: release.buildNumber,
      newer: newer,
      offer: offer,
    );
  }

  static Future<RemoteRelease?> _loadRelease(
    String url, {
    bool refresh = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedBody = prefs.getString(_manifestKey);
    final fetchedAt = prefs.getInt(_fetchedAtKey) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - fetchedAt;
    if (!refresh &&
        cachedBody != null &&
        age >= 0 &&
        age < cacheFor.inMilliseconds) {
      final cached = _decode(cachedBody);
      if (cached != null) return cached;
    }

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) {
        throw HttpException('version.json ${response.statusCode}');
      }
      final parsed = _decode(response.body);
      if (parsed == null) throw const FormatException('version.json');
      await prefs.setString(_manifestKey, response.body);
      await prefs.setInt(_fetchedAtKey, DateTime.now().millisecondsSinceEpoch);
      return parsed;
    } catch (e) {
      debugPrint('App update request failed: $e');
      if (cachedBody == null) return null;
      return _decode(cachedBody);
    }
  }

  static RemoteRelease? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return parseRemoteRelease(Map<String, dynamic>.from(decoded));
    } catch (e) {
      debugPrint('App update file was not valid JSON: $e');
      return null;
    }
  }

  static Future<File> downloadApk(
    String url,
    void Function(double? progress) onProgress,
  ) async {
    final uri = Uri.parse(url);
    final dir = await getTemporaryDirectory();
    final target = File(p.join(dir.path, 'money_traker-update.apk'));
    final part = File('${target.path}.part');
    if (await part.exists()) await part.delete();

    final client = http.Client();
    IOSink? sink;
    var completed = false;
    try {
      final response = await client
          .send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw HttpException('Download failed (${response.statusCode})');
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      sink = part.openWrite();
      await for (final chunk in response.stream.timeout(
        const Duration(minutes: 3),
      )) {
        received += chunk.length;
        sink.add(chunk);
        onProgress(total > 0 ? received / total : null);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received < 1) throw const HttpException('Empty update file');
      if (await target.exists()) await target.delete();
      final saved = await part.rename(target.path);
      completed = true;
      return saved;
    } finally {
      client.close();
      final open = sink;
      sink = null;
      if (open != null) {
        try {
          await open.close();
        } catch (_) {}
      }
      if (!completed && await part.exists()) {
        await part.delete();
      }
    }
  }

  static Future<bool> canRequestPackageInstalls() async {
    try {
      final allowed = await _channel.invokeMethod<bool>(
        'canRequestPackageInstalls',
      );
      return allowed ?? false;
    } catch (e) {
      debugPrint('Install permission check failed: $e');
      return false;
    }
  }

  static Future<void> openInstallPermissionSettings() {
    return _channel.invokeMethod<void>('openInstallPermissionSettings');
  }

  static Future<InstallStart> openApk(File file) async {
    if (!await file.exists() || await file.length() < 1) {
      return InstallStart.failed;
    }
    final allowed = await canRequestPackageInstalls();
    if (!allowed) return InstallStart.needsPermission;
    try {
      final result = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
      if (result.type == ResultType.done) return InstallStart.opened;
      debugPrint('Could not open update: ${result.type} ${result.message}');
      if (result.type == ResultType.permissionDenied) {
        return InstallStart.needsPermission;
      }
      return InstallStart.failed;
    } catch (e) {
      debugPrint('Could not open update: $e');
      return InstallStart.failed;
    }
  }
}
