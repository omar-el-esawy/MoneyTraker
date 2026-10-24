import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:money_traker/pages/sms/bank_messages_page.dart';
import 'package:money_traker/services/backup_service.dart';
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
  String _autoBackupLabel =
      'Checked when you open the app. ${BackupService.phoneFolder} keeps the last ${BackupService.phoneKeepDays} days.';

  @override
  void initState() {
    super.initState();
    _loadAutoBackupLabel();
  }

  Future<void> _loadAutoBackupLabel() async {
    final at = await BackupService.instance.lastAutomaticBackupAt();
    if (!mounted) return;
    setState(() {
      _autoBackupLabel =
          at == null
              ? 'Checked when you open the app. No backup yet. ${BackupService.phoneFolder} keeps the last ${BackupService.phoneKeepDays} days.'
              : 'Last saved ${DateFormat('yyyy-MM-dd HH:mm').format(at)}. Checked again the next time you open the app. ${BackupService.phoneFolder} keeps the last ${BackupService.phoneKeepDays} days.';
    });
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
      builder:
          (ctx) => AlertDialog(
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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              key: tour?.replay,
              leading: const Icon(Icons.explore_outlined),
              title: const Text('App tour / الجولة التعريفية'),
              subtitle: const Text(
                'Walk through what each section does. شرح سريع لكل خانة.',
              ),
              onTap: widget.onReplayTour,
            ),
            const Divider(),
            ListTile(
              key: tour?.bankMessages,
              leading: const Icon(Icons.sms_outlined),
              title: const Text('Bank messages / رسائل البنك'),
              subtitle: const Text(
                'Set a start date, copy bank SMS, and mark numbers to build reading rules.',
              ),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BankMessagesPage()),
                );
                await widget.onDataImported?.call();
              },
            ),
            const Divider(),
            KeyedSubtree(
              key: tour?.backup,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.upload_file),
                    title: const Text('Export backup'),
                    subtitle: const Text(
                      'Share a full JSON backup: money, history, goals, and bank messages.',
                    ),
                    onTap: _exportBackup,
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: const Text('Import backup'),
                    subtitle: const Text(
                      'Restore from a previously exported JSON backup.',
                    ),
                    onTap: _importBackup,
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: const Text('Automatic backup'),
                    subtitle: Text(_autoBackupLabel),
                    onTap: _shareLatestAutomatic,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_busy)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
