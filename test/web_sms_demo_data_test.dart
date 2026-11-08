import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/pages/sms/web_sms_template_demo_page.dart';
import 'package:money_traker/sms/template_engine/template_models.dart';
import 'package:money_traker/sms/template_engine/web_demo_data.dart';

void main() {
  test(
    'web demo catalog uses only in-memory fake messages and valid templates',
    () {
      final banks = WebSmsDemoCatalog.build();

      expect(banks, hasLength(2));
      expect(banks.every((bank) => bank.messages.isNotEmpty), isTrue);
      expect(banks.every((bank) => bank.templates.isNotEmpty), isTrue);

      final cib = banks.firstWhere((bank) => bank.id == 'cib-demo');
      final cibResults = [
        for (final message in cib.messages) cib.templateSet.match(message.body),
      ];
      expect(cibResults[0]!.type, SmsTemplateType.debit);
      expect(cibResults[0]!.amount, 2750.50);
      expect(cibResults[1]!.type, SmsTemplateType.credit);
      expect(cibResults[2], isNull);
      expect(cibResults[3], isNull);

      final qnb = banks.firstWhere((bank) => bank.id == 'qnb-demo');
      final qnbResults = [
        for (final message in qnb.messages) qnb.templateSet.match(message.body),
      ];
      expect(qnbResults[0]!.merchant, 'IKEA CAIRO');
      expect(qnbResults[1]!.type, SmsTemplateType.credit);
      expect(qnbResults[2], isNull);
    },
  );

  testWidgets('clicking a demo bank opens its fake inbox', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WebSmsTemplateDemoPage()));

    expect(find.text('CIB — بيانات تجريبية'), findsOneWidget);
    await tester.tap(find.text('CIB — بيانات تجريبية'));
    await tester.pumpAndSettle();

    expect(find.text('Try a message'), findsOneWidget);
    expect(find.text('Teach new template'), findsOneWidget);
    expect(find.text('Fake inbox'), findsOneWidget);
    expect(find.textContaining('SEOUDI SILVER-STAR'), findsWidgets);
  });
}
