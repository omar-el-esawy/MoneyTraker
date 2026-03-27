import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:intl/intl.dart';
import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/model/total_money_day.dart';

class ZoomableBalanceChart extends StatefulWidget {
  final List<TotalMoneyDay> historyDays;

  const ZoomableBalanceChart({
    super.key,
    required this.historyDays,
  });

  @override
  State<ZoomableBalanceChart> createState() => _ZoomableBalanceChartState();
}

class _ZoomableBalanceChartState extends State<ZoomableBalanceChart> with TickerProviderStateMixin {
  // zoom 1.0 = show full duration
  double _zoomLevel = 1.0;
  double _panOffset = 0.0; // normalized 0..max

  static const double _minZoom = 1.0;
  static const double _maxZoom = 10.0;

  double _baseZoom = 1.0;
  double _focalX = 0.0;

  AnimationController? _resetController;

  AnimationController? _flingController;

  // Tooltip
  int? _hoverIndex;

  double _startPan = 0.0;

  List<TotalMoneyDay> get _sorted {
    final s = [...widget.historyDays]..sort((a, b) => a.date.compareTo(b.date));
    return s;
  }

  double get _visibleRangeRatio => 1.0 / _zoomLevel;
  double get _maxPanOffset => math.max(0.0, 1.0 - _visibleRangeRatio);

  void _stopFling() {
    _flingController?.stop();
    _flingController?.dispose();
    _flingController = null;
  }

  void _resetZoom() {
    _stopFling();

    _resetController?.dispose();
    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    final zoomAnim = Tween<double>(begin: _zoomLevel, end: 1.0).animate(
      CurvedAnimation(parent: _resetController!, curve: Curves.easeOutCubic),
    );
    final panAnim = Tween<double>(begin: _panOffset, end: 0.0).animate(
      CurvedAnimation(parent: _resetController!, curve: Curves.easeOutCubic),
    );

    _resetController!.addListener(() {
      setState(() {
        _zoomLevel = zoomAnim.value;
        _panOffset = panAnim.value;
        _hoverIndex = null;
      });
    });

    _resetController!.forward(from: 0);
  }

  @override
  void dispose() {
    _resetController?.dispose();
    _stopFling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _sorted;

    // Empty state
    if (data.isEmpty) {
      return _ChartCard(
        zoomLevel: 1.0,
        showReset: false,
        rangeLabel: 'All time',
        onReset: null,
        child: const _EmptyChart(),
      );
    }

    final totalDurationMs = math.max(1, data.last.date.difference(data.first.date).inMilliseconds);

    final visibleDurationMs = (totalDurationMs * _visibleRangeRatio).toInt();
    final visibleStart = data.first.date.add(Duration(milliseconds: (totalDurationMs * _panOffset).toInt()));
    final visibleEnd = visibleStart.add(Duration(milliseconds: visibleDurationMs));

    String rangeLabel() {
      if (_zoomLevel <= 1.001) return 'All time';
      final days = visibleEnd.difference(visibleStart).inDays.abs();
      if (days <= 7) return 'Last $days days';
      if (days <= 30) return '$days days';
      return '${DateFormat.MMM().format(visibleStart)} - ${DateFormat.MMM().format(visibleEnd)}';
    }

    return LayoutBuilder(
      builder: (ctx, c) {
        // chart drawing area (inside card padding)
        const double chartHeight = 180;
        const double xLabelHeight = 18;
        final chartWidth = math.max(1.0, c.maxWidth - 40); // card has 20 padding left/right

        final painter = _BalanceChartPainter(
          data: data,
          zoomLevel: _zoomLevel,
          panOffset: _panOffset,
          chartSize: Size(chartWidth, chartHeight),
          hoverIndex: _hoverIndex,
          showDots: _zoomLevel > 2.0,
        );

        void updateHover(Offset localPos) {
          setState(() {
            _hoverIndex = painter.hitTestIndex(localPos);
          });
        }

        return _ChartCard(
          zoomLevel: _zoomLevel,
          showReset: _zoomLevel > 1.001,
          rangeLabel: rangeLabel(),
          onReset: _zoomLevel > 1.001 ? _resetZoom : null,
          child: Column(
            children: [
              RepaintBoundary(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _resetZoom,
                  onScaleStart: (d) {
                    _stopFling();
                    _baseZoom = _zoomLevel;
                    _startPan = _panOffset;
                    _focalX = d.focalPoint.dx;
                  },
                  onScaleUpdate: (d) {
                    // Two-finger => zoom. One-finger => drag when zoomed in.
                    if (d.pointerCount >= 2) {
                      final newZoom = (_baseZoom * d.scale).clamp(_minZoom, _maxZoom);

                      final localX = (context.findRenderObject() is RenderBox)
                          ? (context.findRenderObject() as RenderBox).globalToLocal(d.focalPoint).dx
                          : _focalX;

                      final prevVisible = 1.0 / _zoomLevel;
                      final newVisible = 1.0 / newZoom;

                      // normalized data position under the finger before zoom
                      final focalDataPos = _startPan + (localX / chartWidth) * prevVisible;

                      var newPan = focalDataPos - (localX / chartWidth) * newVisible;
                      newPan = newPan.clamp(0.0, math.max(0.0, 1.0 - newVisible));

                      setState(() {
                        _zoomLevel = newZoom;
                        _panOffset = newPan;
                        _hoverIndex = null;
                      });
                    } else {
                      if (_zoomLevel <= 1.001) return;
                      final panDelta = -d.focalPointDelta.dx / chartWidth * _visibleRangeRatio;
                      setState(() {
                        _panOffset = (_panOffset + panDelta).clamp(0.0, _maxPanOffset);
                        _hoverIndex = null;
                      });
                    }
                  },
                  onScaleEnd: (d) {
                    if (_zoomLevel <= 1.001) return;
                    final v = -d.velocity.pixelsPerSecond.dx / chartWidth * _visibleRangeRatio;
                    if (v.abs() < 0.0001) return;

                    _flingController?.dispose();
                    _flingController = AnimationController.unbounded(vsync: this);

                    final sim = FrictionSimulation(0.135, _panOffset, v);
                    _flingController!.animateWith(sim);
                    _flingController!.addListener(() {
                      setState(() {
                        _panOffset = _flingController!.value.clamp(0.0, _maxPanOffset);
                      });
                    });
                  },
                  onLongPressStart: (d) => updateHover(d.localPosition),
                  onLongPressMoveUpdate: (d) => updateHover(d.localPosition),
                  onLongPressEnd: (_) => setState(() {
                    _hoverIndex = null;
                  }),
                  onTapDown: (d) => updateHover(d.localPosition),
                  onTapUp: (_) {},
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Paint only inside the chart viewport.
                      CustomPaint(
                        size: Size(chartWidth, chartHeight),
                        painter: painter,
                        foregroundPainter: _hoverIndex == null
                            ? null
                            : _TooltipPainter(
                                data: data,
                                painter: painter,
                                hoverIndex: _hoverIndex!,
                              ),
                      ),
                      // Reserve space for x-axis labels so we don't overflow.
                      SizedBox(
                        height: xLabelHeight,
                        width: chartWidth,
                        child: CustomPaint(
                          size: Size(chartWidth, xLabelHeight),
                          painter: _XAxisLabelsPainter(
                            painter: painter,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 3,
                child: _MiniMap(
                  zoomLevel: _zoomLevel,
                  panOffset: _panOffset,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChartCard extends StatelessWidget {
  final Widget child;
  final double zoomLevel;
  final bool showReset;
  final String rangeLabel;
  final VoidCallback? onReset;

  const _ChartCard({
    required this.child,
    required this.zoomLevel,
    required this.showReset,
    required this.rangeLabel,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(20),
      // Removed fixed height to prevent overflows on small devices.
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF0F0F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(
                'Balance Trend',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppConstants.textSecondary,
                    ),
              ),
              const Spacer(),
              if (showReset)
                InkWell(
                  onTap: onReset,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.zoom_out_map, size: 12, color: Color(0xFFE65100)),
                        const SizedBox(width: 4),
                        Text(
                          'Reset',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: const Color(0xFFE65100),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppConstants.primarySurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  rangeLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppConstants.primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            // Fixed chart area: 180 (chart) + 18 (x labels) + 8 (gap) + 3 (minimap)
            height: 209,
            child: Stack(
              children: [
                Align(alignment: Alignment.centerLeft, child: child),
                if (zoomLevel > 1.001)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E).withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.zoom_in, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            '${zoomLevel.toStringAsFixed(1)}x',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMap extends StatelessWidget {
  final double zoomLevel;
  final double panOffset;

  const _MiniMap({required this.zoomLevel, required this.panOffset});

  @override
  Widget build(BuildContext context) {
    final visibleRatio = 1.0 / zoomLevel;
    final maxPan = math.max(0.0, 1.0 - visibleRatio);
    final left = maxPan == 0 ? 0.0 : (panOffset / maxPan);

    return LayoutBuilder(
      builder: (ctx, c) {
        final w = c.maxWidth;
        final indicatorW = w * visibleRatio;
        final indicatorLeft = (w - indicatorW) * left;

        return Container(
          width: double.infinity,
          height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F0F0),
            borderRadius: BorderRadius.circular(1.5),
          ),
          child: Stack(
            children: [
              Positioned(
                left: indicatorLeft,
                child: Container(
                  width: indicatorW,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppConstants.primaryColor,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.show_chart, size: 48, color: Color(0xFFD0D0D0)),
          const SizedBox(height: 12),
          Text(
            'No history yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppConstants.textTertiary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _BalanceChartPainter extends CustomPainter {
  final List<TotalMoneyDay> data;
  final double zoomLevel;
  final double panOffset;
  final Size chartSize;
  final int? hoverIndex;
  final bool showDots;

  _BalanceChartPainter({
    required this.data,
    required this.zoomLevel,
    required this.panOffset,
    required this.chartSize,
    required this.hoverIndex,
    required this.showDots,
  });

  late final DateTime _start = data.first.date;
  late final DateTime _end = data.last.date;

  late final int _totalDurationMs = math.max(1, _end.difference(_start).inMilliseconds);

  late final double _minY;
  late final double _maxY;

  void _computeYRange() {
    double minV = data.first.totalAmount;
    double maxV = data.first.totalAmount;
    for (final d in data) {
      minV = math.min(minV, d.totalAmount);
      maxV = math.max(maxV, d.totalAmount);
    }
    if ((maxV - minV).abs() < 0.00001) {
      // flat line
      minV = minV * 0.95;
      maxV = maxV * 1.05;
      if ((maxV - minV).abs() < 0.00001) {
        maxV = minV + 1;
      }
    } else {
      final pad = (maxV - minV) * 0.05;
      minV -= pad;
      maxV += pad;
    }

    _minY = minV;
    _maxY = maxV;
  }

  double get _visibleRatio => 1.0 / zoomLevel;

  late DateTime _lastVisibleStart;
  late DateTime _lastVisibleEnd;

  DateTime get visibleStart {
    _lastVisibleStart = _start.add(Duration(milliseconds: (_totalDurationMs * panOffset).toInt()));
    return _lastVisibleStart;
  }

  DateTime get visibleEnd {
    _lastVisibleEnd = visibleStart.add(Duration(milliseconds: (_totalDurationMs * _visibleRatio).toInt()));
    return _lastVisibleEnd;
  }

  DateTime get debugVisibleStart => _lastVisibleStart;
  DateTime get debugVisibleEnd => _lastVisibleEnd;

  double dateToX(DateTime date) {
    final normalized = date.difference(_start).inMilliseconds / _totalDurationMs;
    final x = (normalized - panOffset) / _visibleRatio * chartSize.width;
    return x;
  }

  double valueToY(double v) {
    final n = (v - _minY) / (_maxY - _minY);
    return chartSize.height - (n * chartSize.height);
  }

  int? hitTestIndex(Offset p) {
    if (data.length <= 1) return 0;
    final start = visibleStart;
    final end = visibleEnd;

    // Find nearest visible point.
    int? best;
    double bestDist = double.infinity;
    for (int i = 0; i < data.length; i++) {
      final d = data[i];
      if (d.date.isBefore(start.subtract(const Duration(days: 1))) || d.date.isAfter(end.add(const Duration(days: 1)))) {
        continue;
      }
      final x = dateToX(d.date);
      final y = valueToY(d.totalAmount);
      final dist = (Offset(x, y) - p).distance;
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }

    return best;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _computeYRange();

    // Grid + axes
    _drawGrid(canvas);

    // Visible points with 1 padding point before/after
    final points = _visiblePointsWithPadding();

    if (points.isEmpty) return;

    // Line path
    final path = Path();
    for (int i = 0; i < points.length; i++) {
      final p = points[i];
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }

    // Fill
    final fillPath = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppConstants.primaryColor.withValues(alpha: 0.15),
          AppConstants.primaryColor.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);

    canvas.drawPath(fillPath, fillPaint);

    // Stroke
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = zoomLevel > 2.0 ? 2.5 : 2.0
      ..color = AppConstants.primaryColor
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, strokePaint);

    // Dots
    if (showDots) {
      for (final p in points) {
        _drawDot(canvas, p, radius: 3);
      }
    } else {
      // last point only
      _drawDot(canvas, points.last, radius: 4);
    }

    // Hover highlight (outer/inner)
    if (hoverIndex != null && hoverIndex! >= 0 && hoverIndex! < data.length) {
      final d = data[hoverIndex!];
      final x = dateToX(d.date);
      final y = valueToY(d.totalAmount);
      final outer = Paint()..color = AppConstants.primaryColor.withValues(alpha: 0.2);
      final inner = Paint()..color = AppConstants.primaryColor;
      canvas.drawCircle(Offset(x, y), 8, outer);
      canvas.drawCircle(Offset(x, y), 4, inner);
    }
  }

  List<Offset> _visiblePointsWithPadding() {
    if (data.length == 1) {
      return [Offset(chartSize.width / 2, chartSize.height / 2)];
    }

    final start = visibleStart;
    final end = visibleEnd;

    int first = 0;
    while (first < data.length && data[first].date.isBefore(start)) {
      first++;
    }
    int last = data.length - 1;
    while (last >= 0 && data[last].date.isAfter(end)) {
      last--;
    }

    first = (first - 1).clamp(0, data.length - 1);
    last = (last + 1).clamp(0, data.length - 1);

    final out = <Offset>[];
    for (int i = first; i <= last; i++) {
      final d = data[i];
      out.add(Offset(dateToX(d.date), valueToY(d.totalAmount)));
    }
    return out;
  }

  void _drawDot(Canvas canvas, Offset p, {required double radius}) {
    final fill = Paint()..color = AppConstants.primaryColor;
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = radius == 4 ? 2 : 1.5;

    canvas.drawCircle(p, radius, fill);
    canvas.drawCircle(p, radius, border);
  }

  void _drawGrid(Canvas canvas) {
    // Horizontal labels (4-5)
    const int yTicks = 5;
    final gridPaint = Paint()
      ..color = const Color(0xFFF0F0F0)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final dash = _DashPathEffect([4, 4]);

    final textStyle = const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w400);

    for (int i = 0; i < yTicks; i++) {
      final t = i / (yTicks - 1);
      final y = chartSize.height * (1 - t);

      dash.drawDashedLine(canvas, Offset(0, y), Offset(chartSize.width, y), gridPaint);

      final val = _minY + (_maxY - _minY) * t;
      final label = _formatCompact(val);
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout();

      // draw slightly outside left (we still have card padding though)
      tp.paint(canvas, Offset(-2, y - tp.height / 2));
    }

    // X grid lines only (labels are painted in a separate painter below)
    final rangeDays = visibleEnd.difference(visibleStart).inDays.abs();
    final xTicks = (rangeDays < 7) ? math.max(2, rangeDays + 1) : 5;

    for (int i = 0; i < xTicks; i++) {
      final t = i / (xTicks - 1);
      final x = chartSize.width * t;
      dash.drawDashedLine(canvas, Offset(x, 0), Offset(x, chartSize.height), gridPaint);
    }
  }

  String _formatCompact(double v) {
    final abs = v.abs();
    if (abs >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}m';
    if (abs >= 1000) return '${(v / 1000).toStringAsFixed(abs % 1000 == 0 ? 0 : 1)}k';
    return v.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _BalanceChartPainter oldDelegate) {
    return oldDelegate.zoomLevel != zoomLevel ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.data.length != data.length ||
        oldDelegate.hoverIndex != hoverIndex ||
        oldDelegate.showDots != showDots;
  }
}

class _TooltipPainter extends CustomPainter {
  final List<TotalMoneyDay> data;
  final _BalanceChartPainter painter;
  final int hoverIndex;

  _TooltipPainter({
    required this.data,
    required this.painter,
    required this.hoverIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (hoverIndex < 0 || hoverIndex >= data.length) return;
    final d = data[hoverIndex];
    final x = painter.dateToX(d.date);
    final y = painter.valueToY(d.totalAmount);

    // dashed crosshair
    final linePaint = Paint()
      ..color = AppConstants.primaryColor.withValues(alpha: 0.4)
      ..strokeWidth = 1;

    final dash = _DashPathEffect([6, 4]);
    dash.drawDashedLine(canvas, Offset(x, 0), Offset(x, size.height), linePaint);

    // tooltip
    final nf = NumberFormat('#,##0.00');
    final amount = nf.format(d.totalAmount);
    final dateStr = DateFormat('MMM dd, yyyy · HH:mm').format(d.date);

    final titleStyle = const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white);
    final subStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: Colors.white.withValues(alpha: 0.7));

    final tp1 = TextPainter(
      text: TextSpan(text: amount, style: titleStyle),
      textDirection: ui.TextDirection.ltr,
    )..layout();
    final tp2 = TextPainter(
      text: TextSpan(text: dateStr, style: subStyle),
      textDirection: ui.TextDirection.ltr,
    )..layout();

    const padX = 12.0;
    const padY = 8.0;
    final w = math.max(tp1.width, tp2.width) + padX * 2;
    final h = tp1.height + tp2.height + padY * 2 + 2;

    // Try above point, else below
    double top = y - h - 10;
    if (top < 0) top = y + 10;

    double left = x - w / 2;
    left = left.clamp(0.0, size.width - w);

    final rrect = RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), const Radius.circular(8));

    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF1A1A2E));

    tp1.paint(canvas, Offset(left + padX, top + padY));
    tp2.paint(canvas, Offset(left + padX, top + padY + tp1.height + 2));
  }

  @override
  bool shouldRepaint(covariant _TooltipPainter oldDelegate) {
    return oldDelegate.hoverIndex != hoverIndex || oldDelegate.data.length != data.length;
  }
}

class _DashPathEffect {
  final List<double> intervals;

  const _DashPathEffect(this.intervals);

  void drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    final total = (b - a).distance;
    final dir = (b - a) / total;

    double dist = 0;
    int i = 0;

    while (dist < total) {
      final len = intervals[i % intervals.length];
      final next = math.min(dist + len, total);
      if (i.isEven) {
        canvas.drawLine(a + dir * dist, a + dir * next, paint);
      }
      dist = next;
      i++;
    }
  }
}

class _XAxisLabelsPainter extends CustomPainter {
  final _BalanceChartPainter painter;

  _XAxisLabelsPainter({required this.painter});

  @override
  void paint(Canvas canvas, Size size) {
    final start = painter.visibleStart;
    final end = painter.visibleEnd;

    final rangeDays = end.difference(start).inDays.abs();
    final xTicks = (rangeDays < 7) ? math.max(2, rangeDays + 1) : 5;

    DateFormat fmt;
    if (rangeDays < 3) {
      fmt = DateFormat('MMM dd HH:mm');
    } else if (rangeDays <= 60) {
      fmt = DateFormat('MMM dd');
    } else {
      fmt = DateFormat('MMM yyyy');
    }

    final textStyle = const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w400);

    for (int i = 0; i < xTicks; i++) {
      final t = i / (xTicks - 1);
      final x = size.width * t;
      final dt = start.add(Duration(milliseconds: ((end.difference(start).inMilliseconds) * t).toInt()));
      final label = fmt.format(dt);

      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: 80);

      tp.paint(canvas, Offset(x - tp.width / 2, 0));
    }
  }

  @override
  bool shouldRepaint(covariant _XAxisLabelsPainter oldDelegate) {
    return true;
  }
}
