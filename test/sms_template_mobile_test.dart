import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';
import 'package:money_traker/model/money_source.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/model/total_money_day.dart';
import 'package:money_traker/pages/sms_templates/sms_template_operations_page.dart';
import 'package:money_traker/pages/sms_templates/sms_template_wizard_page.dart';
import 'package:money_traker/pages/sms_templates/sms_templates_page.dart';
import 'package:money_traker/services/sms_feature_store.dart';
import 'package:money_traker/services/sms_source_applier.dart';
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

  test('wizard can save once the type and amount are chosen', () {
    const empty = SmsTemplateDraft(type: SmsTemplateType.debit);
    const complete = SmsTemplateDraft(
      type: SmsTemplateType.debit,
      amountRange: SmsTextRange(start: 4, end: 7),
    );

    expect(empty.canSave, isFalse);
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
    'Undo reverses the category amount for the template transaction',
    () async {
      SharedPreferences.setMockInitialValues({});
      final money = MoneyStorage();
      final moneyDb = await money.database;
      await moneyDb.delete('total_money_day_delta_entries');
      await moneyDb.delete('total_money_days');
      await moneyDb.delete('money_source_changes');
      await moneyDb.delete('money_sources');
      await moneyDb.delete('tags');
      final sourceId = await money.addMoneySource(
        MoneySource(name: 'Category card', amount: 900),
      );
      final tag = await money.ensureTag(name: 'Food', type: TagType.expense);
      final day = DateTime(2026, 11, 3);
      await money.addTotalMoneyDay(
        TotalMoneyDay.create(date: day, totalAmount: 900),
      );
      await money.adjustCategorizedAmount(
        date: day,
        tagId: tag.id!,
        delta: 100,
      );
      final smsDb = await DatabaseHelper.instance.database;
      await smsDb.delete('sms_template_applications_v2');
      await smsDb.delete('transactions');
      await DatabaseHelper.instance.upsertTransaction(
        TransactionEntity(
          bank: 'Bank',
          amount: 100,
          type: TransactionType.debit,
          date: DateTime(2026, 11, 3, 10),
          rawSms: 'Debited 100 at SHOP',
          smsHash: 'undo-category',
          ruleId: 'sms-template-v2:template',
          ruleVersion: 1,
          categoryTagId: tag.id,
          categoryAmount: 100,
        ),
      );
      final id = await SmsTemplateMobileStore.instance.insertApplication(
        SmsTemplateApplication(
          smsHash: 'undo-category',
          bankId: 'bank',
          bankName: 'Bank',
          templateId: 'template',
          sourceId: sourceId,
          sourceName: 'Category card',
          amount: 100,
          delta: -100,
          beforeAmount: 1000,
          afterAmount: 900,
          occurredAt: DateTime(2026, 11, 3, 10),
          rawSms: 'Debited 100 at SHOP',
          createdAt: DateTime.now(),
        ),
      );
      final application =
          (await SmsTemplateMobileStore.instance.getApplications()).firstWhere(
            (item) => item.id == id,
          );

      final undone = await SmsTemplateSyncService.instance.undo(application);
      final leftover = await money.amountsForTag(tag.id!);

      expect(undone, isTrue);
      expect(leftover[day] ?? 0, closeTo(0, 0.0001));
      expect(
        await DatabaseHelper.instance.getTransactionByHash('undo-category'),
        isNull,
      );
    },
  );

  test('a sender ID can belong to only one bank', () async {
    final smsDb = await DatabaseHelper.instance.database;
    await smsDb.delete('sms_template_banks_v2');
    final first = SmsTemplateBank(
      id: 'bank-a',
      name: 'Bank A',
      senders: const ['HSBC', 'HSBC-EG'],
      createdAt: DateTime(2026, 11, 10),
    );
    final second = SmsTemplateBank(
      id: 'bank-b',
      name: 'Bank B',
      senders: const ['hsbc'],
      createdAt: DateTime(2026, 11, 10),
    );
    final store = SmsTemplateMobileStore.instance;

    expect(await store.saveBank(first), isNull);
    final conflict = await store.saveBank(second);
    expect(conflict?.sender, 'hsbc');
    expect(conflict?.bank.id, 'bank-a');
    expect(await store.getBanks(), hasLength(1));
    expect(
      smsTemplateSenderConflict([first], const [' HSBC '])?.bank.id,
      'bank-a',
    );
    expect(smsTemplateBanksForSender([first, second], 'hsbc'), hasLength(2));
  });

  test('overlapping senders are not applied to either bank', () async {
    SharedPreferences.setMockInitialValues({
      SmsTemplateMobileStore.enabledKey: true,
    });
    final money = MoneyStorage();
    final moneyDb = await money.database;
    await moneyDb.delete('money_source_changes');
    await moneyDb.delete('money_sources');
    final sourceA = await money.addMoneySource(
      MoneySource(name: 'Card A', amount: 1000),
    );
    final sourceB = await money.addMoneySource(
      MoneySource(name: 'Card B', amount: 1000),
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
    const body = 'Debited 100 EGP successfully';
    Future<void> seedBank({
      required String id,
      required String name,
      required int sourceId,
    }) async {
      await smsDb.insert('sms_template_banks_v2', {
        'id': id,
        'name': name,
        'senders_json': jsonEncode(const ['BANK']),
        'source_id': sourceId,
        'created_at': DateTime(2026, 11, 10).millisecondsSinceEpoch,
      });
      await SmsTemplateMobileStore.instance.saveTemplate(
        SmsTemplate(
          id: '$id-template',
          bankId: id,
          sampleText: body,
          type: SmsTemplateType.debit,
          amount: const SmsPlaceholder(
            kind: SmsPlaceholderKind.amount,
            range: SmsTextRange(start: 8, end: 11),
          ),
          directionRanges: const [SmsTextRange(start: 0, end: 7)],
        ),
      );
    }

    await seedBank(id: 'overlap-a', name: 'Overlap A', sourceId: sourceA);
    await seedBank(id: 'overlap-b', name: 'Overlap B', sourceId: sourceB);
    await SmsTemplateMobileStore.instance.upsertMessage(
      SmsTemplateStoredMessage(
        hash: SmsHash.of(smsId: 'overlap-sms', sender: 'BANK', body: body),
        smsId: 'overlap-sms',
        sender: 'BANK',
        body: body,
        date: DateTime(2026, 11, 10, 12),
        bankId: 'overlap-a',
        status: SmsTemplateMessageStatus.unrecognized,
        copiedAt: DateTime(2026, 11, 10, 12),
      ),
    );

    final result = await SmsTemplateSyncService.instance.reprocessBank(
      'overlap-a',
    );
    final sources = await money.getMoneySources();

    expect(result.applied, 0);
    expect(sources.map((item) => item.amount), everyElement(1000));
  });

  test('deleting a bank removes its category dictionary', () async {
    final smsDb = await DatabaseHelper.instance.database;
    await smsDb.execute('''
      CREATE TABLE IF NOT EXISTS sms_category_rules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        bank_id TEXT NOT NULL,
        word TEXT NOT NULL,
        tag_id INTEGER NOT NULL,
        pattern TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await smsDb.delete('sms_category_rules');
    await smsDb.delete('sms_template_banks_v2');
    await SmsTemplateMobileStore.instance.saveBank(
      SmsTemplateBank(
        id: 'dict-bank',
        name: 'Dict Bank',
        senders: const ['DICT'],
        createdAt: DateTime(2026, 11, 10),
      ),
    );
    await DatabaseHelper.instance.insertSmsCategoryRule(
      SmsCategoryRule(
        bankId: 'dict-bank',
        word: 'SHOP',
        tagId: 1,
        createdAt: DateTime(2026, 11, 10),
      ),
    );

    await SmsTemplateMobileStore.instance.deleteBank('dict-bank');

    expect(
      await DatabaseHelper.instance.getSmsCategoryRules(bankId: 'dict-bank'),
      isEmpty,
    );
  });

  test('sync status reports errors instead of a zero-applied success', () {
    expect(
      const SmsTemplateSyncResult(disabled: true).statusMessage,
      'Turn on SMS Templates before syncing.',
    );
    expect(
      SmsTemplateSyncResult.unsupported.statusMessage,
      'SMS reading is available on Android only.',
    );
    expect(
      const SmsTemplateSyncResult(permissionGranted: false).statusMessage,
      'SMS permission was not granted.',
    );
    expect(
      const SmsTemplateSyncResult(error: 'timeout').statusMessage,
      'Sync failed: timeout',
    );
    expect(
      const SmsTemplateSyncResult(applied: 0, unrecognized: 2).statusMessage,
      '0 applied • 2 need teaching',
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

      expect(first.parsed, 2);
      expect(first.applied, 2);
      expect(first.duplicates, 0);
      expect(first.unrecognized, 1);
      expect(second.applied, 0);
      expect(source.amount, 800);
      expect(
        (await SmsTemplateMobileStore.instance.getApplications()).length,
        2,
      );
    },
  );

  test('a manually ignored message stays out of teaching', () async {
    SharedPreferences.setMockInitialValues({
      SmsTemplateMobileStore.enabledKey: true,
    });
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
    const bankId = 'ignore-bank';
    final at = DateTime(2026, 11, 10, 12);
    await SmsTemplateMobileStore.instance.saveBank(
      SmsTemplateBank(
        id: bankId,
        name: 'Ignore Bank',
        senders: const ['BANK'],
        sourceId: null,
        createdAt: at,
      ),
    );
    await SmsTemplateMobileStore.instance.upsertMessage(
      SmsTemplateStoredMessage(
        hash: SmsHash.of(
          smsId: 'ad-1',
          sender: 'BANK',
          body: 'Your OTP is 123456',
        ),
        smsId: 'ad-1',
        sender: 'BANK',
        body: 'Your OTP is 123456',
        date: at,
        bankId: bankId,
        status: SmsTemplateMessageStatus.ignored,
        copiedAt: at,
      ),
    );

    final result = await SmsTemplateSyncService.instance.reprocessBank(bankId);
    final saved = await SmsTemplateMobileStore.instance.getMessages(
      bankId: bankId,
    );

    expect(result.unrecognized, 0);
    expect(saved.single.status, SmsTemplateMessageStatus.ignored);
  });

  test(
    'identical purchases with different SMS IDs both change money',
    () async {
      SharedPreferences.setMockInitialValues({
        SmsTemplateMobileStore.enabledKey: true,
      });
      final money = MoneyStorage();
      final moneyDb = await money.database;
      await moneyDb.delete('money_source_changes');
      await moneyDb.delete('money_sources');
      final sourceId = await money.addMoneySource(
        MoneySource(name: 'Repeat card', amount: 1000),
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
      const body = 'Debited 100 EGP successfully';
      const bankId = 'repeat-bank';
      final at = DateTime(2026, 11, 10, 12);
      await SmsTemplateMobileStore.instance.saveBank(
        SmsTemplateBank(
          id: bankId,
          name: 'Repeat Bank',
          senders: const ['BANK'],
          sourceId: sourceId,
          createdAt: at,
        ),
      );
      await SmsTemplateMobileStore.instance.saveTemplate(
        const SmsTemplate(
          id: 'repeat-template',
          bankId: bankId,
          sampleText: body,
          type: SmsTemplateType.debit,
          amount: SmsPlaceholder(
            kind: SmsPlaceholderKind.amount,
            range: SmsTextRange(start: 8, end: 11),
          ),
          directionRanges: [SmsTextRange(start: 0, end: 7)],
        ),
      );
      for (final smsId in const ['sms-a', 'sms-b']) {
        await SmsTemplateMobileStore.instance.upsertMessage(
          SmsTemplateStoredMessage(
            hash: SmsHash.of(smsId: smsId, sender: 'BANK', body: body),
            smsId: smsId,
            sender: 'BANK',
            body: body,
            date: at,
            bankId: bankId,
            status: SmsTemplateMessageStatus.unrecognized,
            copiedAt: at,
          ),
        );
      }

      final first = await SmsTemplateSyncService.instance.reprocessBank(bankId);
      final second = await SmsTemplateSyncService.instance.reprocessBank(
        bankId,
      );

      expect(first.applied, 2);
      expect(first.duplicates, 0);
      expect(second.applied, 0);
      expect((await money.getMoneySources()).single.amount, 800);
      expect(
        (await SmsTemplateMobileStore.instance.getApplications()).length,
        2,
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

    expect(find.text('Choose a real message'), findsNothing);
    expect(find.text('What happened to the money?'), findsOneWidget);
    expect(find.text('Debited EGP150 at STAR MARKET'), findsOneWidget);
    expect(find.text('Debit'), findsOneWidget);
    expect(find.text('Credit'), findsOneWidget);

    await tester.tap(find.text('Debit'));
    await tester.pump();

    expect(find.text('Choose the money'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
    expect(find.text('Debited'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Debited')).dx,
      lessThan(tester.getTopLeft(find.text('150')).dx),
    );
    expect(
      Directionality.of(tester.element(find.text('150'))),
      TextDirection.ltr,
    );
    expect(
      tester.widget<Text>(find.text('150')).textDirection,
      TextDirection.ltr,
    );
  });

  testWidgets('arabic template message reads from right to left', (
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
            hash: 'arabic-message',
            smsId: 'arabic-message',
            sender: 'BANK',
            body: 'تم خصم مبلغ 150 جنيه',
            date: now,
            bankId: 'wizard-bank',
            status: SmsTemplateMessageStatus.unrecognized,
            copiedAt: now,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('تم خصم مبلغ 150 جنيه'), findsOneWidget);
    expect(find.text('Choose a real message'), findsNothing);

    await tester.tap(find.text('Credit'));
    await tester.pump();

    expect(find.text('خصم'), findsOneWidget);
    expect(find.text('150'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('تم')).dx,
      greaterThan(tester.getTopLeft(find.text('خصم')).dx),
    );
    expect(
      tester.getTopLeft(find.text('خصم')).dx,
      greaterThan(tester.getTopLeft(find.text('150')).dx),
    );
    expect(
      Directionality.of(tester.element(find.text('150'))),
      TextDirection.rtl,
    );
    expect(
      tester.widget<Text>(find.text('خصم')).textDirection,
      TextDirection.rtl,
    );
    expect(
      tester.widget<Text>(find.text('150')).textDirection,
      TextDirection.ltr,
    );
  });

  testWidgets('operations screen shows an active Undo action', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: SmsTemplateOperationsPage()),
    );
    await _waitForText(tester, 'Undo change');

    expect(find.text('Balance changes'), findsOneWidget);
    expect(find.text('Undo change'), findsAtLeastNWidgets(1));
  });

  test('sync cutoff starts on the activation day', () {
    final activated = DateTime(2026, 11, 8, 19, 40);

    expect(smsTemplateSyncAfter(activatedAt: activated), DateTime(2026, 11, 8));
    expect(
      smsTemplateSyncAfter(
        activatedAt: activated,
        lastSync: DateTime(2026, 11, 8, 0, 1),
      ),
      DateTime(2026, 11, 8),
    );
    expect(
      smsTemplateSyncAfter(
        activatedAt: DateTime(2026, 10, 1),
        lastSync: DateTime(2026, 11, 8, 12),
      ),
      DateTime(2026, 11, 8, 11, 58),
    );
  });

  test('global and bank sync cursors stay independent', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SmsTemplateMobileStore.instance;
    final global = DateTime(2026, 11, 10, 10);
    final bankA = DateTime(2026, 11, 10, 10, 5);
    final bankB = DateTime(2026, 11, 10, 9, 55);

    await store.setLastSyncAt(global);
    await store.setLastSyncAt(bankA, bankId: 'bank-a');
    await store.setLastSyncAt(bankB, bankId: 'bank-b');

    expect(await store.lastSyncAt(), global);
    expect(await store.lastSyncAt(bankId: 'bank-a'), bankA);
    expect(await store.lastSyncAt(bankId: 'bank-b'), bankB);
    expect(await store.lastSyncAt(bankId: 'bank-c'), isNull);
    expect(smsTemplateLatestSync(global, bankA), bankA);
    expect(smsTemplateLatestSync(global, bankB), global);
  });

  test('an SMS money operation applies only once', () async {
    final money = MoneyStorage();
    final db = await money.database;
    await db.delete('money_source_changes');
    await db.delete('money_sources');
    await db.delete('total_money_days');
    final columns = await db.rawQuery(
      "PRAGMA table_info('money_source_changes')",
    );
    expect(columns.map((column) => column['name']), contains('operationKey'));

    final sourceId = await money.addMoneySource(
      MoneySource(name: 'Idempotent card', amount: 1000),
    );
    final first = await SmsSourceApplier.instance.applySignedDeltaOnce(
      sourceId: sourceId,
      delta: -100,
      date: DateTime(2026, 11, 10),
      operationKey: 'sms-template-v2:idempotent',
    );
    final second = await SmsSourceApplier.instance.applySignedDeltaOnce(
      sourceId: sourceId,
      delta: -100,
      date: DateTime(2026, 11, 10),
      operationKey: 'sms-template-v2:idempotent',
    );

    expect(first?.newlyApplied, isTrue);
    expect(second?.newlyApplied, isFalse);
    expect(second?.beforeAmount, 1000);
    expect(second?.afterAmount, 900);
    expect((await money.getMoneySources()).single.amount, 900);
    final changes = await money.getMoneySourceChanges(sourceId);
    expect(changes, hasLength(1));
    expect(changes.single.operationKey, 'sms-template-v2:idempotent');
  });

  test(
    'reprocessing repairs records after money was already applied',
    () async {
      SharedPreferences.setMockInitialValues({
        SmsTemplateMobileStore.enabledKey: true,
      });
      final money = MoneyStorage();
      final moneyDb = await money.database;
      await moneyDb.delete('money_source_changes');
      await moneyDb.delete('money_sources');
      await moneyDb.delete('total_money_days');
      final sourceId = await money.addMoneySource(
        MoneySource(name: 'Recovery card', amount: 1000),
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

      const body = 'Debited 100 EGP successfully';
      const bankId = 'recovery-bank';
      const templateId = 'recovery-template';
      const smsId = 'recovery-sms';
      final hash = SmsHash.of(smsId: smsId, sender: 'BANK', body: body);
      await SmsTemplateMobileStore.instance.saveBank(
        SmsTemplateBank(
          id: bankId,
          name: 'Recovery Bank',
          senders: const ['BANK'],
          sourceId: sourceId,
          createdAt: DateTime(2026, 11, 10),
        ),
      );
      await SmsTemplateMobileStore.instance.saveTemplate(
        const SmsTemplate(
          id: templateId,
          bankId: bankId,
          sampleText: body,
          type: SmsTemplateType.debit,
          amount: SmsPlaceholder(
            kind: SmsPlaceholderKind.amount,
            range: SmsTextRange(start: 8, end: 11),
          ),
          directionRanges: [SmsTextRange(start: 0, end: 7)],
        ),
      );
      await SmsTemplateMobileStore.instance.upsertMessage(
        SmsTemplateStoredMessage(
          hash: hash,
          smsId: smsId,
          sender: 'BANK',
          body: body,
          date: DateTime(2026, 11, 10, 12),
          bankId: bankId,
          status: SmsTemplateMessageStatus.unrecognized,
          copiedAt: DateTime(2026, 11, 10, 12),
        ),
      );
      await SmsSourceApplier.instance.applySignedDeltaOnce(
        sourceId: sourceId,
        delta: -100,
        date: DateTime(2026, 11, 10, 12),
        operationKey: 'sms-template-v2:$hash',
      );

      final result = await SmsTemplateSyncService.instance.reprocessBank(
        bankId,
      );

      expect(result.applied, 1);
      expect((await money.getMoneySources()).single.amount, 900);
      expect(
        await SmsTemplateMobileStore.instance.hasApplication(hash),
        isTrue,
      );
      expect(await smsDb.query('transactions'), hasLength(1));
    },
  );

  test('concurrent reprocessing changes the source once', () async {
    SharedPreferences.setMockInitialValues({
      SmsTemplateMobileStore.enabledKey: true,
    });
    final money = MoneyStorage();
    final moneyDb = await money.database;
    await moneyDb.delete('money_source_changes');
    await moneyDb.delete('money_sources');
    await moneyDb.delete('total_money_days');
    final sourceId = await money.addMoneySource(
      MoneySource(name: 'Concurrent card', amount: 1000),
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

    const body = 'Debited 100 EGP successfully';
    const bankId = 'concurrent-bank';
    final hash = SmsHash.of(
      smsId: 'concurrent-sms',
      sender: 'BANK',
      body: body,
    );
    await SmsTemplateMobileStore.instance.saveBank(
      SmsTemplateBank(
        id: bankId,
        name: 'Concurrent Bank',
        senders: const ['BANK'],
        sourceId: sourceId,
        createdAt: DateTime(2026, 11, 10),
      ),
    );
    await SmsTemplateMobileStore.instance.saveTemplate(
      const SmsTemplate(
        id: 'concurrent-template',
        bankId: bankId,
        sampleText: body,
        type: SmsTemplateType.debit,
        amount: SmsPlaceholder(
          kind: SmsPlaceholderKind.amount,
          range: SmsTextRange(start: 8, end: 11),
        ),
        directionRanges: [SmsTextRange(start: 0, end: 7)],
      ),
    );
    await SmsTemplateMobileStore.instance.upsertMessage(
      SmsTemplateStoredMessage(
        hash: hash,
        smsId: 'concurrent-sms',
        sender: 'BANK',
        body: body,
        date: DateTime(2026, 11, 10, 12),
        bankId: bankId,
        status: SmsTemplateMessageStatus.unrecognized,
        copiedAt: DateTime(2026, 11, 10, 12),
      ),
    );

    final results = await Future.wait([
      SmsTemplateSyncService.instance.reprocessBank(bankId),
      SmsTemplateSyncService.instance.reprocessBank(bankId),
    ]);

    expect(results.fold<int>(0, (sum, item) => sum + item.applied), 1);
    expect((await money.getMoneySources()).single.amount, 900);
    expect(
      await SmsTemplateMobileStore.instance.getApplications(),
      hasLength(1),
    );
  });

  test(
    'enabling SMS Templates records the start of that day and keeps it',
    () async {
      SharedPreferences.setMockInitialValues({});
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);

      final enabled = await SmsTemplateSyncService.instance.setEnabled(true);
      expect(enabled, SmsTemplateEnableResult.enabled);
      expect(await SmsTemplateMobileStore.instance.activatedAt(), start);

      await SmsTemplateSyncService.instance.setEnabled(false);
      final again = await SmsTemplateSyncService.instance.setEnabled(true);

      expect(again, SmsTemplateEnableResult.enabled);
      expect(await SmsTemplateMobileStore.instance.activatedAt(), start);
    },
  );

  test(
    'an already enabled feature without an activation day starts today',
    () async {
      SharedPreferences.setMockInitialValues({
        SmsTemplateMobileStore.enabledKey: true,
      });
      final today = DateTime.now();

      final activated = await SmsTemplateMobileStore.instance
          .ensureActivatedAt();
      final again = await SmsTemplateMobileStore.instance.ensureActivatedAt();

      expect(activated, DateTime(today.year, today.month, today.day));
      expect(again, activated);
    },
  );

  test('inbox pages request 10 messages at a time', () {
    expect(
      smsInboxPageSort(limit: smsInboxPreviewPageSize, offset: 0),
      'date DESC LIMIT 10 OFFSET 0',
    );
    expect(
      smsInboxPageSort(limit: smsInboxPreviewPageSize, offset: 10),
      'date DESC LIMIT 10 OFFSET 10',
    );
    final filter = smsInboxSenderFilter(const [' HSBC ', 'CIB']);
    expect(filter?.selection, 'address = ? OR address = ?');
    expect(filter?.args, ['HSBC', 'CIB']);
    expect(smsInboxSenderFilter(const [' ', '']), isNull);
  });

  test('amount and balance templates change money differently', () {
    final amount = smsTemplateMoneyChange(
      result: const SmsParsedResult(
        templateId: 'amount',
        amount: 100,
        type: SmsTemplateType.debit,
      ),
      sourceAmount: 1000,
    );
    final balance = smsTemplateMoneyChange(
      result: const SmsParsedResult(
        templateId: 'balance',
        amount: 900,
        type: SmsTemplateType.debit,
        balance: 900,
        usesBalance: true,
      ),
      sourceAmount: 1000,
    );

    expect(amount.delta, -100);
    expect(amount.recordedAmount, 100);
    expect(balance.delta, -100);
    expect(balance.debit, isTrue);
    expect(balance.recordedAmount, 100);
  });

  test('a taught message applies only after SMS Templates was opened', () {
    final opened = DateTime(2026, 11, 8, 19, 40);

    expect(
      smsTaughtMessageShouldApply(
        messageDate: DateTime(2026, 10, 1, 9),
        activatedAt: opened,
      ),
      isFalse,
    );
    expect(
      smsTaughtMessageShouldApply(
        messageDate: DateTime(2026, 11, 8, 8),
        activatedAt: opened,
      ),
      isTrue,
    );
    expect(
      smsTaughtMessageShouldApply(
        messageDate: DateTime(2026, 11, 10, 12),
        activatedAt: null,
      ),
      isFalse,
    );
  });

  test(
    'only the taught message is stored, and inbox pages stay in memory',
    () async {
      SharedPreferences.setMockInitialValues({});
      const body = 'Debited EGP 20.00 at SHOP';
      const template = SmsTemplate(
        id: 'template-inbox-sample',
        bankId: 'hsbc-sample',
        sampleText: body,
        type: SmsTemplateType.debit,
        amount: SmsPlaceholder(
          kind: SmsPlaceholderKind.amount,
          range: SmsTextRange(start: 12, end: 17),
        ),
        directionRanges: [SmsTextRange(start: 0, end: 7)],
      );
      final message = SmsTemplateStoredMessage(
        hash: 'hsbc-sample-message',
        smsId: 'sms-1',
        sender: 'HSBC',
        body: body,
        date: DateTime(2026, 10, 1),
        bankId: 'hsbc-sample',
        status: SmsTemplateMessageStatus.pending,
        copiedAt: DateTime(2026, 11, 8),
      );
      final store = SmsTemplateMobileStore.instance;

      if (!kIsWeb && !Platform.isAndroid) {
        final preview = await SmsTemplateSyncService.instance.previewInboxPage(
          bankId: 'hsbc-sample',
          senders: const ['HSBC'],
          offset: 0,
        );
        expect(preview.supported, isFalse);
        expect(preview.messages, isEmpty);
        expect(await store.getMessages(bankId: 'hsbc-sample'), isEmpty);
      }

      await SmsTemplateSyncService.instance.saveTaughtTemplate(
        template: template,
        message: message,
      );

      final templates = await store.getTemplates(bankId: 'hsbc-sample');
      expect(templates.single.sampleText, body);
      final saved = await store.getMessages(bankId: 'hsbc-sample');
      expect(saved, hasLength(1));
      expect(saved.single.body, body);
      expect(saved.single.templateId, template.id);
      expect(saved.single.status, SmsTemplateMessageStatus.sample);
    },
  );

  test('a taught example is not applied, but a later match still is', () async {
    SharedPreferences.setMockInitialValues({
      SmsTemplateMobileStore.enabledKey: true,
    });
    final money = MoneyStorage();
    final moneyDb = await money.database;
    await moneyDb.delete('money_source_changes');
    await moneyDb.delete('money_sources');
    final sourceId = await money.addMoneySource(
      MoneySource(name: 'Taught card', amount: 1000),
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
    const body = 'Debited 100 EGP successfully';
    const template = SmsTemplate(
      id: 'taught-template',
      bankId: 'taught-bank',
      sampleText: body,
      type: SmsTemplateType.debit,
      amount: SmsPlaceholder(
        kind: SmsPlaceholderKind.amount,
        range: SmsTextRange(start: 8, end: 11),
      ),
      directionRanges: [SmsTextRange(start: 0, end: 7)],
    );
    final sample = SmsTemplateStoredMessage(
      hash: SmsHash.of(smsId: 'old-sms', sender: 'BANK', body: body),
      smsId: 'old-sms',
      sender: 'BANK',
      body: body,
      date: DateTime(2026, 10, 1, 9),
      bankId: 'taught-bank',
      status: SmsTemplateMessageStatus.pending,
      copiedAt: DateTime(2026, 11, 10),
    );
    await SmsTemplateMobileStore.instance.saveBank(
      SmsTemplateBank(
        id: 'taught-bank',
        name: 'Taught Bank',
        senders: const ['BANK'],
        sourceId: sourceId,
        createdAt: DateTime(2026, 11, 10),
      ),
    );
    await SmsTemplateMobileStore.instance.upsertMessage(
      SmsTemplateStoredMessage(
        hash: SmsHash.of(smsId: 'new-sms', sender: 'BANK', body: body),
        smsId: 'new-sms',
        sender: 'BANK',
        body: body,
        date: DateTime(2026, 11, 10, 12),
        bankId: 'taught-bank',
        status: SmsTemplateMessageStatus.unrecognized,
        copiedAt: DateTime(2026, 11, 10),
      ),
    );

    await SmsTemplateSyncService.instance.saveTaughtTemplate(
      template: template,
      message: sample,
    );
    final result = await SmsTemplateSyncService.instance.reprocessBank(
      'taught-bank',
    );
    final source = (await money.getMoneySources()).single;
    final savedSample = (await SmsTemplateMobileStore.instance.getMessages(
      bankId: 'taught-bank',
    )).firstWhere((message) => message.smsId == 'old-sms');

    expect(result.applied, 1);
    expect(source.amount, 900);
    expect(savedSample.status, SmsTemplateMessageStatus.sample);
    expect(
      await SmsTemplateMobileStore.instance.hasApplication(sample.hash),
      isFalse,
    );
  });

  test(
    'teaching from a message after SMS Templates opened applies it',
    () async {
      final opened = DateTime(2026, 11, 8);
      SharedPreferences.setMockInitialValues({
        SmsTemplateMobileStore.enabledKey: true,
        SmsTemplateMobileStore.activatedAtKey: opened.millisecondsSinceEpoch,
      });
      final money = MoneyStorage();
      final moneyDb = await money.database;
      await moneyDb.delete('money_source_changes');
      await moneyDb.delete('money_sources');
      final sourceId = await money.addMoneySource(
        MoneySource(name: 'Opened card', amount: 1000),
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
      const body = 'Debited 100 EGP successfully';
      const template = SmsTemplate(
        id: 'opened-template',
        bankId: 'opened-bank',
        sampleText: body,
        type: SmsTemplateType.debit,
        amount: SmsPlaceholder(
          kind: SmsPlaceholderKind.amount,
          range: SmsTextRange(start: 8, end: 11),
        ),
        directionRanges: [SmsTextRange(start: 0, end: 7)],
      );
      final message = SmsTemplateStoredMessage(
        hash: SmsHash.of(smsId: 'today-sms', sender: 'BANK', body: body),
        smsId: 'today-sms',
        sender: 'BANK',
        body: body,
        date: DateTime(2026, 11, 10, 12),
        bankId: 'opened-bank',
        status: SmsTemplateMessageStatus.pending,
        copiedAt: DateTime(2026, 11, 10),
      );
      await SmsTemplateMobileStore.instance.saveBank(
        SmsTemplateBank(
          id: 'opened-bank',
          name: 'Opened Bank',
          senders: const ['BANK'],
          sourceId: sourceId,
          createdAt: opened,
        ),
      );

      await SmsTemplateSyncService.instance.saveTaughtTemplate(
        template: template,
        message: message,
      );
      final result = await SmsTemplateSyncService.instance.reprocessBank(
        'opened-bank',
      );
      final source = (await money.getMoneySources()).single;

      expect(result.applied, 1);
      expect(source.amount, 900);
      expect(
        await SmsTemplateMobileStore.instance.hasApplication(message.hash),
        isTrue,
      );
    },
  );
}

Future<void> _waitForText(WidgetTester tester, String text) async {
  for (var i = 0; i < 40 && find.text(text).evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}
