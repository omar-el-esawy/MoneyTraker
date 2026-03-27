import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:money_traker/store/money_storage.dart';

class SettingsPage extends StatefulWidget {
  final Future<void> Function()? onDataImported;

  const SettingsPage({super.key, this.onDataImported});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;

  Future<void> _exportBackup() async {
    setState(() => _busy = true);
    try {
      final storage = MoneyStorage();
      final jsonMap = await storage.exportBackupJson();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(jsonMap);

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/money_traker_backup.json');
      await file.writeAsString(jsonStr);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        text: 'Money Tracker backup',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
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
          'Import will replace your current local data (money sources, history, missions).\n\nDo you want to continue?',
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
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid backup format.');
      }

      await MoneyStorage().importBackupJson(decoded, replace: true);
      await widget.onDataImported?.call();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import completed successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Export backup'),
              subtitle: const Text('Create a JSON backup you can share/save.'),
              onTap: _exportBackup,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Import backup'),
              subtitle: const Text('Restore from a previously exported JSON backup.'),
              onTap: _importBackup,
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
