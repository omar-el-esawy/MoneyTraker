import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:money_traker/constants/app_constants.dart';

/// Stable targets for the first-run walkthrough.
class AppTourAnchors {
  final totalMoney = GlobalKey(debugLabel: 'tour_total');
  final hideAmounts = GlobalKey(debugLabel: 'tour_hide');
  final goals = GlobalKey(debugLabel: 'tour_goals');
  final firstSource = GlobalKey(debugLabel: 'tour_source');
  final addSource = GlobalKey(debugLabel: 'tour_add');
  final bottomNav = GlobalKey(debugLabel: 'tour_nav');
  final historyChart = GlobalKey(debugLabel: 'tour_chart');
  final historyDay = GlobalKey(debugLabel: 'tour_day');
  final compareDays = GlobalKey(debugLabel: 'tour_compare');
  final insightsHeader = GlobalKey(debugLabel: 'tour_insights');
  final insightsSummary = GlobalKey(debugLabel: 'tour_summary');
  final bankMessages = GlobalKey(debugLabel: 'tour_bank');
  final backup = GlobalKey(debugLabel: 'tour_backup');
  final replay = GlobalKey(debugLabel: 'tour_replay');
}

class AppTourScope extends InheritedWidget {
  final AppTourAnchors anchors;

  const AppTourScope({super.key, required this.anchors, required super.child});

  static AppTourAnchors? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppTourScope>()?.anchors;
  }

  @override
  bool updateShouldNotify(AppTourScope oldWidget) =>
      anchors != oldWidget.anchors;
}

class AppTourStep {
  final GlobalKey? target;
  final int tab;
  final String title;
  final String body;

  const AppTourStep({
    required this.target,
    required this.tab,
    required this.title,
    required this.body,
  });
}

class AppTourSteps {
  static const totalTab = 0;
  static const historyTab = 1;
  static const insightsTab = 2;
  static const settingsTab = 3;

  static List<AppTourStep> compose(
    AppTourAnchors anchors, {
    required bool hasSources,
    required bool hasHistoryDays,
  }) {
    return [
      const AppTourStep(
        target: null,
        tab: totalTab,
        title: 'أهلاً بيك',
        body:
            'الجولة دي هتمشي على الخانات الأساسية وتقولك كل واحدة بتعمل إيه. تقدر تتخطاها في أي وقت، وترجع لها من الإعدادات.',
      ),
      AppTourStep(
        target: anchors.totalMoney,
        tab: totalTab,
        title: 'إجمالي الفلوس',
        body:
            'الرقم ده مجموع كل فلوسك دلوقتي. بيتحدث لوحده لما تزود أو تنقص أو تحوّل بين المصادر.',
      ),
      AppTourStep(
        target: anchors.hideAmounts,
        tab: totalTab,
        title: 'إخفاء الأرقام',
        body:
            'اضغط العين عشان تخبي المبالغ لو حد بيبص على الشاشة، واضغطها تاني عشان تظهر.',
      ),
      AppTourStep(
        target: anchors.goals,
        tab: totalTab,
        title: 'الأهداف',
        body:
            'هنا أهداف التوفير أو حد المصروف، وقد إيه فاضل عليها. See all يفتح كل الأهداف، و New Goal يضيف هدف جديد.',
      ),
      if (hasSources)
        AppTourStep(
          target: anchors.firstSource,
          tab: totalTab,
          title: 'مصدر الفلوس',
          body:
              'دي خانة مصدر زي الكاش أو البنك. اضغطها عشان تزود أو تنقص أو تحوّل أو تشوف السجل، واسحبها لليسار عشان تمسحها.',
        ),
      AppTourStep(
        target: anchors.addSource,
        tab: totalTab,
        title: 'إضافة مصدر',
        body:
            hasSources
                ? 'الزرار ده يضيف مصدر جديد باسم ومبلغ. تقدر تسجل الحركة بتاريخ أقدم لو فاتتك.'
                : 'لسه مفيش مصادر. الزرار ده يضيف أول مصدر، زي كاش أو بنك. بعد كده هتقدر تضغط الخانة عشان تزود أو تنقص أو تحوّل.',
      ),
      AppTourStep(
        target: anchors.bottomNav,
        tab: totalTab,
        title: 'القوائم',
        body:
            'من الشريط ده تتنقل بين أربع صفحات: الإجمالي، السجل، التحليلات، والإعدادات.',
      ),
      AppTourStep(
        target: anchors.historyChart,
        tab: historyTab,
        title: 'السجل',
        body: 'الرسم بيوضح رصيدك يوم بيوم. قرّب بإصبعين عشان تشوف فترة أقصر.',
      ),
      if (hasHistoryDays)
        AppTourStep(
          target: anchors.historyDay,
          tab: historyTab,
          title: 'يوم في السجل',
          body:
              'الكارت فيه إجمالي اليوم والفرق عن اليوم اللي قبله. ضغطة بتصنّف الفرق، وضغطة مطوّلة بتكتب ملاحظة.',
        ),
      AppTourStep(
        target: anchors.compareDays,
        tab: historyTab,
        title: 'مقارنة يومين',
        body:
            'الأيقونة دي بتختار يومين وتوريك الفرق بينهم. بتشتغل لما يبقى عندك يومين أو أكتر.',
      ),
      AppTourStep(
        target: anchors.insightsHeader,
        tab: insightsTab,
        title: 'التحليلات',
        body:
            'اختار يوم أو أسبوع أو شهر، واتنقل بالأسهم بين الفترات. أيقونة التقويم بتحدد تاريخ معين.',
      ),
      AppTourStep(
        target: anchors.insightsSummary,
        tab: insightsTab,
        title: 'صافي الفترة',
        body:
            'الكارت الأخضر بيوريك الدخل والمصروف والصافي. تحتيه توزيع المبالغ على التصنيفات.',
      ),
      AppTourStep(
        target: anchors.bankMessages,
        tab: settingsTab,
        title: 'رسائل البنك',
        body:
            'من هنا تنسخ رسائل البنك وتحوّلها لحركات على المصادر، وتعمل قواعد عشان الرسائل الجاية تتقرأ لوحدها.',
      ),
      AppTourStep(
        target: anchors.backup,
        tab: settingsTab,
        title: 'النسخ الاحتياطي',
        body:
            'صدّر نسخة من بياناتك أو ارجّع نسخة قديمة. التطبيق كمان بيحفظ نسخة لوحده لما تفتحه.',
      ),
      AppTourStep(
        target: anchors.replay,
        tab: settingsTab,
        title: 'إعادة الجولة',
        body: 'لو حابب الشرح تاني في أي وقت، الخانة دي بترجّع الجولة من الأول.',
      ),
    ];
  }
}

class AppTourStore {
  static const seenKey = 'app_tour_seen_v1';

  static Future<bool> hasSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(seenKey) ?? false;
  }

  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(seenKey, true);
  }
}

class AppTourOverlay extends StatefulWidget {
  final AppTourStep step;
  final int index;
  final int total;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onSkip;

  const AppTourOverlay({
    super.key,
    required this.step,
    required this.index,
    required this.total,
    required this.onNext,
    required this.onBack,
    required this.onSkip,
  });

  @override
  State<AppTourOverlay> createState() => _AppTourOverlayState();
}

class _AppTourOverlayState extends State<AppTourOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  Rect? _hole;
  bool _revealed = false;
  int _revealAttempts = 0;
  bool _trackQueued = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _queueTrack();
    _tryReveal();
  }

  @override
  void didUpdateWidget(covariant AppTourOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index ||
        oldWidget.step.target != widget.step.target) {
      _hole = null;
      _revealed = false;
      _revealAttempts = 0;
      _tryReveal();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _queueTrack() {
    if (_trackQueued) return;
    _trackQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _trackQueued = false;
      if (!mounted) return;
      _updateHole();
      _queueTrack();
    });
  }

  void _tryReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _revealed) return;
      final target = widget.step.target;
      if (target == null) {
        _revealed = true;
        return;
      }
      final targetContext = target.currentContext;
      if (targetContext == null) {
        _revealAttempts++;
        if (_revealAttempts < 40) _tryReveal();
        return;
      }
      _revealed = true;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.18,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _updateHole() {
    final target = widget.step.target;
    if (target == null) {
      if (_hole != null) setState(() => _hole = null);
      return;
    }

    final targetContext = target.currentContext;
    final overlayBox = context.findRenderObject();
    if (targetContext == null ||
        overlayBox is! RenderBox ||
        !overlayBox.hasSize) {
      return;
    }

    final targetBox = targetContext.findRenderObject();
    if (targetBox is! RenderBox ||
        !targetBox.attached ||
        !targetBox.hasSize ||
        targetBox.size.isEmpty) {
      return;
    }

    final topLeft = overlayBox.globalToLocal(
      targetBox.localToGlobal(Offset.zero),
    );
    final pad = targetBox.size.shortestSide < 64 ? 10.0 : 6.0;
    final next = (topLeft & targetBox.size).inflate(pad);
    if (_sameRect(_hole, next)) return;
    setState(() => _hole = next);
  }

  bool _sameRect(Rect? a, Rect? b) {
    if (a == null || b == null) return a == null && b == null;
    return (a.left - b.left).abs() < 0.5 &&
        (a.top - b.top).abs() < 0.5 &&
        (a.width - b.width).abs() < 0.5 &&
        (a.height - b.height).abs() < 0.5;
  }

  String get _primaryLabel {
    if (widget.index == 0) return 'يلا نبدأ';
    if (widget.index >= widget.total - 1) return 'خلّصنا';
    return 'التالي';
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        widget.total == 0 ? 0.0 : (widget.index + 1) / widget.total;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (widget.index == 0) {
          widget.onSkip();
        } else {
          widget.onBack();
        }
      },
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Colors.transparent),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _TourDimPainter(hole: _hole, pulse: _pulse),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          _positionCard(context, progress),
        ],
      ),
    );
  }

  Widget _positionCard(BuildContext context, double progress) {
    final size = MediaQuery.sizeOf(context);
    final padding = MediaQuery.paddingOf(context);
    final card = _buildCard(context, progress);
    final hole = _hole;

    if (hole == null && widget.step.target == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            padding.top + 16,
            16,
            padding.bottom + 16,
          ),
          child: card,
        ),
      );
    }

    if (hole == null) {
      return Positioned(
        left: 16,
        right: 16,
        bottom: padding.bottom + 16,
        child: card,
      );
    }

    final spaceAbove = hole.top - padding.top;
    final spaceBelow = size.height - hole.bottom - padding.bottom;
    final placeBelow = spaceBelow >= 170 || spaceBelow >= spaceAbove;
    final available = (placeBelow ? spaceBelow : spaceAbove) - 24;
    final maxHeight = available.clamp(96.0, 340.0);
    final bounded = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: card,
    );

    if (placeBelow) {
      return Positioned(
        left: 16,
        right: 16,
        top: hole.bottom + 12,
        child: bounded,
      );
    }

    return Positioned(
      left: 16,
      right: 16,
      bottom: size.height - hole.top + 12,
      child: bounded,
    );
  }

  Widget _buildCard(BuildContext context, double progress) {
    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppConstants.primarySurface,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'جولة تعريفية',
                      style: TextStyle(
                        color: AppConstants.primaryColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${widget.index + 1} من ${widget.total}',
                    style: const TextStyle(
                      color: AppConstants.textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  color: AppConstants.primaryColor,
                  backgroundColor: AppConstants.primarySurface,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.step.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                widget.step.body,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.45, fontSize: 15),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: widget.onSkip,
                    child: const Text('تخطي'),
                  ),
                  const Spacer(),
                  if (widget.index > 0) ...[
                    TextButton(
                      onPressed: widget.onBack,
                      child: const Text('رجوع'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppConstants.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: widget.onNext,
                    child: Text(_primaryLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TourDimPainter extends CustomPainter {
  final Rect? hole;
  final Animation<double> pulse;

  _TourDimPainter({required this.hole, required this.pulse})
    : super(repaint: pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final layer = Offset.zero & size;
    canvas.saveLayer(layer, Paint());
    canvas.drawRect(
      layer,
      Paint()..color = const Color(0xFF101410).withValues(alpha: 0.68),
    );

    final spot = hole;
    if (spot != null) {
      final radius = Radius.circular(spot.shortestSide < 72 ? 14 : 18);
      final rrect = RRect.fromRectAndRadius(spot, radius);
      canvas.drawRRect(rrect, Paint()..blendMode = BlendMode.clear);

      final t = pulse.value;
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 + (t * 1.6)
          ..color = AppConstants.primaryLight.withValues(
            alpha: 0.55 + (t * 0.45),
          ),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TourDimPainter oldDelegate) =>
      oldDelegate.hole != hole;
}
