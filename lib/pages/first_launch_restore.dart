import 'package:flutter/material.dart';
import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/services/backup_service.dart';
import 'package:money_traker/services/public_backup.dart';
import 'package:money_traker/store/money_storage.dart';
import 'package:sqflite/sqflite.dart';

/// Returns true when it is safe to write today's automatic backup.
/// False leaves the public folder untouched so the next open can ask again.
Future<bool> settleFirstLaunchRestore(
  BuildContext context, {
  required Future<void> Function() waitForSettingsReturn,
}) async {
  final backup = BackupService.instance;
  if (await backup.isRestorePromptDecided()) return true;
  if (!context.mounted) return false;

  if (await _installHasUserData()) {
    await backup.markRestorePromptDecided();
    return true;
  }
  if (!backup.supportsPublicRestore) {
    await backup.markRestorePromptDecided();
    return true;
  }

  PublicBackupScan scan;
  try {
    scan = await backup.scanPublicBackups();
  } catch (e, stack) {
    debugPrint('Public backup scan failed: $e\n$stack');
    return false;
  }
  if (!context.mounted) return false;

  final found = await backup.newestRestorableBackup(scan.files);
  if (!context.mounted) return false;
  if (found != null) {
    return _askAndMaybeRestore(context, found);
  }
  if (scan.readable) {
    await backup.markRestorePromptDecided();
    return true;
  }

  final search = await _askToLook(context);
  if (!context.mounted) return false;
  if (search != true) {
    await backup.retirePublicBackups();
    await backup.markRestorePromptDecided();
    return true;
  }

  final resumed = waitForSettingsReturn();
  String status;
  try {
    status = await backup.requestPublicBackupAccess();
  } catch (e, stack) {
    debugPrint('Backup access request failed: $e\n$stack');
    return false;
  }
  if (status == 'settings') {
    await resumed;
  }
  if (!context.mounted) return false;
  if (status == 'denied') {
    _snack(context, 'متعذر قراءة مجلد النسخ. تقدر تختار أبدأ من الأول، أو تسمح بعدين.');
    return false;
  }

  try {
    scan = await backup.scanPublicBackups();
  } catch (e, stack) {
    debugPrint('Public backup scan failed: $e\n$stack');
    return false;
  }
  if (!context.mounted) return false;
  final foundAfter = await backup.newestRestorableBackup(scan.files);
  if (!context.mounted) return false;
  if (foundAfter != null) {
    return _askAndMaybeRestore(context, foundAfter);
  }
  if (!scan.readable) {
    _snack(context, 'لسه مش قادرين نقرأ Downloads/MoneyTracker.');
    return false;
  }
  await backup.markRestorePromptDecided();
  if (context.mounted) {
    _snack(context, 'مفيش بيانات في مجلد النسخ. هنبدأ من الأول.');
  }
  return true;
}

Future<bool> _installHasUserData() async {
  final storage = MoneyStorage();
  if ((await storage.getMoneySources()).isNotEmpty) return true;
  if ((await storage.getGoals()).isNotEmpty) return true;
  if ((await storage.getMissions()).isNotEmpty) return true;
  if ((await storage.getTags()).isNotEmpty) return true;
  final days = await storage.getTotalMoneyDays();
  if (days.length > 1) return true;
  if (days.any((day) => day.totalAmount.abs() > 0.0000001)) return true;
  try {
    final db = await DatabaseHelper.instance.database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM transactions'),
    );
    if ((count ?? 0) > 0) return true;
  } catch (e, stack) {
    debugPrint('SMS data check failed: $e\n$stack');
  }
  return false;
}

Future<bool> _askAndMaybeRestore(BuildContext context, RestorableBackup backup) async {
  final restore = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _restoreDialog(ctx, backup.dateLabel),
  );
  if (!context.mounted) return false;
  if (restore != true) {
    await BackupService.instance.retirePublicBackups();
    await BackupService.instance.markRestorePromptDecided();
    return true;
  }
  try {
    await BackupService.instance.importDecoded(backup.json);
    await BackupService.instance.markRestorePromptDecided();
    if (context.mounted) {
      _snack(context, 'تم استرجاع البيانات.');
    }
    return true;
  } catch (e, stack) {
    debugPrint('Restore failed: $e\n$stack');
    if (!context.mounted) return false;
    final fresh = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder:
          (ctx) => _choiceDialog(
            ctx,
            title: 'الاسترجاع فشل',
            body: 'الملف موجود بس متعذر نرجّعه.\n$e',
            confirm: 'حاول تاني بعدين',
            cancel: 'أبدأ من الأول',
          ),
    );
    if (fresh == false) {
      await BackupService.instance.retirePublicBackups();
      await BackupService.instance.markRestorePromptDecided();
      return true;
    }
    return false;
  }
}

Future<bool?> _askToLook(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder:
        (ctx) => _choiceDialog(
          ctx,
          title: 'نسخة احتياطية',
          body:
              'أول مرة تفتح التطبيق. عشان نشوف لو فيه نسخة قديمة في Downloads/MoneyTracker محتاجين إذن قراءة الملفات. لو لقينا بيانات هسألك تسترجعها ولا تبدأ من الأول.',
          confirm: 'السماح والبحث',
          cancel: 'أبدأ من الأول',
        ),
  );
}

Widget _restoreDialog(BuildContext context, String dateLabel) {
  return _choiceDialog(
    context,
    title: 'لقيت نسخة احتياطية',
    body:
        'فيه بيانات محفوظة في Downloads/MoneyTracker بتاريخ $dateLabel. تسترجع البيانات ولا تبدأ من الأول؟',
    confirm: 'استرجاع البيانات',
    cancel: 'أبدأ من الأول',
  );
}

Widget _choiceDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  required String cancel,
}) {
  return Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancel),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirm),
        ),
      ],
    ),
  );
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
