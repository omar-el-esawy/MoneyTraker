import 'package:money_traker/sms/sms_models.dart';

class SmsStrings {
  final bool ar;

  const SmsStrings(this.ar);

  String get title => ar ? 'رسائل البنك' : 'Bank messages';
  String get intro => ar
      ? 'اختر تاريخ البداية، ثم افتح بنكاً لربط مصدر المال وتعليم الرسائل.'
      : 'Pick a start date, then open a bank to link a money source and teach its messages.';
  String get openBank => ar ? 'افتح البنك' : 'Open bank';
  String get off => ar ? 'متوقف' : 'Off';
  String messagesCount(int count) => ar ? '$count رسالة' : '$count messages';
  String rulesCount(int count) => ar ? '$count قاعدة' : '$count rules';
  String get startDate => ar ? 'تاريخ البداية' : 'Start date';
  String get pickDate => ar ? 'اختر التاريخ' : 'Choose date';
  String get banks => ar ? 'البنوك' : 'Banks';
  String get banksHint => ar
      ? 'فعّل البنك وعدّل اسم المُرسِل كما يظهر في الرسالة.'
      : 'Turn a bank on and edit the sender name as it appears on the message.';
  String get addBank => ar ? 'إضافة بنك' : 'Add bank';
  String get addSender => ar ? 'إضافة مُرسِل' : 'Add sender';
  String get senderHint => ar ? 'اسم المُرسِل' : 'Sender name';
  String get nameEn => ar ? 'الاسم بالإنجليزية' : 'English name';
  String get nameAr => ar ? 'الاسم بالعربية' : 'Arabic name';
  String get save => ar ? 'حفظ' : 'Save';
  String get cancel => ar ? 'إلغاء' : 'Cancel';
  String get delete => ar ? 'حذف' : 'Delete';
  String get deleteBank => ar ? 'حذف البنك' : 'Delete bank';
  String deleteBankConfirm(String name) => ar
      ? 'حذف $name؟ لن تُجلب رسائله بعد الآن.'
      : 'Delete $name? Its messages will no longer be fetched.';
  String get start => ar ? 'ابدأ وانسخ الرسائل' : 'Start and copy messages';
  String get checkNow => ar ? 'افحص الرسائل الآن' : 'Check messages now';
  String get fetchFromStart =>
      ar ? 'اجلب من تاريخ البداية' : 'Fetch from start date';
  String get applyFromStart =>
      ar ? 'طبّق من تاريخ البداية' : 'Apply from start date';
  String get applyFromStartHint => ar
      ? 'يطبق الرسائل غير المطبّقة من تاريخ البداية. الرسالة المطبّقة تُتخطى. يمكنك إرجاع رسالة إلى غير مطبّق ثم التطبيق مرة أخرى.'
      : 'Applies messages that are not applied, from the start date. Applied messages are skipped. You can mark a message as not applied, then apply again.';
  String get applied => ar ? 'مطبّق' : 'Applied';
  String get notApplied => ar ? 'غير مطبّق' : 'Not applied';
  String get markNotApplied => ar ? 'اجعلها غير مطبّق' : 'Mark as not applied';
  String get copied => ar ? 'نسخ الرسائل' : 'Copied messages';
  String get rules => ar ? 'قواعد القراءة' : 'Reading rules';
  String get parsed => ar ? 'تمت قراءتها' : 'Read';
  String get appliedToSource =>
      ar ? 'تم خصم/إضافة المصدر' : 'Money source updated';
  String get notAppliedToSource =>
      ar ? 'لم يُحدَّث المصدر بعد' : 'Money source not updated yet';
  String get currentSources => ar ? 'أرصدة المصادر الآن' : 'Money sources now';
  String get pending => ar ? 'بانتظار التعليم' : 'Waiting to be marked';
  String get unreadable => ar ? 'لم تطابق قاعدة' : 'No matching rule';
  String get markHint => ar
      ? 'حدّد المبلغ حتى لو لازق في حروف زي EGP. وحدّد أي جزء من النص يعني خصم أو إيداع أو تصنيف. لما نفس الجزء يظهر في رسالة جاية، هيعمل نفس الحاجة.'
      : 'Select the amount, even when it is stuck to letters such as EGP. Select any part of the text that means a debit, a credit, or a category. When that same text appears in a later message, it does the same thing.';
  String get noNumbers =>
      ar ? 'لا توجد أرقام في هذه الرسالة.' : 'This message has no numbers.';
  String get moneySource => ar ? 'مصدر المال' : 'Money source';
  String get noMoneySource => ar ? 'بدون ربط' : 'Not linked';
  String get noSourcesYet => ar
      ? 'أضف مصدر مال من الصفحة الرئيسية أولاً.'
      : 'Add a money source on the home page first.';
  String get typeWords => ar ? 'نصوص الخصم والإيداع' : 'Debit and credit text';
  String get categoryRules =>
      ar ? 'تصنيف المصروف والدخل' : 'Expense and income rules';
  String get categoryRulesHint => ar
      ? 'حدّد أي جزء من الرسالة. الخصم يتحط في التصنيف، ولو الفلوس رجعت بعد كده تنقص من نفس التصنيف حتى لو في يوم تاني.'
      : 'Select any text in a message. A deduction is filed under the category, and money added back is removed from that same category, even on a later day.';
  String get wordMeansCategory => ar
      ? 'حط المبلغ في مصروف أو دخل'
      : 'File the amount as an expense or income';
  String get pickCategory => ar ? 'اختار التصنيف' : 'Choose a category';
  String pickCategoryHint(String word) => ar
      ? 'لو الرسالة فيها «$word» وخصمت، المبلغ يتحط في التصنيف. لو رجّعت فلوس، ينقص من نفس التصنيف.'
      : 'If a message containing "$word" is a deduction, the amount is filed here. If money is added back, it is removed from the same category.';
  String get expenses => ar ? 'مصروف' : 'Expense';
  String get income => ar ? 'دخل' : 'Income';
  String get newCategory => ar ? 'تصنيف جديد' : 'New category';
  String get noCategoryTags => ar
      ? 'مفيش تصنيفات لسه. اكتب اسم جديد تحت.'
      : 'No categories yet. Type a new name below.';
  String get categorySaved => ar
      ? 'اتحفظت القاعدة. أي رسالة مطبّقة فيها النص ده هتتصنف لوحدها.'
      : 'Rule saved. Applied messages that contain this text are categorized automatically.';
  String get missingCategory => ar ? 'تصنيف محذوف' : 'Deleted category';
  String categoryApplied(bool expense, String name) => ar
      ? 'وهيتحط في ${expense ? 'المصروف' : 'الدخل'}: $name.'
      : 'Filed under ${expense ? 'expense' : 'income'}: $name.';
  String categoryReduced(bool expense, String name) => ar
      ? 'وهتقلل من ${expense ? 'المصروف' : 'الدخل'}: $name.'
      : 'Taken out of ${expense ? 'expense' : 'income'}: $name.';
  String get markThisText => ar ? 'علّم النص ده' : 'Mark this text';
  String get selectSomeText =>
      ar ? 'حدّد نص الأول.' : 'Select some text first.';
  String get wordMeansDebit =>
      ar ? 'النص ده يعني خصم' : 'This text means debit';
  String get wordMeansCredit =>
      ar ? 'النص ده يعني إيداع' : 'This text means credit';
  String selectedTextMeans(String text) =>
      ar ? '«$text» يعني' : '"$text" means';
  String get amount => ar ? 'المبلغ' : 'Amount';
  String get balance => ar ? 'الرصيد' : 'Balance';
  String get account => ar ? 'رقم الحساب' : 'Account number';
  String get debit => ar ? 'خصم' : 'Debit';
  String get credit => ar ? 'إيداع' : 'Credit';
  String get whatIsThis => ar ? 'هذا الرقم يعني' : 'This number means';
  String get removeMark => ar ? 'إزالة العلامة' : 'Remove mark';
  String get saveRules => ar ? 'احفظ القواعد' : 'Save rules';
  String get needAmount =>
      ar ? 'علّم على رقم المبلغ أولاً.' : 'Mark the amount number first.';
  String get weakRule => ar
      ? 'ضع العلامة على رقم حوله كلمات، حتى تستطيع القاعدة تمييزه.'
      : 'Mark a number that has words around it, so the rule can recognize it.';
  String get emptyMessages => ar
      ? 'لا توجد رسائل منسوخة بعد. افحص الرسائل أو غيّر البنوك والتاريخ.'
      : 'No copied messages yet. Check messages, or change the banks and date.';
  String get androidOnly => ar
      ? 'قراءة الرسائل تعمل على هاتف أندرويد.'
      : 'Reading messages works on an Android phone.';
  String get permissionDenied => ar
      ? 'السماح بقراءة الرسائل مطلوب.'
      : 'Permission to read messages is required.';
  String get preview =>
      ar ? 'القراءة من هذه الرسالة' : 'Reading from this message';
  String get none => ar ? 'لا شيء بعد' : 'Nothing yet';
  String get language => ar ? 'English' : 'عربي';
  String get openToMark =>
      ar ? 'افتح رسالة لتعليم الأرقام' : 'Open a message to mark numbers';
  String get messages => ar ? 'الرسائل المنسوخة' : 'Copied messages';
  String get ruleTester => ar ? 'تجربة القاعدة' : 'Rule tester';
  String get ruleTesterHint => ar
      ? 'دي نتيجة تجريبية بس. مفيش حاجة هتتخصم دلوقتي. لو القراءة صح، فعّل القاعدة.'
      : 'This is a preview only. Nothing is deducted yet. Activate the rule if the reading looks right.';
  String get thisMessage => ar ? 'نتيجة الرسالة دي' : 'Result for this message';
  String get otherMessages =>
      ar ? 'الرسايل القديمة بنفس القاعدة' : 'Old messages with the same rule';
  String money(double amount) {
    return amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(2);
  }

  String dateLabel(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  String outcome({
    required String typeHint,
    required double amount,
    required DateTime date,
    String? sourceName,
  }) {
    final value = money(amount);
    final day = dateLabel(date);
    final source = (sourceName == null || sourceName.isEmpty)
        ? (ar ? 'المصدر لما يتربط' : 'the linked money source')
        : sourceName;
    if (typeHint == 'debit') {
      return ar
          ? 'هنخصم $value يوم $day من $source.'
          : 'We will deduct $value on $day from $source.';
    }
    if (typeHint == 'credit') {
      return ar
          ? 'هنضيف $value يوم $day إلى $source.'
          : 'We will add $value on $day to $source.';
    }
    return ar ? 'المبلغ $value يوم $day.' : 'Amount $value on $day.';
  }

  String incompleteReading(SmsReading reading) {
    if (reading.amount == null && reading.typeHint.isEmpty) {
      return ar
          ? 'القاعدة مش قادرة تقرأ الرسالة دي: مفيش مبلغ ولا خصم/إيداع.'
          : 'The rule cannot read this message: no amount and no debit/credit.';
    }
    if (reading.amount == null) {
      return ar
          ? 'عرفنا إنها ${typeLabel(reading.typeHint)}، بس المبلغ مش ظاهر.'
          : 'This looks like a ${typeLabel(reading.typeHint).toLowerCase()}, but the amount is missing.';
    }
    return ar
        ? 'المبلغ ${money(reading.amount!)} ظاهر، بس مش محدد خصم ولا إيداع.'
        : 'Amount ${money(reading.amount!)} was found, but debit or credit is not set.';
  }

  String get testRules => ar ? 'جرّب القواعد' : 'Test rules';
  String get activateRule => ar ? 'فعّل القاعدة' : 'Activate rule';
  String get reprocess =>
      ar ? 'أعد تحليل الرسايل القديمة' : 'Re-process old messages';
  String get reprocessHint => ar
      ? 'يحلل الرسايل الأصلية مرة تانية ويحدّث العمليات بدل ما يكرّرها.'
      : 'Re-reads the original messages and updates transactions instead of duplicating them.';
  String matchedLine(int matched, int total) => ar
      ? 'هتتأثر $matched من أصل $total رسالة.'
      : '$matched of $total messages would be affected.';
  String get ruleVersion => ar ? 'إصدار القاعدة' : 'Rule version';
  String get sampleHits =>
      ar ? 'عيّنة من الرسايل المتأثرة' : 'Sample of affected messages';
  String get noHits => ar
      ? 'مفيش رسايل قديمة تطابق القاعدة دي.'
      : 'No old messages match this rule.';
  String field(SmsField field) {
    switch (field) {
      case SmsField.amount:
        return amount;
      case SmsField.balance:
        return balance;
      case SmsField.account:
        return account;
    }
  }

  String typeLabel(String hint) {
    if (hint == 'debit') return debit;
    if (hint == 'credit') return credit;
    return '';
  }

  String resultLine({
    required int copied,
    required int parsed,
    int appliedToSource = 0,
    int skipped = 0,
    int unmatched = 0,
    int missingSource = 0,
    int updated = 0,
    String error = '',
  }) {
    if (error.isNotEmpty) {
      return ar ? 'فشل التطبيق: $error' : 'Apply failed: $error';
    }
    if (ar) {
      return 'تطبيق $appliedToSource، تحديث $updated، تخطي $skipped مطبّق، بدون قاعدة $unmatched، بدون مصدر $missingSource.';
    }
    return 'Applied $appliedToSource, updated $updated, skipped $skipped already applied, no matching rule $unmatched, no money source $missingSource.';
  }
}
