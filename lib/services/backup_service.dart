import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/services/public_backup.dart';
import 'package:money_traker/services/sms_feature_store.dart';
import 'package:money_traker/services/sync_service.dart';
import 'package:money_traker/store/money_storage.dart';

/// Full JSON backup of money data, bank SMS data, and the settings that drive them.
///
/// The check runs when the app is opened. If today's copy is already saved, nothing else happens.
/// Nothing is scheduled in the background.
///
/// On Android the same open also puts the file in Downloads/MoneyTracker and deletes
/// copies older than [phoneKeepDays] days. That folder stays if the app is removed.
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static const keepDays = 30;
  static const phoneKeepDays = 10;
  static const phoneFolder = 'Downloads/MoneyTracker';
  static const _lastBackupKey = 'last_auto_backup_at';
  static const _lastPhoneBackupKey = 'last_phone_backup_at';
  static const restoreDecidedKey = 'public_backup_restore_decided_v2';
  static const _latestName = 'latest.json';
  static const _phoneChannel = MethodChannel('com.example.money_traker/backup');

  Future<File?>? _active;
  bool _again = false;

  Future<Map<String, dynamic>> buildBackup() async {
    final money = await MoneyStorage().exportBackupJson();
    final sms = await DatabaseHelper.instance.exportSmsTables();
    final preferences = await _exportPreferences();
    return {
      ...money,
      'schemaVersion': MoneyStorage.backupSchemaVersion,
      'sms': sms,
      'preferences': preferences,
    };
  }

  Future<String> buildBackupJson() async {
    final map = await buildBackup();
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  Future<void> importDecoded(Map<String, dynamic> json) async {
    await MoneyStorage().importBackupJson(json, replace: true);
    final sms = json['sms'];
    if (sms is Map) {
      await DatabaseHelper.instance.importSmsTables(Map<String, dynamic>.from(sms));
    }
    final preferences = json['preferences'];
    if (preferences is Map) {
      await _importPreferences(Map<String, dynamic>.from(preferences));
    }
    await writeAutomaticBackup(force: true);
  }

  Future<DateTime?> lastAutomaticBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_lastBackupKey);
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<File?> latestBackupFile() async {
    final dir = await _backupDirectory(create: false);
    final file = File(p.join(dir.path, _latestName));
    if (await file.exists()) return file;
    return null;
  }

  /// Saves `latest.json` and today's dated copy.
  /// Skips the write when a backup was already saved today, unless [force] is set.
  Future<File?> writeAutomaticBackup({bool force = false}) async {
    if (!force) {
      final last = await lastAutomaticBackupAt();
      final now = DateTime.now();
      final alreadyToday = last != null && last.year == now.year && last.month == now.month && last.day == now.day;
      if (alreadyToday && await _phoneBackupDoneToday()) {
        return latestBackupFile();
      }
      if (alreadyToday && await _publishExistingDaily()) {
        return latestBackupFile();
      }
    }
    if (_active != null) {
      _again = true;
      return _active!;
    }
    final run = _run();
    _active = run;
    return run.whenComplete(() => _active = null);
  }

  Future<File?> _run() async {
    try {
      File? written;
      do {
        _again = false;
        written = await _writeOnce();
      } while (_again);
      return written;
    } catch (e, stack) {
      debugPrint('Automatic backup failed: $e\n$stack');
      return null;
    }
  }

  Future<File> _writeOnce() async {
    final jsonStr = await buildBackupJson();
    final dir = await _backupDirectory(create: true);
    final latest = File(p.join(dir.path, _latestName));
    await latest.writeAsString(jsonStr);

    final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final daily = File(p.join(dir.path, 'money_traker_$stamp.json'));
    await daily.writeAsString(jsonStr);
    await _prune(dir);
    await _publishPhoneCopy(daily);
    await _markBackupDone();
    return latest;
  }

  Future<bool> _phoneBackupDoneToday() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_lastPhoneBackupKey);
    if (millis == null) return false;
    final last = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    return last.year == now.year && last.month == now.month && last.day == now.day;
  }

  Future<bool> _publishExistingDaily() async {
    final dir = await _backupDirectory(create: false);
    final stamp = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final daily = File(p.join(dir.path, 'money_traker_$stamp.json'));
    if (!await daily.exists()) return false;
    try {
      await _publishPhoneCopy(daily);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastPhoneBackupKey, DateTime.now().millisecondsSinceEpoch);
      return true;
    } catch (e, stack) {
      debugPrint('Phone folder backup failed: $e\n$stack');
      return false;
    }
  }

  Future<void> _markBackupDone() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt(_lastBackupKey, now);
    if (!kIsWeb && Platform.isAndroid) {
      await prefs.setInt(_lastPhoneBackupKey, now);
    }
  }

  /// Copies today's file into the public phone folder. On Android a failure
  /// skips the "already backed up today" mark so the next open tries again.
  Future<void> _publishPhoneCopy(File daily) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await _phoneChannel.invokeMethod<String>('savePublicBackup', {
      'path': daily.path,
      'name': p.basename(daily.path),
      'keepDays': phoneKeepDays,
    });
  }

  Future<Directory> _backupDirectory({required bool create}) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'backups'));
    if (create && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _prune(Directory dir) async {
    final cutoff = DateTime.now().subtract(const Duration(days: keepDays));
    final cutoffDay = DateTime(cutoff.year, cutoff.month, cutoff.day);
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!name.startsWith('money_traker_') || !name.endsWith('.json')) continue;
      final datePart = name.substring('money_traker_'.length, name.length - '.json'.length);
      final date = DateTime.tryParse(datePart);
      if (date != null && date.isBefore(cutoffDay)) {
        await entity.delete();
      }
    }
  }

  Future<Map<String, dynamic>> _exportPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final rawConfig = prefs.getString(SmsFeatureStore.prefsKey);
    Object? config;
    if (rawConfig != null && rawConfig.isNotEmpty) {
      final decoded = jsonDecode(rawConfig);
      if (decoded is Map) config = decoded;
    }
    return {
      SmsFeatureStore.prefsKey: config,
      SyncService.lastSyncPrefsKey: prefs.getInt(SyncService.lastSyncPrefsKey),
    };
  }

  Future<void> _importPreferences(Map<String, dynamic> preferences) async {
    final prefs = await SharedPreferences.getInstance();
    final config = preferences[SmsFeatureStore.prefsKey];
    if (config == null) {
      await prefs.remove(SmsFeatureStore.prefsKey);
    } else {
      await prefs.setString(SmsFeatureStore.prefsKey, jsonEncode(config));
    }

    final lastSync = preferences[SyncService.lastSyncPrefsKey];
    if (lastSync is num) {
      await prefs.setInt(SyncService.lastSyncPrefsKey, lastSync.toInt());
    } else {
      await prefs.remove(SyncService.lastSyncPrefsKey);
    }
  }

  bool get supportsPublicRestore {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  Future<bool> isRestorePromptDecided() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(restoreDecidedKey) ?? false;
  }

  Future<void> markRestorePromptDecided() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(restoreDecidedKey, true);
  }

  /// Renames Downloads/MoneyTracker backups to `money_traker_<date>_old_<today>.json`.
  /// Those copies are deleted after 3 days.
  Future<void> retirePublicBackups() async {
    if (!supportsPublicRestore) return;
    try {
      await _phoneChannel.invokeMethod<void>('retirePublicBackups');
    } catch (e, stack) {
      debugPrint('Retire public backups failed: $e\n$stack');
    }
  }

  /// `granted` when the folder can be read now, `settings` when the system
  /// settings screen was opened, `denied` when the user refused.
  Future<String> requestPublicBackupAccess() async {
    if (!supportsPublicRestore) return 'granted';
    final status = await _phoneChannel.invokeMethod<String>('requestPublicBackupAccess');
    return status ?? 'denied';
  }

  Future<PublicBackupScan> scanPublicBackups() async {
    if (!supportsPublicRestore) {
      return const PublicBackupScan(readable: true, files: []);
    }
    final raw = await _phoneChannel.invokeMethod<Map>('scanPublicBackups');
    if (raw == null) {
      return const PublicBackupScan(readable: false, files: []);
    }
    final files = <PublicBackupEntry>[];
    final listed = raw['files'];
    if (listed is List) {
      for (final item in listed) {
        if (item is! Map) continue;
        final name = item['name'];
        if (name is! String || !backupFileName.hasMatch(name)) continue;
        final modified = item['modified'];
        files.add(
          PublicBackupEntry(
            name: name,
            modifiedMillis: modified is num ? modified.toInt() : 0,
          ),
        );
      }
    }
    return PublicBackupScan(readable: raw['readable'] == true, files: files);
  }

  Future<RestorableBackup?> newestRestorableBackup(List<PublicBackupEntry> files) async {
    final sorted = [...files]..sort(comparePublicBackupEntries);
    for (final file in sorted) {
      try {
        final path = await _phoneChannel.invokeMethod<String>('stagePublicBackup', {
          'name': file.name,
        });
        if (path == null || path.isEmpty) continue;
        final staged = File(path);
        final decoded = json.decode(await staged.readAsString());
        try {
          await staged.delete();
        } catch (_) {}
        if (decoded is! Map) continue;
        final map = Map<String, dynamic>.from(decoded);
        if (!backupJsonHasUserData(map)) continue;
        return RestorableBackup(
          name: file.name,
          dateLabel: backupDateLabel(file.name) ?? file.name,
          json: map,
        );
      } catch (e, stack) {
        debugPrint('Skip public backup ${file.name}: $e\n$stack');
      }
    }
    return null;
  }
}
