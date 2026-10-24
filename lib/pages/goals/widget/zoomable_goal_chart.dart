import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money_traker/constants/app_constants.dart';
import 'package:money_traker/model/goal.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/store/money_storage.dart';

enum GoalChartMode { lineChart, histogram }

class GoalDayProgress {
  final DateTime date;
  final double progress;
  final double dailyDelta;

  GoalDayProgress({
    required this.date,
    required this.progress,
    required this.dailyDelta,
  });
}

class ZoomableGoalChart extends StatefulWidget {
  final Goal goal;
  final GoalChartMode initialMode;

  const ZoomableGoalChart({
    super.key,
    required this.goal,
    this.initialMode = GoalChartMode.lineChart,
  });

  @override
  State<ZoomableGoalChart> createState() => _ZoomableGoalChartState();
}

class _ZoomableGoalChartState extends State<ZoomableGoalChart> with TickerProviderStateMixin {
  late GoalChartMode _mode;
  double _zoomLevel = 1.0;
  double _panOffset = 0.0;

  static const double _minZoom = 1.0;
  static const double _maxZoom = 10.0;

  double _baseZoom = 1.0;
  double _focalX = 0.0;

  AnimationController? _resetController;
  AnimationController? _flingController;

  int? _hoverIndex;

  final MoneyStorage _storage = MoneyStorage();
  bool _loading = true;
  List<GoalDayProgress> _dayProgress = [];

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _loadGoalProgress();
  }

  Future<void> _loadGoalProgress() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final cycle = widget.goal.currentCycle().range;
      final db = await _storage.database;
      final excludedIds = widget.goal.excludedTagIds.toSet();

      // Get all days in the cycle
      final allDaysQuery = await db.rawQuery('''
        SELECT DISTINCT date FROM total_money_days
        WHERE date >= ? AND date < ?
        ORDER BY date
      ''', [cycle.start.toIso8601String(), cycle.end.toIso8601String()]);

      final dayProgress = <GoalDayProgress>[];
      double cumulativeProgress = 0;

      for (final dayRow in allDaysQuery) {
        final dateStr = dayRow['date'] as String;
        final date = DateTime.parse(dateStr);
        final dateOnly = DateTime(date.year, date.month, date.day);
        final nextDay = dateOnly.add(const Duration(days: 1));

        // Get entries for this specific day
        final dayEntries = await db.rawQuery('''
          SELECT e.amount, e.tagId, t.type
          FROM total_money_day_delta_entries e
          JOIN tags t ON t.id = e.tagId
          JOIN total_money_days d ON d.id = e.dayId
          WHERE d.date >= ? AND d.date < ?
        ''', [dateOnly.toIso8601String(), nextDay.toIso8601String()]);

        double dailyDelta = 0;

        for (final entry in dayEntries) {
          final tagId = entry['tagId'] as int;
          if (excludedIds.contains(tagId)) continue;

          final type = TagTypeDb.fromDb(entry['type'] as String);
          final amount = (entry['amount'] as num).toDouble();

          if (widget.goal.direction == GoalDirection.spendingLimit) {
            if (type == TagType.expense) {
              dailyDelta += amount;
            }
          } else {
            // savingsTarget
            if (type == TagType.income) {
              dailyDelta += amount;
            } else if (type == TagType.expense) {
              dailyDelta -= amount;
            }
          }
        }

        cumulativeProgress += dailyDelta;

        dayProgress.add(GoalDayProgress(
          date: dateOnly,
          progress: cumulativeProgress,
          dailyDelta: dailyDelta,
        ));
      }

      if (!mounted) return;
      setState(() {
        _dayProgress = dayProgress;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading goal progress: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

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

  void _toggleMode() {
    setState(() {
      _mode = _mode == GoalChartMode.lineChart ? GoalChartMode.histogram : GoalChartMode.lineChart;
    });
  }

  double get _visibleRangeRatio => 1.0 / _zoomLevel;
  double get _maxPanOffset => math.max(0.0, 1.0 - _visibleRangeRatio);

  @override
  void dispose() {
    _resetController?.dispose();
    _stopFling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_dayProgress.isEmpty) {
      return SizedBox(
        height: 300,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.trending_up, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                'No activity yet',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final totalDurationMs = math.max(1, _dayProgress.last.date.difference(_dayProgress.first.date).inMilliseconds);
    final visibleDurationMs = (totalDurationMs * _visibleRangeRatio).toInt();
    final visibleStart = _dayProgress.first.date.add(Duration(milliseconds: (totalDurationMs * _panOffset).toInt()));
    final visibleEnd = visibleStart.add(Duration(milliseconds: visibleDurationMs));

    String rangeLabel() {
      if (_zoomLevel <= 1.001) return 'Full period';
      final days = visibleEnd.difference(visibleStart).inDays.abs();
      if (days <= 7) return 'Last $days days';
      if (days <= 30) return '$days days';
      return '${DateFormat.MMM().format(visibleStart)} - ${DateFormat.MMM().format(visibleEnd)}';
    }

    final visibleData = _dayProgress.where((d) {
      final dayOnly = DateTime(d.date.year, d.date.month, d.date.day);
      return dayOnly.isAfter(visibleStart.subtract(const Duration(days: 1))) && dayOnly.isBefore(visibleEnd.add(const Duration(days: 1)));
    }).toList();

    return Column(
      children: [
        // Header with mode toggle and controls
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Goal Progress',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      rangeLabel(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(_mode == GoalChartMode.lineChart ? Icons.timeline : Icons.bar_chart),
                onPressed: _toggleMode,
                tooltip: _mode == GoalChartMode.lineChart ? 'Switch to histogram' : 'Switch to line chart',
              ),
              if (_zoomLevel > 1.01)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _resetZoom,
                  tooltip: 'Reset zoom',
                ),
            ],
          ),
        ),
        // Chart
        LayoutBuilder(
          builder: (ctx, c) {
            return GestureDetector(
              onScaleStart: (details) {
                _baseZoom = _zoomLevel;
                _focalX = details.localFocalPoint.dx / c.maxWidth;
              },
              onScaleUpdate: (details) {
                _stopFling();

                final newZoom = (_baseZoom / details.scale).clamp(_minZoom, _maxZoom);
                final focalRatio = _focalX;
                final oldVisibleRatio = 1.0 / _baseZoom;
                final newVisibleRatio = 1.0 / newZoom;

                setState(() {
                  _zoomLevel = newZoom;
                  _panOffset = (focalRatio - focalRatio * (newVisibleRatio / oldVisibleRatio)).clamp(0.0, _maxPanOffset);
                  _hoverIndex = null;
                });
              },
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: c.maxWidth * math.max(1.0, _zoomLevel),
                  height: 300,
                  child: _mode == GoalChartMode.lineChart
                      ? _buildLineChart(visibleData, visibleStart, visibleEnd, c.maxWidth)
                      : _buildHistogram(visibleData, visibleStart, visibleEnd, c.maxWidth),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLineChart(List<GoalDayProgress> data, DateTime visibleStart, DateTime visibleEnd, double width) {
    if (data.isEmpty) {
      return const Center(child: Text('No data'));
    }

    return CustomPaint(
      painter: _LineChartPainter(
        data: data,
        goal: widget.goal,
        visibleStart: visibleStart,
        visibleEnd: visibleEnd,
        hoverIndex: _hoverIndex,
        onHover: (index) {
          setState(() => _hoverIndex = index);
        },
      ),
      size: Size(width * math.max(1.0, _zoomLevel), 300),
    );
  }

  Widget _buildHistogram(List<GoalDayProgress> data, DateTime visibleStart, DateTime visibleEnd, double width) {
    if (data.isEmpty) {
      return const Center(child: Text('No data'));
    }

    return CustomPaint(
      painter: _HistogramPainter(
        data: data,
        goal: widget.goal,
        visibleStart: visibleStart,
        visibleEnd: visibleEnd,
        hoverIndex: _hoverIndex,
        onHover: (index) {
          setState(() => _hoverIndex = index);
        },
      ),
      size: Size(width * math.max(1.0, _zoomLevel), 300),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<GoalDayProgress> data;
  final Goal goal;
  final DateTime visibleStart;
  final DateTime visibleEnd;
  final int? hoverIndex;
  final Function(int?) onHover;

  _LineChartPainter({
    required this.data,
    required this.goal,
    required this.visibleStart,
    required this.visibleEnd,
    required this.hoverIndex,
    required this.onHover,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 40.0;
    final chartWidth = size.width - padding * 2;
    final chartHeight = size.height - padding * 2;

    // Draw background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    if (data.isEmpty) return;

    // Calculate min/max for progress
    final allProgress = data.map((d) => d.progress).toList();
    final minProgress = allProgress.reduce((a, b) => a < b ? a : b);
    final maxProgress = allProgress.reduce((a, b) => a > b ? a : b);
    final progressRange = (maxProgress - minProgress).abs();
    final safeRange = progressRange > 0 ? progressRange : 1.0;

    // Filter visible data
    final visibleData = data.where((d) {
      final dayOnly = DateTime(d.date.year, d.date.month, d.date.day);
      return dayOnly.isAfter(visibleStart.subtract(const Duration(days: 1))) &&
          dayOnly.isBefore(visibleEnd.add(const Duration(days: 1)));
    }).toList();

    if (visibleData.isEmpty) return;

    final totalDuration = visibleEnd.difference(visibleStart).inDays.abs().toDouble();

    // Draw grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFFF0F0F0)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = padding + (chartHeight / 4) * i;
      canvas.drawLine(Offset(padding, y), Offset(size.width - padding, y), gridPaint);
    }

    // Draw target line
    if (goal.targetAmount > 0) {
      final targetY = padding + chartHeight - ((goal.targetAmount - minProgress) / safeRange * chartHeight);
      final targetPaint = Paint()
        ..color = Colors.orange
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(padding, targetY),
        Offset(size.width - padding, targetY),
        targetPaint,
      );
    }

    // Draw line chart
    final linePaint = Paint()
      ..color = AppConstants.primaryColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPath = Path()..moveTo(padding, size.height - padding);

    for (int i = 0; i < visibleData.length; i++) {
      final d = visibleData[i];
      final daysFromStart = d.date.difference(visibleStart).inDays.toDouble();
      final x = padding + (daysFromStart / totalDuration) * chartWidth;
      final y = padding + chartHeight - ((d.progress - minProgress) / safeRange * chartHeight);

      if (i == 0) {
        fillPath.lineTo(x, y);
      } else {
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width - padding, size.height - padding);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..color = AppConstants.primaryColor.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill,
    );

    // Re-draw line
    for (int i = 0; i < visibleData.length; i++) {
      final d = visibleData[i];
      final daysFromStart = d.date.difference(visibleStart).inDays.toDouble();
      final x = padding + (daysFromStart / totalDuration) * chartWidth;
      final y = padding + chartHeight - ((d.progress - minProgress) / safeRange * chartHeight);

      if (i > 0) {
        final prevD = visibleData[i - 1];
        final prevDaysFromStart = prevD.date.difference(visibleStart).inDays.toDouble();
        final prevX = padding + (prevDaysFromStart / totalDuration) * chartWidth;
        final prevY = padding + chartHeight - ((prevD.progress - minProgress) / safeRange * chartHeight);
        canvas.drawLine(Offset(prevX, prevY), Offset(x, y), linePaint);
      }
    }

    // Draw points
    for (int i = 0; i < visibleData.length; i++) {
      final d = visibleData[i];
      final daysFromStart = d.date.difference(visibleStart).inDays.toDouble();
      final x = padding + (daysFromStart / totalDuration) * chartWidth;
      final y = padding + chartHeight - ((d.progress - minProgress) / safeRange * chartHeight);

      canvas.drawCircle(
        Offset(x, y),
        hoverIndex == i ? 6 : 4,
        Paint()..color = AppConstants.primaryColor,
      );
    }

    // Draw axes labels
    final labelPaint = TextPainter(textDirection: ui.TextDirection.ltr)
      ..text = TextSpan(
        text: DateFormat('MMM d').format(visibleStart),
        style: const TextStyle(color: Colors.grey, fontSize: 10),
      )
      ..layout();
    labelPaint.paint(canvas, Offset(padding - 20, size.height - 25));

    final endLabelPaint = TextPainter(textDirection: ui.TextDirection.ltr)
      ..text = TextSpan(
        text: DateFormat('MMM d').format(visibleEnd),
        style: const TextStyle(color: Colors.grey, fontSize: 10),
      )
      ..layout();
    endLabelPaint.paint(canvas, Offset(size.width - padding - 20, size.height - 25));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _HistogramPainter extends CustomPainter {
  final List<GoalDayProgress> data;
  final Goal goal;
  final DateTime visibleStart;
  final DateTime visibleEnd;
  final int? hoverIndex;
  final Function(int?) onHover;

  _HistogramPainter({
    required this.data,
    required this.goal,
    required this.visibleStart,
    required this.visibleEnd,
    required this.hoverIndex,
    required this.onHover,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 40.0;
    final chartWidth = size.width - padding * 2;
    final chartHeight = size.height - padding * 2;

    // Draw background
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    if (data.isEmpty) return;

    // Calculate min/max for daily delta
    final allDeltas = data.map((d) => d.dailyDelta).toList();
    final minDelta = allDeltas.reduce((a, b) => a < b ? a : b);
    final maxDelta = allDeltas.reduce((a, b) => a > b ? a : b);
    final deltaRange = (maxDelta - minDelta).abs();
    final safeRange = deltaRange > 0 ? deltaRange : 1.0;

    // Filter visible data
    final visibleData = data.where((d) {
      final dayOnly = DateTime(d.date.year, d.date.month, d.date.day);
      return dayOnly.isAfter(visibleStart.subtract(const Duration(days: 1))) &&
          dayOnly.isBefore(visibleEnd.add(const Duration(days: 1)));
    }).toList();

    if (visibleData.isEmpty) return;

    final totalDuration = visibleEnd.difference(visibleStart).inDays.abs().toDouble();
    final barWidth = (chartWidth / (totalDuration + 1)) * 0.8;

    // Draw grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFFF0F0F0)
      ..strokeWidth = 1;

    for (int i = 0; i <= 4; i++) {
      final y = padding + (chartHeight / 4) * i;
      canvas.drawLine(Offset(padding, y), Offset(size.width - padding, y), gridPaint);
    }

    // Draw zero line
    final zeroY = padding + chartHeight - ((0 - minDelta) / safeRange * chartHeight);
    canvas.drawLine(
      Offset(padding, zeroY),
      Offset(size.width - padding, zeroY),
      Paint()
        ..color = Colors.grey[300]!
        ..strokeWidth = 1,
    );

    // Draw bars
    for (int i = 0; i < visibleData.length; i++) {
      final d = visibleData[i];
      final daysFromStart = d.date.difference(visibleStart).inDays.toDouble();
      final x = padding + (daysFromStart / totalDuration) * chartWidth;
      final barHeight = (d.dailyDelta / safeRange) * chartHeight;
      final y = padding + chartHeight - barHeight;

      final color = d.dailyDelta >= 0 ? AppConstants.primaryColor : Colors.red;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - barWidth / 2, y, barWidth, barHeight.abs()),
          const Radius.circular(2),
        ),
        Paint()
          ..color = color.withValues(alpha: hoverIndex == i ? 1.0 : 0.7)
          ..style = PaintingStyle.fill,
      );
    }

    // Draw labels
    final textPainter = TextPainter(textDirection: ui.TextDirection.ltr);
    textPainter.text = TextSpan(
      text: DateFormat('MMM d').format(visibleStart),
      style: const TextStyle(color: Colors.grey, fontSize: 10),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(padding - 20, size.height - 25));

    textPainter.text = TextSpan(
      text: DateFormat('MMM d').format(visibleEnd),
      style: const TextStyle(color: Colors.grey, fontSize: 10),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(size.width - padding - 20, size.height - 25));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}







