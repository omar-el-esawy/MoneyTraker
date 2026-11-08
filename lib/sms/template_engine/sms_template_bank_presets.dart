class SmsTemplateBankPreset {
  final String id;
  final String name;
  final List<String> senders;

  const SmsTemplateBankPreset({
    required this.id,
    required this.name,
    required this.senders,
  });

  static const customId = '__custom__';

  static const all = [
    SmsTemplateBankPreset(
      id: 'cib',
      name: 'CIB',
      senders: ['CIB-Egypt', 'CIBEGYPT', 'CIB'],
    ),
    SmsTemplateBankPreset(
      id: 'nbe',
      name: 'NBE',
      senders: ['NBE', 'AlAhlyBank', 'NationalBank'],
    ),
    SmsTemplateBankPreset(
      id: 'banque_misr',
      name: 'Banque Misr',
      senders: ['BanqueMisr', 'B-Misr'],
    ),
    SmsTemplateBankPreset(
      id: 'qnb',
      name: 'QNB',
      senders: ['QNBALAHLI', 'QNB'],
    ),
    SmsTemplateBankPreset(
      id: 'alex',
      name: 'Alex Bank',
      senders: ['AlexBank', 'ABE'],
    ),
    SmsTemplateBankPreset(id: 'adcb', name: 'ADCB', senders: ['ADCB']),
    SmsTemplateBankPreset(id: 'hsbc', name: 'HSBC', senders: ['HSBC']),
    SmsTemplateBankPreset(
      id: 'banque_du_caire',
      name: 'Banque du Caire',
      senders: ['BdC', 'BanqueDuCaire'],
    ),
    SmsTemplateBankPreset(id: 'aaib', name: 'AAIB', senders: ['AAIB']),
    SmsTemplateBankPreset(
      id: 'fawry',
      name: 'Fawry',
      senders: ['Fawry', 'FawryPay'],
    ),
    SmsTemplateBankPreset(
      id: 'vodafone_cash',
      name: 'Vodafone Cash',
      senders: ['VF-Cash', 'Vodafone', 'VFCash'],
    ),
    SmsTemplateBankPreset(
      id: 'etisalat_cash',
      name: 'Etisalat Cash',
      senders: ['Etisalat', 'eand', 'e& money'],
    ),
    SmsTemplateBankPreset(
      id: 'orange_cash',
      name: 'Orange Cash',
      senders: ['Orange', 'OrangeCash'],
    ),
    SmsTemplateBankPreset(
      id: 'we_pay',
      name: 'WE Pay',
      senders: ['WE', 'WEPay'],
    ),
  ];
}
