import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/sms/template_engine/sms_amount_parser.dart';

void main() {
  group('SmsAmountParser', () {
    test('parses comma thousands and dot decimals', () {
      expect(SmsAmountParser.parse('1,500.00'), 1500);
      expect(SmsAmountParser.parse('12,345,678.90'), 12345678.90);
    });

    test('parses dot thousands and comma decimals', () {
      expect(SmsAmountParser.parse('1.500,00'), 1500);
      expect(SmsAmountParser.parse('12.345.678,90'), 12345678.90);
    });

    test('parses amounts without thousands separators or decimals', () {
      expect(SmsAmountParser.parse('1500'), 1500);
      expect(SmsAmountParser.parse('1500,50'), 1500.50);
      expect(SmsAmountParser.parse('1500.50'), 1500.50);
    });

    test('parses Arabic-Indic, Persian, and mixed digits', () {
      expect(SmsAmountParser.parse('١\u066C٥٠٠\u066B٢٥'), 1500.25);
      expect(SmsAmountParser.parse('۱۵۰۰,۵۰'), 1500.50);
      expect(SmsAmountParser.parse('1٥۰٠.2٥'), 1500.25);
    });

    test('accepts currency before, after, or attached to the amount', () {
      expect(SmsAmountParser.parse('EGP 1500'), 1500);
      expect(SmsAmountParser.parse('1500 جنيه'), 1500);
      expect(SmsAmountParser.parse('EGP1500'), 1500);
      expect(SmsAmountParser.parse('1500EGP'), 1500);
      expect(SmsAmountParser.parse('ج.م 150'), 150);
      expect(SmsAmountParser.parse('LE1,500.00'), 1500);
      expect(SmsAmountParser.parse('USD 25.50'), 25.50);
      expect(SmsAmountParser.parse(r'$75'), 75);
    });

    test('rejects a marked value containing more than one number', () {
      expect(SmsAmountParser.parse('خصم 150 والرصيد 900'), isNull);
      expect(SmsAmountParser.parse('card 1234 amount EGP 50'), isNull);
    });

    test('rejects missing, zero, and malformed amounts', () {
      expect(SmsAmountParser.parse('EGP'), isNull);
      expect(SmsAmountParser.parse('0.00'), isNull);
      expect(SmsAmountParser.parse('12,34,567.00'), isNull);
      expect(SmsAmountParser.parse('1.2.3'), isNull);
    });
  });
}
