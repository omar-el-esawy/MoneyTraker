import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/services/public_backup.dart';

void main() {
  test('empty backup files are not user data', () {
    expect(backupJsonHasUserData({}), isFalse);
    expect(backupJsonHasUserData({'money_sources': []}), isFalse);
    expect(
      backupJsonHasUserData({
        'sms': {'transactions': []},
      }),
      isFalse,
    );
  });

  test('sources or bank messages count as user data', () {
    expect(
      backupJsonHasUserData({
        'money_sources': [
          {'name': 'cash'},
        ],
      }),
      isTrue,
    );
    expect(
      backupJsonHasUserData({
        'sms': {
          'transactions': [
            {'amount': 10},
          ],
        },
      }),
      isTrue,
    );
  });

  test('newest dated backup with a tie broken by modified time comes first', () {
    final files = [
      const PublicBackupEntry(
        name: 'money_traker_2026-10-20.json',
        modifiedMillis: 1,
      ),
      const PublicBackupEntry(
        name: 'money_traker_2026-10-22.json',
        modifiedMillis: 5,
      ),
      const PublicBackupEntry(
        name: 'money_traker_2026-10-22 (1).json',
        modifiedMillis: 9,
      ),
    ]..sort(comparePublicBackupEntries);

    expect(files.first.name, 'money_traker_2026-10-22 (1).json');
    expect(backupDateLabel(files.first.name), '2026-10-22');
    expect(files.last.name, 'money_traker_2026-10-20.json');
  });

  test('retired copies are not offered as the current backup', () {
    expect(
      backupFileName.hasMatch('money_traker_2026-10-22_old_2026-10-26.json'),
      isFalse,
    );
    expect(
      backupFileName.hasMatch('money_traker_2026-10-22_old_2026-10-26 (1).json'),
      isFalse,
    );
    expect(backupFileName.hasMatch('money_traker_2026-10-22.json'), isTrue);
  });
}
