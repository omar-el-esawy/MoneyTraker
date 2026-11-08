import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/model/money_source.dart';
import 'package:money_traker/pages/sms_templates/sms_template_operations_page.dart';
import 'package:money_traker/pages/sms_templates/sms_template_wizard_page.dart';
import 'package:money_traker/pages/sms_templates/sms_templates_page.dart';
import 'package:money_traker/services/sms_feature_store.dart';
import 'package:money_traker/services/sms_template_sync_service.dart';
import 'package:money_traker/sms/sms_hash.dart';
import 'package:money_traker/sms/sms_models.dart';
import 'package:money_traker/sms/template_engine/sms_template_mobile_store.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';
import 'package:money_traker/store/money_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late String smsDatabasePath;

  setUpAll(() async {
    final databasesPath = await getDatabasesPath();
    smsDatabasePath = join(databasesPath, 'money_traker_sms.db');
    final moneyDatabasePath = join(databasesPath, 'money_traker.db');
    await deleteDatabase(smsDatabasePath);
    await deleteDatabase(moneyDatabasePath);

    final oldDb = await openDatabase(
      smsDatabasePath,
      version: 9,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE sms_copies (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            sms_id TEXT,
            sender TEXT,
            body TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE transactions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            bank TEXT NOT NULL,
            amount REAL NOT NULL,
            type TEXT NOT NULL,
            date INTEGER NOT NULL,
            raw_sms TEXT NOT NULL,
            sms_id TEXT,
            balance REAL,
            account_hint TEXT,
            sms_hash TEXT,
            rule_id TEXT,
            rule_version INTEGER,
            category_tag_id INTEGER,
            category_amount REAL,
            category_allocations TEXT
          )
        ''');
        await db.insert('sms_copies', {
          'sms_id': 'old-1',
          'sender': 'OLDBANK',
          'body': 'old data must survive',
        });
      },
    );
    await oldDb.close();
  });

  test(
    'v9 migration preserves old SMS data and adds isolated V2 tables',
    () async {
      final db = await DatabaseHelper.instance.database;
      final oldRows = await db.query('sms_copies');
      expect(oldRows.single['body'], 'old data must survive');

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final names = tables.map((row) => row['name']).toSet();
      expect(names, contains('sms_template_banks_v2'));
      expect(names, contains('sms_templates_v2'));
      expect(names, contains('sms_template_messages_v2'));
      expect(names, contains('sms_template_applications_v2'));
    },
  );

  test('old active Bank messages blocks enabling SMS Templates', () async {
    final oldConfig = SmsFeatureConfig(
      started: true,
      startDate: DateTime(2026),
      languageCode: 'en',
      banks: const [
        BankConfig(
          id: 'old',
          nameEn: 'Old',
          nameAr: 'قديم',
          senders: ['OLD'],
          enabled: true,
        ),
      ],
    );
    SharedPreferences.setMockInitialValues({
      SmsFeatureStore.prefsKey: jsonEncode(oldConfig.toJson()),
      SmsTemplateMobileStore.enabledKey: false,
    });

    final result = await SmsTemplateSyncService.instance.setEnabled(true);

    expect(result, SmsTemplateEnableResult.oldSystemActive);
    expect(await SmsTemplateMobileStore.instance.isEnabled(), isFalse);
  });

  test('disabled SMS Templates does not read or apply anything', () async {
    SharedPreferences.setMockInitialValues({
      SmsTemplateMobileStore.enabledKey: false,
    });

    final result = await SmsTemplateSyncService.instance.sync();

    expect(result.disabled, isTrue);
    expect(result.copied, 0);
    expect(result.applied, 0);
  });

  test('template JSON round-trip preserves every marked field', () {
    const template = SmsTemplate(
      id: 'purchase-v2',
      bankId: 'bank-v2',
      sampleText: 'Debited 150 at SHOP ref A1',
      type: SmsTemplateType.debit,
      amount: SmsPlaceholder(
        kind: SmsPlaceholderKind.amount,
        range: SmsTextRange(start: 8, end: 11),
      ),
      directionRanges: [SmsTextRange(start: 0, end: 7)],
      placeholders: [
        SmsPlaceholder(
          kind: SmsPlaceholderKind.merchant,
          range: SmsTextRange(start: 15, end: 19),
        ),
        SmsPlaceholder(
          kind: SmsPlaceholderKind.reference,
          range: SmsTextRange(start: 24, end: 26),
        ),
      ],
    );

    final restored = SmsTemplate.fromJson(template.toJson());

    expect(restored.id, template.id);
    expect(restored.type, SmsTemplateType.debit);
    expect(restored.amount.range.start, 8);
    expect(restored.directionRanges.single.end, 7);
    expect(restored.placeholders.map((item) => item.kind), [
      SmsPlaceholderKind.merchant,
      SmsPlaceholderKind.reference,
    ]);
  });

  test('wizard refuses a draft without both amount and direction', () {
    const empty = SmsTemplateDraft(type: SmsTemplateType.debit);
    const amountOnly = SmsTemplateDraft(
      type: SmsTemplateType.debit,
      amountRange: SmsTextRange(start: 4, end: 7),
    );
    const complete = SmsTemplateDraft(
      type: SmsTemplateType.debit,
      amountRange: SmsTextRange(start: 4, end: 7),
      directionRanges: [SmsTextRange(start: 0, end: 3)],
    );

    expect(empty.canSave, isFalse);
    expect(amountOnly.canSave, isFalse);
    expect(complete.canSave, isTrue);
  });

  test('Undo applies the inverse delta once and is idempotent', () async {
    SharedPreferences.setMockInitialValues({});
    final money = MoneyStorage();
    final moneyDb = await money.database;
    await moneyDb.delete('money_source_changes');
    await moneyDb.delete('money_sources');
    final sourceId = await money.addMoneySource(
      MoneySource(name: 'Main card', amount: 900),
    );
    final smsDb = await DatabaseHelper.instance.database;
    await smsDb.delete('sms_template_applications_v2');

    final id = await SmsTemplateMobileStore.instance.insertApplication(
      SmsTemplateApplication(
        smsHash: 'undo-once',
        bankId: 'bank',
        bankName: 'Bank',
        templateId: 'template',
        sourceId: sourceId,
        sourceName: 'Main card',
        amount: 100,
        delta: -100,
        beforeAmount: 1000,
        afterAmount: 900,
        occurredAt: DateTime(2026, 11, 3),
        rawSms: 'Debited 100',
        createdAt: DateTime.now(),
      ),
    );
    final application =
        (await SmsTemplateMobileStore.instance.getApplications()).firstWhere(
          (item) => item.id == id,
        );

    final first = await SmsTemplateSyncService.instance.undo(application);
    final second = await SmsTemplateSyncService.instance.undo(application);
    final source = (await money.getMoneySources()).single;

    expect(first, isTrue);
    expect(second, isFalse);
    expect(source.amount, 1000);
    expect(
      (await SmsTemplateMobileStore.instance.getApplications()).single.undone,
      isTrue,
    );
  });

  test(
    'reprocessing filters exact sender, dedupes, rejects malformed, and applies once',
    () async {
      SharedPreferences.setMockInitialValues({
        SmsTemplateMobileStore.enabledKey: true,
      });
      final money = MoneyStorage();
      final moneyDb = await money.database;
      await moneyDb.delete('money_source_changes');
      await moneyDb.delete('money_sources');
      final sourceId = await money.addMoneySource(
        MoneySource(name: 'Template card', amount: 1000),
      );
      final smsDb = await DatabaseHelper.instance.database;
      for (final table in [
        'sms_template_applications_v2',
        'sms_template_messages_v2',
        'sms_templates_v2',
        'sms_template_banks_v2',
        'transactions',
      ]) {
        await smsDb.delete(table);
      }
      final bank = SmsTemplateBank(
        id: 'runtime-bank',
        name: 'Runtime Bank',
        senders: const ['BANK'],
        sourceId: sourceId,
        createdAt: DateTime.now(),
      );
      await SmsTemplateMobileStore.instance.saveBank(bank);
      const sample = 'Debited 100 EGP successfully';
      await SmsTemplateMobileStore.instance.saveTemplate(
        const SmsTemplate(
          id: 'debit-template',
          bankId: 'runtime-bank',
          sampleText: sample,
          type: SmsTemplateType.debit,
          amount: SmsPlaceholder(
            kind: SmsPlaceholderKind.amount,
            range: SmsTextRange(start: 8, end: 11),
          ),
          directionRanges: [SmsTextRange(start: 0, end: 7)],
        ),
      );
      final base = DateTime(2026, 11, 3, 10);
      final inputs = [
        ('sms-1', 'BANK', sample, base),
        ('sms-2', 'BANK', sample, base.add(const Duration(minutes: 1))),
        ('sms-3', 'OTHER', sample, base.add(const Duration(minutes: 5))),
        (
          'sms-4',
          'BANK',
          'Your OTP is 123456',
          base.add(const Duration(minutes: 10)),
        ),
      ];
      for (final input in inputs) {
        await SmsTemplateMobileStore.instance.upsertMessage(
          SmsTemplateStoredMessage(
            hash: SmsHash.of(smsId: input.$1, sender: input.$2, body: input.$3),
            smsId: input.$1,
            sender: input.$2,
            body: input.$3,
            date: input.$4,
            bankId: bank.id,
            status: SmsTemplateMessageStatus.unrecognized,
            copiedAt: DateTime.now(),
          ),
        );
      }

      final first = await SmsTemplateSyncService.instance.reprocessBank(
        bank.id,
      );
      final second = await SmsTemplateSyncService.instance.reprocessBank(
        bank.id,
      );
      final source = (await money.getMoneySources()).single;

      expect(first.parsed, 1);
      expect(first.applied, 1);
      expect(first.duplicates, 1);
      expect(first.unrecognized, 1);
      expect(second.applied, 0);
      expect(source.amount, 900);
      expect(
        (await SmsTemplateMobileStore.instance.getApplications()).length,
        1,
      );
    },
  );

  testWidgets('dashboard exposes the global toggle and bank action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      SmsTemplateMobileStore.enabledKey: false,
    });

    await tester.pumpWidget(const MaterialApp(home: SmsTemplatesPage()));
    await _waitForText(tester, 'SMS Templates');

    expect(find.text('SMS Templates'), findsOneWidget);
    expect(find.text('Reading is off'), findsOneWidget);
    expect(find.text('Add bank'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
  });

  testWidgets('wizard starts with a separate debit or credit question', (
    tester,
  ) async {
    final now = DateTime(2026, 11, 3);
    await tester.pumpWidget(
      MaterialApp(
        home: SmsTemplateWizardPage(
          bank: SmsTemplateBank(
            id: 'wizard-bank',
            name: 'Wizard Bank',
            senders: const ['BANK'],
            createdAt: now,
          ),
          initialMessage: SmsTemplateStoredMessage(
            hash: 'wizard-message',
            smsId: 'wizard-message',
            sender: 'BANK',
            body: 'Debited EGP150 at STAR MARKET',
            date: now,
            bankId: 'wizard-bank',
            status: SmsTemplateMessageStatus.unrecognized,
            copiedAt: now,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('What happened to the money?'), findsOneWidget);
    expect(find.text('Debit'), findsOneWidget);
    expect(find.text('Credit'), findsOneWidget);
  });

  testWidgets('operations screen shows an active Undo action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SmsTemplateOperationsPage()),
    );
    await _waitForText(tester, 'Undo change');

    expect(find.text('Balance changes'), findsOneWidget);
    expect(find.text('Undo change'), findsOneWidget);
    expect(find.textContaining('Template card'), findsOneWidget);
  });
}

Future<void> _waitForText(WidgetTester tester, String text) async {
  for (var i = 0; i < 40 && find.text(text).evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}
