import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/pages/app_update_prompt.dart';
import 'package:money_traker/pages/sms/bank_messages_page.dart';
import 'package:money_traker/services/app_update.dart';
import 'package:money_traker/services/app_update_logic.dart';
import 'package:money_traker/services/backup_service.dart';
import 'package:money_traker/services/inbox_store.dart';
import 'package:money_traker/tour/app_tour.dart';

class SettingsPage extends StatefulWidget {
  final Future<void> Function()? onDataImported;
  final VoidCallback? onReplayTour;

  const SettingsPage({super.key, this.onDataImported, this.onReplayTour});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  String _backupStatus = 'No backup yet. Tap to create and share one.';
  String _installedVersion = '';

  @override
  void initState() {
    super.initState();
    _loadAutoBackupLabel();
    _loadInstalledVersion();
  }

  Future<void> _loadInstalledVersion() async {
    final info = await PackageInfo.fromPlatform();
    final build = int.tryParse(info.buildNumber) ?? 0;
    if (!mounted) return;
    setState(() => _installedVersion = releaseLabel(info.version, build));
  }

  Future<void> _loadAutoBackupLabel() async {
    final at = await BackupService.instance.lastAutomaticBackupAt();
    if (!mounted) return;
    setState(() {
      _backupStatus = at == null
          ? 'No backup yet. Tap to create and share one.'
          : 'Last saved ${DateFormat('d MMM, HH:mm').format(at)}. Tap to share it.';
    });
  }

  Future<void> _checkAppVersion() async {
    setState(() => _busy = true);
    try {
      final result = await AppUpdateService.checkLatest(refresh: true);
      if (!mounted) return;
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not check the latest version.')),
        );
        return;
      }
      await InboxStore.instance.syncUpdateOffer(result.offer);
      if (!mounted) return;
      final offer = result.offer;
      if (offer != null) {
        await showOptionalUpdateDialog(context, offer);
        return;
      }
      final arabic = Localizations.localeOf(context).languageCode == 'ar';
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: Text(
              arabic
                  ? 'آخر إصدار هو ${result.latestLabel}.'
                  : 'The latest is ${result.latestLabel}.',
            ),
            content: Text(
              result.newer
                  ? (arabic
                        ? 'في إصدار أحدث. التحديث من تطبيق أندرويد.'
                        : 'A newer version is available. Update it from the Android app.')
                  : (arabic
                        ? 'النسخة اللي عندك هي الأحدث (${result.currentLabel}).'
                        : 'You already have this version (${result.currentLabel}).'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(arabic ? 'حسناً' : 'OK'),
              ),
            ],
          );
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      final jsonStr = await BackupService.instance.buildBackupJson();

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/money_traker_backup.json');
      await file.writeAsString(jsonStr);
      await BackupService.instance.writeAutomaticBackup(force: true);
      await _loadAutoBackupLabel();

      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/json'),
      ], text: 'Money Tracker backup');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareLatestAutomatic() async {
    setState(() => _busy = true);
    try {
      final existing = await BackupService.instance.latestBackupFile();
      final file =
          existing ??
          await BackupService.instance.writeAutomaticBackup(force: true);
      if (file == null) {
        throw Exception('Could not create a backup file.');
      }
      await _loadAutoBackupLabel();
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'application/json'),
      ], text: 'Money Tracker backup');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not share backup: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import backup'),
        content: const Text(
          'Import replaces the data stored in the backup: money sources, history, tags, goals, missions, bank messages, reading rules, and bank settings.\n\nOlder backups that only contain money data leave bank messages on this phone unchanged.\n\nDo you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;
      final path = picked.path;
      if (path == null || path.isEmpty) {
        throw Exception('Could not access the selected file path.');
      }

      final content = await File(path).readAsString();
      final decoded = json.decode(content);
      if (decoded is! Map) {
        throw Exception('Invalid backup format.');
      }

      await BackupService.instance.importDecoded(
        Map<String, dynamic>.from(decoded),
      );
      await _loadAutoBackupLabel();
      await widget.onDataImported?.call();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import completed successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tour = AppTourScope.maybeOf(context);
    final version = _installedVersion.isEmpty
        ? 'Version'
        : 'Version $_installedVersion';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: AppConstants.primaryColor,
                  backgroundColor: AppConstants.primarySurface,
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: AbsorbPointer(
              absorbing: _busy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: [
                  const _SectionLabel('Guide'),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        key: tour?.replay,
                        icon: Icons.explore_outlined,
                        title: 'App tour',
                        arabic: 'الجولة التعريفية',
                        subtitle: 'A short walk through each section.',
                        onTap: widget.onReplayTour,
                      ),
                    ],
                  ),
                  const _SectionLabel('App'),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        icon: Icons.system_update_alt,
                        title: 'Check for updates',
                        arabic: 'التحقق من التحديث',
                        subtitle: 'Compare this phone with the latest version.',
                        onTap: _checkAppVersion,
                      ),
                    ],
                  ),
                  const _SectionLabel('Bank'),
                  _SettingsCard(
                    children: [
                      _SettingsTile(
                        key: tour?.bankMessages,
                        icon: Icons.sms_outlined,
                        title: 'Bank messages',
                        arabic: 'رسائل البنك',
                        subtitle:
                            'Copy bank SMS and teach the app how to read them.',
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const BankMessagesPage(),
                            ),
                          );
                          await widget.onDataImported?.call();
                        },
                      ),
                    ],
                  ),
                  const _SectionLabel('Backup'),
                  KeyedSubtree(
                    key: tour?.backup,
                    child: _SettingsCard(
                      footer:
                          'A backup is saved when you open the app. ${BackupService.phoneFolder} keeps the last ${BackupService.phoneKeepDays} days.',
                      children: [
                        _SettingsTile(
                          icon: Icons.upload_file,
                          title: 'Export backup',
                          subtitle:
                              'Share a file with your money, history, and messages.',
                          onTap: _exportBackup,
                        ),
                        _SettingsTile(
                          icon: Icons.download,
                          title: 'Import backup',
                          subtitle:
                              'Replace this phone’s data with a backup file.',
                          onTap: _importBackup,
                        ),
                        _SettingsTile(
                          icon: Icons.backup_outlined,
                          title: 'Automatic backup',
                          subtitle: _backupStatus,
                          onTap: _shareLatestAutomatic,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Text(
              version,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppConstants.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: AppConstants.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final String? footer;

  const _SettingsCard({required this.children, this.footer});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          const Divider(
            height: 1,
            indent: 68,
            endIndent: 12,
            color: AppConstants.dividerColor,
          ),
        );
      }
      rows.add(children[i]);
    }
    if (footer != null) {
      rows.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: Text(
            footer!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppConstants.textTertiary),
          ),
        ),
      );
    }
    return Card(child: Column(children: rows));
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? arabic;
  final String subtitle;
  final VoidCallback? onTap;

  const _SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.arabic,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppConstants.primarySurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppConstants.primaryColor, size: 20),
      ),
      title: Text(title),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text.rich(
          TextSpan(
            children: [
              if (arabic != null)
                TextSpan(
                  text: '$arabic\n',
                  style: const TextStyle(
                    color: AppConstants.textTertiary,
                    height: 1.3,
                  ),
                ),
              TextSpan(text: subtitle),
            ],
          ),
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: AppConstants.textTertiary,
      ),
      onTap: onTap,
    );
  }
}
