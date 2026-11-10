import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:intl/intl.dart';
import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/model/total_money_day.dart';

class ZoomableBalanceChart extends StatefulWidget {
  final List<TotalMoneyDay> historyDays;
  final bool showAmounts;

  const ZoomableBalanceChart({
    super.key,
    required this.historyDays,
    this.showAmounts = true,
  });

  @override
  State<ZoomableBalanceChart> createState() => _ZoomableBalanceChartState();
}

class _ZoomableBalanceChartState extends State<ZoomableBalanceChart>
    with TickerProviderStateMixin {
  // 1.0 shows the full history. Higher values show a shorter window.
  double _zoomLevel = 1.0;
  double _panOffset = 0.0; // normalized 0..max

  static const double _minZoom = 1.0;
  static const int _defaultWindowDays = 30;
  static const int _minWindowDays = 2;

  /// True after the user pinches, pans, or uses the zoom buttons.
  bool _userAdjusted = false;

  double _baseZoom = 1.0;

  AnimationController? _resetController;

  AnimationController? _flingController;

  // Tooltip
  int? _hoverIndex;

  double _startPan = 0.0;

  int get _totalDurationMs {
    final data = _sorted;
    if (data.length < 2) return 1;
    return math.max(
      1,
      data.last.date.difference(data.first.date).inMilliseconds,
    );
  }

  /// Zoom that frames the latest [_defaultWindowDays], or all history when shorter.
  double get _defaultZoom {
    final total = _totalDurationMs;
    final windowMs = const Duration(days: _defaultWindowDays).inMilliseconds;
    if (_sorted.length < 2 || windowMs >= total) return _minZoom;
    return total / windowMs;
  }

  double get _defaultPan {
    final visible = 1.0 / _defaultZoom;
    return math.max(0.0, 1.0 - visible);
  }

  /// Allows zooming in to about [_minWindowDays], and always past the default window.
  double get _maxZoom {
    final total = _totalDurationMs;
    final minWindowMs = const Duration(days: _minWindowDays).inMilliseconds;
    final zoomForMinWindow = total / minWindowMs;
    return math.max(4.0, math.max(_defaultZoom, zoomForMinWindow));
  }

  bool get _isDefaultView {
    final zoomTol = math.max(0.02, _defaultZoom * 0.02);
    return (_zoomLevel - _defaultZoom).abs() <= zoomTol &&
        (_panOffset - _defaultPan).abs() <= 0.015;
  }

  void _applyDefaultViewport() {
    _zoomLevel = _defaultZoom;
    _panOffset = _defaultPan;
  }

  bool _spanChanged(List<TotalMoneyDay> previous, List<TotalMoneyDay> next) {
    if (previous.length != next.length) return true;
    if (previous.isEmpty || next.isEmpty) return false;
    int earliest(List<TotalMoneyDay> days) =>
        days.map((d) => d.date.millisecondsSinceEpoch).reduce(math.min);
    int latest(List<TotalMoneyDay> days) =>
        days.map((d) => d.date.millisecondsSinceEpoch).reduce(math.max);
    return earliest(previous) != earliest(next) ||
        latest(previous) != latest(next);
  }

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

  void _stopReset() {
    _resetController?.stop();
    _resetController?.dispose();
    _resetController = null;
  }

  void _resetZoom() {
    _stopFling();
    _stopReset();

    final targetZoom = _defaultZoom;
    final targetPan = _defaultPan;
    if ((_zoomLevel - targetZoom).abs() < 0.001 &&
        (_panOffset - targetPan).abs() < 0.001) {
      _userAdjusted = false;
      return;
    }

    _resetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    final zoomAnim = Tween<double>(begin: _zoomLevel, end: targetZoom).animate(
      CurvedAnimation(parent: _resetController!, curve: Curves.easeOutCubic),
    );
    final panAnim = Tween<double>(begin: _panOffset, end: targetPan).animate(
      CurvedAnimation(parent: _resetController!, curve: Curves.easeOutCubic),
    );

    _resetController!.addListener(() {
      setState(() {
        _zoomLevel = zoomAnim.value;
        _panOffset = panAnim.value;
        _hoverIndex = null;
      });
    });
    _resetController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _userAdjusted = false;
      }
    });

    _resetController!.forward(from: 0);
  }

  /// [factor] > 1 zooms in. The newest date currently in view stays put.
  void _zoomBy(double factor) {
    _stopFling();
    _stopReset();
    _userAdjusted = true;

    final newZoom = (_zoomLevel * factor).clamp(_minZoom, _maxZoom).toDouble();
    final newVisible = 1.0 / newZoom;
    // Keep the newest visible date pinned so zooming stays on the latest days.
    final rightEdge = _panOffset + (1.0 / _zoomLevel);
    final newPan = (rightEdge - newVisible)
        .clamp(0.0, math.max(0.0, 1.0 - newVisible))
        .toDouble();

    setState(() {
      _zoomLevel = newZoom;
      _panOffset = newPan;
      _hoverIndex = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _applyDefaultViewport();
  }

  @override
  void didUpdateWidget(covariant ZoomableBalanceChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_userAdjusted ||
        !_spanChanged(oldWidget.historyDays, widget.historyDays)) {
      return;
    }
    _applyDefaultViewport();
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
        showReset: false,
        onReset: null,
        onZoomIn: null,
        onZoomOut: null,
        child: const _EmptyChart(),
      );
    }

    final totalDurationMs = _totalDurationMs;
    final canZoomOut = _zoomLevel > _minZoom + 0.001;
    final canZoomIn = _zoomLevel < _maxZoom - 0.001;

    return LayoutBuilder(
      builder: (ctx, c) {
        // chart drawing area (inside card padding)
        const double chartHeight = 180;
        const double xLabelHeight = 18;
        final chartWidth = math.max(
          1.0,
          c.maxWidth - 40,
        ); // card has 20 padding left/right

        final painter = _BalanceChartPainter(
          data: data,
          zoomLevel: _zoomLevel,
          panOffset: _panOffset,
          chartSize: Size(chartWidth, chartHeight),
          hoverIndex: _hoverIndex,
          showDots:
              (totalDurationMs / _zoomLevel) <=
              const Duration(days: 45).inMilliseconds,
          showAmounts: widget.showAmounts,
        );

        void updateHover(Offset localPos) {
          setState(() {
            _hoverIndex = painter.hitTestIndex(localPos);
          });
        }

        return _ChartCard(
          showReset: !_isDefaultView,
          onReset: _isDefaultView ? null : _resetZoom,
          onZoomIn: canZoomIn ? () => _zoomBy(1.6) : null,
          onZoomOut: canZoomOut ? () => _zoomBy(1 / 1.6) : null,
          child: Column(
            children: [
              RepaintBoundary(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: _resetZoom,
                  onScaleStart: (d) {
                    _stopFling();
                    _stopReset();
                    _userAdjusted = true;
                    _baseZoom = _zoomLevel;
                    _startPan = _panOffset;
                  },
                  onScaleUpdate: (d) {
                    // Two-finger => zoom. One-finger => drag when zoomed in.
                    if (d.pointerCount >= 2) {
                      final newZoom = (_baseZoom * d.scale).clamp(
                        _minZoom,
                        _maxZoom,
                      );

                      final localX = d.localFocalPoint.dx;

                      final prevVisible = 1.0 / _zoomLevel;
                      final newVisible = 1.0 / newZoom;

                      // normalized data position under the finger before zoom
                      final focalFraction = painter.xToVisibleFraction(localX);
                      final focalDataPos =
                          _startPan + focalFraction * prevVisible;

                      var newPan = focalDataPos - focalFraction * newVisible;
                      newPan = newPan.clamp(
                        0.0,
                        math.max(0.0, 1.0 - newVisible),
                      );

                      setState(() {
                        _zoomLevel = newZoom;
                        _panOffset = newPan;
                        _hoverIndex = null;
                      });
                    } else {
                      if (_zoomLevel <= 1.001) return;
                      final panDelta =
                          -d.focalPointDelta.dx /
                          painter.plotWidth *
                          _visibleRangeRatio;
                      setState(() {
                        _panOffset = (_panOffset + panDelta).clamp(
                          0.0,
                          _maxPanOffset,
                        );
                        _hoverIndex = null;
                      });
                    }
                  },
                  onScaleEnd: (d) {
                    if (_zoomLevel <= 1.001) return;
                    final v =
                        -d.velocity.pixelsPerSecond.dx /
                        painter.plotWidth *
                        _visibleRangeRatio;
                    if (v.abs() < 0.0001) return;

                    _flingController?.dispose();
                    _flingController = AnimationController.unbounded(
                      vsync: this,
                    );

                    final sim = FrictionSimulation(0.135, _panOffset, v);
                    _flingController!.animateWith(sim);
                    _flingController!.addListener(() {
                      setState(() {
                        _panOffset = _flingController!.value.clamp(
                          0.0,
                          _maxPanOffset,
                        );
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
                        foregroundPainter:
                            _hoverIndex == null || !widget.showAmounts
                            ? null
                            : _TooltipPainter(
                                data: data,
                                painter: painter,
                                hoverIndex: _hoverIndex!,
                                showAmounts: widget.showAmounts,
                              ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        height: xLabelHeight,
                        width: chartWidth,
                        child: CustomPaint(
                          size: Size(chartWidth, xLabelHeight),
                          painter: _XAxisLabelsPainter(painter: painter),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 3,
                child: _MiniMap(zoomLevel: _zoomLevel, panOffset: _panOffset),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    size: 13,
                    color: AppConstants.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      'Pinch to zoom · drag to explore · double-tap to reset',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppConstants.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
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
  final bool showReset;
  final VoidCallback? onReset;
  final VoidCallback? onZoomIn;
  final VoidCallback? onZoomOut;

  const _ChartCard({
    required this.child,
    required this.showReset,
    required this.onReset,
    required this.onZoomIn,
    required this.onZoomOut,
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
              Flexible(
                child: Text(
                  'Balance Trend',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppConstants.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ZoomIconButton(
                tooltip: 'Zoom out',
                icon: Icons.remove,
                onPressed: onZoomOut,
              ),
              const SizedBox(width: 4),
              _ZoomIconButton(
                tooltip: 'Zoom in',
                icon: Icons.add,
                onPressed: onZoomIn,
              ),
              if (showReset) ...[
                const SizedBox(width: 4),
                _ZoomIconButton(
                  tooltip: 'Reset zoom',
                  icon: Icons.refresh,
                  onPressed: onReset,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ZoomIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  const _ZoomIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: enabled ? AppConstants.primarySurface : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(
              icon,
              size: 16,
              color: enabled
                  ? AppConstants.primaryColor
                  : const Color(0xFFB0B0B0),
            ),
          ),
        ),
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
  final bool showAmounts;

  _BalanceChartPainter({
    required this.data,
    required this.zoomLevel,
    required this.panOffset,
    required this.chartSize,
    required this.hoverIndex,
    required this.showDots,
    required this.showAmounts,
  });

  late final DateTime _start = data.first.date;
  late final DateTime _end = data.last.date;

  late final int _totalDurationMs = math.max(
    1,
    _end.difference(_start).inMilliseconds,
  );

  late final double _minY;
  late final double _maxY;

  double get plotLeft => showAmounts ? 44.0 : 8.0;
  double get plotRight => chartSize.width - 10.0;
  double get plotTop => 8.0;
  double get plotBottom => chartSize.height - 8.0;
  double get plotWidth => math.max(1.0, plotRight - plotLeft);
  double get plotHeight => math.max(1.0, plotBottom - plotTop);
  Rect get plotRect => Rect.fromLTRB(plotLeft, plotTop, plotRight, plotBottom);

  double xToVisibleFraction(double x) {
    return ((x - plotLeft) / plotWidth).clamp(0.0, 1.0);
  }

  void _computeYRange() {
    var first = 0;
    var last = data.length - 1;
    if (data.length > 1) {
      final start = visibleStart;
      final end = visibleEnd;
      while (first < data.length && data[first].date.isBefore(start)) {
        first++;
      }
      while (last >= 0 && data[last].date.isAfter(end)) {
        last--;
      }
      if (first > last) {
        first = 0;
        last = data.length - 1;
      } else {
        first = (first - 1).clamp(0, data.length - 1);
        last = (last + 1).clamp(0, data.length - 1);
      }
    }

    double minV = data[first].totalAmount;
    double maxV = minV;
    for (var i = first; i <= last; i++) {
      minV = math.min(minV, data[i].totalAmount);
      maxV = math.max(maxV, data[i].totalAmount);
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
    _lastVisibleStart = _start.add(
      Duration(milliseconds: (_totalDurationMs * panOffset).toInt()),
    );
    return _lastVisibleStart;
  }

  DateTime get visibleEnd {
    _lastVisibleEnd = visibleStart.add(
      Duration(milliseconds: (_totalDurationMs * _visibleRatio).toInt()),
    );
    return _lastVisibleEnd;
  }

  DateTime get debugVisibleStart => _lastVisibleStart;
  DateTime get debugVisibleEnd => _lastVisibleEnd;

  double dateToX(DateTime date) {
    final normalized =
        date.difference(_start).inMilliseconds / _totalDurationMs;
    final x = plotLeft + ((normalized - panOffset) / _visibleRatio * plotWidth);
    return x;
  }

  double valueToY(double v) {
    final n = (v - _minY) / (_maxY - _minY);
    return plotBottom - (n * plotHeight);
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
      if (d.date.isBefore(start.subtract(const Duration(days: 1))) ||
          d.date.isAfter(end.add(const Duration(days: 1)))) {
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

    if (!showAmounts) return;

    canvas.save();
    canvas.clipRect(plotRect.inflate(5));

    // Visible points with 1 padding point before/after
    final points = _visiblePointsWithPadding();

    if (points.isEmpty) {
      canvas.restore();
      return;
    }

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
      ..lineTo(points.last.dx, plotBottom)
      ..lineTo(points.first.dx, plotBottom)
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
      final outer = Paint()
        ..color = AppConstants.primaryColor.withValues(alpha: 0.2);
      final inner = Paint()..color = AppConstants.primaryColor;
      canvas.drawCircle(Offset(x, y), 8, outer);
      canvas.drawCircle(Offset(x, y), 4, inner);
    }
    canvas.restore();
  }

  List<Offset> _visiblePointsWithPadding() {
    if (data.length == 1) {
      return [Offset(plotLeft + plotWidth / 2, plotTop + plotHeight / 2)];
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

    final textStyle = const TextStyle(
      fontSize: 10,
      color: Color(0xFF9CA3AF),
      fontWeight: FontWeight.w400,
    );

    for (int i = 0; i < yTicks; i++) {
      final t = i / (yTicks - 1);
      final y = plotBottom - (plotHeight * t);

      dash.drawDashedLine(
        canvas,
        Offset(plotLeft, y),
        Offset(plotRight, y),
        gridPaint,
      );

      if (showAmounts) {
        final val = _minY + (_maxY - _minY) * t;
        final label = _formatCompact(val);
        final tp = TextPainter(
          text: TextSpan(text: label, style: textStyle),
          textDirection: ui.TextDirection.ltr,
        )..layout();

        final labelY = (y - tp.height / 2).clamp(
          0.0,
          chartSize.height - tp.height,
        );
        tp.paint(canvas, Offset(plotLeft - tp.width - 6, labelY));
      }
    }

    // X grid lines only (labels are painted in a separate painter below)
    final rangeDays = visibleEnd.difference(visibleStart).inDays.abs();
    final xTicks = (rangeDays < 7) ? math.max(2, rangeDays + 1) : 5;

    for (int i = 0; i < xTicks; i++) {
      final t = i / (xTicks - 1);
      final x = plotLeft + (plotWidth * t);
      dash.drawDashedLine(
        canvas,
        Offset(x, plotTop),
        Offset(x, plotBottom),
        gridPaint,
      );
    }
  }

  String _formatCompact(double v) {
    final abs = v.abs();
    if (abs >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}m';
    if (abs >= 1000) {
      return '${(v / 1000).toStringAsFixed(abs % 1000 == 0 ? 0 : 1)}k';
    }
    return v.toStringAsFixed(0);
  }

  @override
  bool shouldRepaint(covariant _BalanceChartPainter oldDelegate) {
    return oldDelegate.zoomLevel != zoomLevel ||
        oldDelegate.panOffset != panOffset ||
        oldDelegate.data.length != data.length ||
        oldDelegate.hoverIndex != hoverIndex ||
        oldDelegate.showDots != showDots ||
        oldDelegate.showAmounts != showAmounts;
  }
}

class _TooltipPainter extends CustomPainter {
  final List<TotalMoneyDay> data;
  final _BalanceChartPainter painter;
  final int hoverIndex;
  final bool showAmounts;

  _TooltipPainter({
    required this.data,
    required this.painter,
    required this.hoverIndex,
    required this.showAmounts,
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
    dash.drawDashedLine(
      canvas,
      Offset(x, painter.plotTop),
      Offset(x, painter.plotBottom),
      linePaint,
    );

    // tooltip
    final nf = NumberFormat('#,##0.00');
    final amount = showAmounts ? nf.format(d.totalAmount) : '••••';
    final dateStr = DateFormat('MMM dd, yyyy · HH:mm').format(d.date);

    final titleStyle = const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );
    final subStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w400,
      color: Colors.white.withValues(alpha: 0.7),
    );

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

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, w, h),
      const Radius.circular(8),
    );

    canvas.drawRRect(rrect, Paint()..color = const Color(0xFF1A1A2E));

    tp1.paint(canvas, Offset(left + padX, top + padY));
    tp2.paint(canvas, Offset(left + padX, top + padY + tp1.height + 2));
  }

  @override
  bool shouldRepaint(covariant _TooltipPainter oldDelegate) {
    return oldDelegate.hoverIndex != hoverIndex ||
        oldDelegate.data.length != data.length ||
        oldDelegate.showAmounts != showAmounts;
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

    final textStyle = const TextStyle(
      fontSize: 10,
      color: Color(0xFF9CA3AF),
      fontWeight: FontWeight.w400,
    );

    for (int i = 0; i < xTicks; i++) {
      final t = i / (xTicks - 1);
      final x = painter.plotLeft + (painter.plotWidth * t);
      final dt = start.add(
        Duration(
          milliseconds: ((end.difference(start).inMilliseconds) * t).toInt(),
        ),
      );
      final label = fmt.format(dt);

      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: ui.TextDirection.ltr,
      )..layout(maxWidth: 80);

      final left = (x - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(left, 0));
    }
  }

  @override
  bool shouldRepaint(covariant _XAxisLabelsPainter oldDelegate) {
    return true;
  }
}
