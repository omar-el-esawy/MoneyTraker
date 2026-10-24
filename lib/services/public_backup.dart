class PublicBackupEntry {
  final String name;
  final int modifiedMillis;

  const PublicBackupEntry({required this.name, required this.modifiedMillis});
}

class PublicBackupScan {
  final bool readable;
  final List<PublicBackupEntry> files;

  const PublicBackupScan({required this.readable, required this.files});
}

class RestorableBackup {
  final String name;
  final String dateLabel;
  final Map<String, dynamic> json;

  const RestorableBackup({
    required this.name,
    required this.dateLabel,
    required this.json,
  });
}

final RegExp backupFileName = RegExp(
  r'^money_traker_(\d{4}-\d{2}-\d{2})(?: \(\d+\))?\.json$',
);

const backupDataKeys = <String>[
  'missions',
  'money_sources',
  'total_money_days',
  'tags',
  'total_money_day_delta_entries',
  'goals',
  'money_source_changes',
];

String? backupDateLabel(String name) {
  return backupFileName.firstMatch(name)?.group(1);
}

int comparePublicBackupEntries(PublicBackupEntry a, PublicBackupEntry b) {
  final byDate = (backupDateLabel(b.name) ?? '').compareTo(
    backupDateLabel(a.name) ?? '',
  );
  if (byDate != 0) return byDate;
  return b.modifiedMillis.compareTo(a.modifiedMillis);
}

bool backupJsonHasUserData(Map<String, dynamic> json) {
  for (final key in backupDataKeys) {
    final value = json[key];
    if (value is List && value.isNotEmpty) return true;
  }
  final sms = json['sms'];
  if (sms is Map) {
    for (final value in sms.values) {
      if (value is List && value.isNotEmpty) return true;
    }
  }
  return false;
}
