import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/tour/app_tour.dart';

void main() {
  test('tour points at the main sections and skips empty ones', () {
    final anchors = AppTourAnchors();
    final full = AppTourSteps.compose(
      anchors,
      hasSources: true,
      hasHistoryDays: true,
    );
    final titles = full.map((step) => step.title).toList();

    expect(titles.first, 'أهلاً بيك');
    expect(titles, contains('إجمالي الفلوس'));
    expect(titles, contains('مصدر الفلوس'));
    expect(titles, contains('يوم في السجل'));
    expect(titles, contains('رسائل البنك'));
    expect(titles.last, 'إعادة الجولة');
    expect(full.first.tab, AppTourSteps.totalTab);
    expect(full.last.tab, AppTourSteps.settingsTab);
    expect(
      full.every((step) => step.title.isNotEmpty && step.body.isNotEmpty),
      isTrue,
    );

    final empty = AppTourSteps.compose(
      anchors,
      hasSources: false,
      hasHistoryDays: false,
    );
    final emptyTitles = empty.map((step) => step.title);
    expect(emptyTitles, isNot(contains('مصدر الفلوس')));
    expect(emptyTitles, isNot(contains('يوم في السجل')));
    expect(emptyTitles, contains('إضافة مصدر'));
  });

  testWidgets('tour card explains the highlighted section', (tester) async {
    final key = GlobalKey();
    var nextTaps = 0;
    var skips = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Center(
                child: SizedBox(
                  key: key,
                  width: 120,
                  height: 48,
                  child: const ColoredBox(color: Colors.green),
                ),
              ),
              Positioned.fill(
                child: AppTourOverlay(
                  step: AppTourStep(
                    target: key,
                    tab: 0,
                    title: 'إجمالي الفلوس',
                    body: 'الرقم ده مجموع كل فلوسك دلوقتي.',
                  ),
                  index: 0,
                  total: 3,
                  onNext: () => nextTaps++,
                  onBack: () {},
                  onSkip: () => skips++,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('إجمالي الفلوس'), findsOneWidget);
    expect(find.text('الرقم ده مجموع كل فلوسك دلوقتي.'), findsOneWidget);
    expect(find.text('يلا نبدأ'), findsOneWidget);

    await tester.tap(find.text('يلا نبدأ'));
    await tester.pump();
    expect(nextTaps, 1);

    await tester.tap(find.text('تخطي'));
    await tester.pump();
    expect(skips, 1);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
