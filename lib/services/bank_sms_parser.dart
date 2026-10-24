import 'package:money_traker/domain/entities/transaction_entity.dart';

class BankSmsParser {
  final Map<String, List<String>> bankSenders = {
    'CIB': ['CIB-Egypt', 'CIBEGYPT', 'CIB'],
    'NBE': ['NBE', 'AlAhlyBank', 'NationalBank'],
    'Banque Misr': ['BanqueMisr', 'B-Misr'],
    'QNB': ['QNBALAHLI', 'QNB'],
    'Alex Bank': ['AlexBank', 'ABE'],
    'ADCB': ['ADCB'],
    'HSBC': ['HSBC'],
    'Fawry': ['Fawry', 'FawryPay'],
  };

  final debitPatterns = [
    RegExp(r'تم خصم\s+([\d,]+(?:\.\d+)?)\s+جنيه'),
    RegExp(r'debited\s+EGP\s*([\d,]+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'Purchase of\s+EGP\s*([\d,]+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'مشتريات بمبلغ\s+([\d,]+(?:\.\d+)?)'),
    RegExp(r'Amount[:\s]+EGP\s*([\d,]+(?:\.\d+)?)', caseSensitive: false),
  ];

  final creditPatterns = [
    RegExp(r'تم إيداع\s+([\d,]+(?:\.\d+)?)\s+جنيه'),
    RegExp(r'credited\s+EGP\s*([\d,]+(?:\.\d+)?)', caseSensitive: false),
    RegExp(r'تحويل وارد بمبلغ\s+([\d,]+(?:\.\d+)?)'),
  ];

  final debitKeywords = ['خصم', 'debited', 'purchase', 'مشتريات', 'سحب'];
  final creditKeywords = ['إيداع', 'credited', 'deposit', 'تحويل وارد'];

  TransactionEntity? parse(String sender, String body) {
    final bank = _detectBank(sender);
    if (bank == null) return null;

    final amount = _extractAmount(body);
    if (amount == null) return null;

    final type = _detectType(body);

    return TransactionEntity(
      bank: bank,
      amount: amount,
      type: type,
      date: DateTime.now(),
      rawSms: body,
    );
  }

  String? _detectBank(String sender) {
    for (final entry in bankSenders.entries) {
      if (entry.value.any((s) => sender.toLowerCase().contains(s.toLowerCase()))) {
        return entry.key;
      }
    }
    return null;
  }

  double? _extractAmount(String body) {
    for (final pattern in [...debitPatterns, ...creditPatterns]) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        return double.tryParse(match.group(1)!.replaceAll(',', ''));
      }
    }
    return null;
  }

  TransactionType _detectType(String body) {
    final lower = body.toLowerCase();
    if (debitKeywords.any((k) => lower.contains(k))) {
      return TransactionType.debit;
    }
    return TransactionType.credit;
  }
}

