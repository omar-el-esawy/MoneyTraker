import 'package:flutter/material.dart';
import 'package:money_traker/model/total_money_day.dart';
import 'package:money_traker/model/total_money_day_delta_entry.dart';
import 'package:money_traker/store/money_storage.dart';
import 'widget/history_chart.dart';
import 'package:money_traker/constants/app_constants.dart';
import 'logic/history_logic.dart';
import '../widgets/note_popup.dart';
import 'widget/compare_delta_chart.dart';
import 'day_delta_tagging_sheet.dart';
import 'logic/day_delta_logic.dart';
import 'widget/day_delta_badge.dart';
import 'package:money_traker/pages/widgets/obscurable_amount.dart';
import 'package:money_traker/tour/app_tour.dart';

class HistoryPage extends StatefulWidget {
  final List<TotalMoneyDay> historyDays;
  final bool showAmounts;

  const HistoryPage({
    super.key,
    required this.historyDays,
    this.showAmounts = true,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late List<TotalMoneyDay> _historyDays;
  final MoneyStorage _storage = MoneyStorage();
  Map<int, DayDeltaCategorySummary> _deltaSummariesByDayId = {};

  bool _compareMode = false;
  int? _pickedFirstIndex; // index in _historyDays (sorted asc)
  int? _pickedSecondIndex;

  @override
  void initState() {
    super.initState();
    _historyDays = List<TotalMoneyDay>.from(widget.historyDays);

    // Work with a consistently sorted list.
    _historyDays.sort((a, b) => a.date.compareTo(b.date));
    _loadDeltaSummaries();
  }

  @override
  void didUpdateWidget(covariant HistoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // HomePage can refresh its in-memory history list when returning to this tab.
    // Keep this page in sync so updated notes appear immediately.
    if (!identical(oldWidget.historyDays, widget.historyDays)) {
      _historyDays = List<TotalMoneyDay>.from(widget.historyDays)
        ..sort((a, b) => a.date.compareTo(b.date));
      _loadDeltaSummaries();
    }
  }

  Future<void> _loadDeltaSummaries() async {
    final ids = _historyDays
        .where((d) => d.id != null)
        .map((d) => d.id!)
        .toList(growable: false);
    final summaries = await _storage.getDeltaSummariesForDays(ids);
    if (!mounted) return;
    setState(() => _deltaSummariesByDayId = summaries);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _formatDateShort(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  void _toggleCompareMode() {
    if (_historyDays.length < 2) return;
    setState(() {
      _compareMode = !_compareMode;
      _pickedFirstIndex = null;
      _pickedSecondIndex = null;
    });
  }

  void _cancelCompare() {
    setState(() {
      _compareMode = false;
      _pickedFirstIndex = null;
      _pickedSecondIndex = null;
    });
  }

  Color _cardBorderColor(BuildContext context) {
    // Soft border for light surfaces.
    return const Color(0xFFE5E7EB);
  }

  Color _cardOnSurface(BuildContext context) {
    // Dark text for light cards.
    return const Color(0xFF111827);
  }

  Color _cardOnSurfaceMuted(BuildContext context) {
    return const Color(0xFF6B7280);
  }

  Color _selectionColor(BuildContext context, bool selected) {
    // Keep a modern light look even in dark mode.
    // Slight tint for selected items.
    return selected ? const Color(0xFFE9EEF4) : const Color(0xFFF3F4F6);
  }

  Future<void> _openDeltaTagging(int sortedIndex) async {
    if (sortedIndex < 0 || sortedIndex >= _historyDays.length) return;

    final day = _historyDays[sortedIndex];
    if (day.id == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This day is not saved yet.')),
      );
      return;
    }

    // For the very first day there is no previous snapshot, so use its full
    // total as the baseline delta to enable category tagging.
    final delta =
        sortedIndex == 0
            ? day.totalAmount
            : dayDelta(_historyDays, sortedIndex);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder:
          (ctx) => DayDeltaTaggingSheet(
            dayId: day.id!,
            delta: delta,
            entryDate: day.date,
            showAmounts: widget.showAmounts,
          ),
    );

    await _loadDeltaSummaries();
  }

  Future<void> _handleHistoryTap({
    required int sortedIndex,
    required int displayIndex,
    required TotalMoneyDay item,
  }) async {
    if (!_compareMode) {
      // New behavior: open delta tagging editor (difference vs previous day)
      // but keep note editing via long-press.
      await _openDeltaTagging(sortedIndex);
      return;
    }

    setState(() {
      if (_pickedFirstIndex == null) {
        _pickedFirstIndex = sortedIndex;
        return;
      }
      if (_pickedFirstIndex == sortedIndex) {
        // Allow toggling off.
        _pickedFirstIndex = null;
        _pickedSecondIndex = null;
        return;
      }

      // Pick second.
      _pickedSecondIndex = sortedIndex;
    });

    // If two picks are done, show comparison.
    if (_pickedFirstIndex != null && _pickedSecondIndex != null) {
      final a = _historyDays[_pickedFirstIndex!];
      final b = _historyDays[_pickedSecondIndex!];
      final from = a.date.isBefore(b.date) ? a : b;
      final to = a.date.isBefore(b.date) ? b : a;

      final delta = to.totalAmount - from.totalAmount;
      final sign = delta > 0 ? '+' : '';
      final Color deltaColor =
          !widget.showAmounts
              ? Colors.grey
              : (delta > 0
                  ? AppConstants.accentColor
                  : (delta < 0 ? AppConstants.errorColor : Colors.grey));

      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) {
          final fromDate = _formatDateShort(_dateOnly(from.date));
          final toDate = _formatDateShort(_dateOnly(to.date));

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.compare_arrows),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Comparison',
                          style: Theme.of(ctx).textTheme.titleLarge,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$fromDate → $toDate',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  CompareDeltaChart(
                    fromValue: from.totalAmount,
                    toValue: to.totalAmount,
                    showAmounts: widget.showAmounts,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ObscurableAmount(
                                amount:
                                    'From: ${from.totalAmount.toStringAsFixed(2)}',
                                visible: widget.showAmounts,
                                style: Theme.of(ctx).textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 4),
                              ObscurableAmount(
                                amount:
                                    'To: ${to.totalAmount.toStringAsFixed(2)}',
                                visible: widget.showAmounts,
                                style: Theme.of(ctx).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'Δ Difference',
                              style: Theme.of(
                                ctx,
                              ).textTheme.labelLarge?.copyWith(
                                color:
                                    Theme.of(ctx).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            ObscurableAmount(
                              amount: '$sign${delta.toStringAsFixed(2)}',
                              visible: widget.showAmounts,
                              textAlign: TextAlign.end,
                              style: Theme.of(
                                ctx,
                              ).textTheme.headlineSmall?.copyWith(
                                color: deltaColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      // Reset picks but keep compare mode on so user can compare again quickly.
      if (mounted) {
        setState(() {
          _pickedFirstIndex = null;
          _pickedSecondIndex = null;
        });
      }
    }
  }

  Future<void> _editNote(
    BuildContext context,
    int sortedIndex,
    TotalMoneyDay item,
  ) async {
    final newNote = await showDialog<String>(
      context: context,
      builder: (context) => NotePopup(initialNote: item.note),
    );
    if (newNote != null && newNote != item.note) {
      final updated = TotalMoneyDay(
        id: item.id,
        date: item.date,
        totalAmount: item.totalAmount,
        note: newNote,
      );
      await MoneyStorage().updateTotalMoneyDay(updated);
      setState(() {
        // _historyDays is sorted ascending, and sortedIndex matches its indexing.
        _historyDays[sortedIndex] = updated;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCompare = _historyDays.length >= 2;
    final tour = AppTourScope.maybeOf(context);

    return Scaffold(
      backgroundColor: AppConstants.backgroundColor,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'History',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    KeyedSubtree(
                      key: tour?.compareDays,
                      child:
                          _compareMode
                              ? TextButton.icon(
                                onPressed: _cancelCompare,
                                icon: const Icon(Icons.close),
                                label: const Text('Cancel'),
                              )
                              : IconButton(
                                tooltip:
                                    canCompare
                                        ? 'Compare days'
                                        : 'Need at least 2 days',
                                onPressed:
                                    canCompare ? _toggleCompareMode : null,
                                icon: const Icon(Icons.compare_arrows),
                              ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: KeyedSubtree(
                  key: tour?.historyChart,
                  child: HistoryChart(
                    historyDays: _historyDays,
                    showAmounts: widget.showAmounts,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  // We display newest first.
                  final sortedIndex = _historyDays.length - 1 - index;
                  final item = _historyDays[sortedIndex];
                  final date = item.date;

                  final isSelected =
                      (_pickedFirstIndex == sortedIndex) ||
                      (_pickedSecondIndex == sortedIndex);

                  Color amountColor = _cardOnSurface(context);
                  if (widget.showAmounts &&
                      _historyDays.length > 1 &&
                      index < _historyDays.length - 1) {
                    final prev = _historyDays[_historyDays.length - index - 2];
                    final change = getChangeType(prev, item);
                    if (change == ChangeType.increase) {
                      amountColor = AppConstants.accentColor;
                    } else if (change == ChangeType.decrease) {
                      amountColor = AppConstants.errorColor;
                    } else {
                      amountColor = _cardOnSurface(context);
                    }
                  }

                  // Make date compact (no time) to reduce clutter.
                  final dateOnly = _dateOnly(date);
                  final dateTitle = _formatDateShort(dateOnly);

                  // Keep time as muted small text (optional).
                  final timeText =
                      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

                  final delta = dayDelta(_historyDays, sortedIndex);
                  final bool showDelta = !_compareMode && sortedIndex > 0;
                  final summary =
                      item.id == null ? null : _deltaSummariesByDayId[item.id!];
                  final hasCategories =
                      summary != null && summary.hasAnyCategory;

                  final tileIconColor =
                      isSelected
                          ? const Color(0xFF2563EB)
                          : _cardOnSurfaceMuted(context);

                  final card = AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap:
                          () => _handleHistoryTap(
                            sortedIndex: sortedIndex,
                            displayIndex: index,
                            item: item,
                          ),
                      onLongPress:
                          _compareMode
                              ? null
                              : () => _editNote(context, sortedIndex, item),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: _selectionColor(context, isSelected),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _cardBorderColor(context)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 10,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top row: date + (optional) delta chip / compare indicator
                            Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _cardBorderColor(context),
                                    ),
                                  ),
                                  child: Icon(
                                    _compareMode
                                        ? (isSelected
                                            ? Icons.check_circle
                                            : Icons.circle_outlined)
                                        : Icons.calendar_today,
                                    size: 18,
                                    color: tileIconColor,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dateTitle,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium?.copyWith(
                                          color: _cardOnSurface(context),
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        timeText,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.copyWith(
                                          color: _cardOnSurfaceMuted(context),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (showDelta)
                                  DayDeltaBadge(
                                    delta: delta,
                                    showAmount: widget.showAmounts,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // Total row (big, clean)
                            Row(
                              children: [
                                Text(
                                  'Total',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodyMedium?.copyWith(
                                    color: _cardOnSurfaceMuted(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const Spacer(),
                                ObscurableAmount(
                                  amount: item.totalAmount.toStringAsFixed(2),
                                  visible: widget.showAmounts,
                                  textAlign: TextAlign.end,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.headlineSmall?.copyWith(
                                    color: amountColor,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),

                            if (item.note != null &&
                                item.note!.trim().isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.55),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _cardBorderColor(context),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.notes,
                                      size: 16,
                                      color: _cardOnSurfaceMuted(context),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item.note!.trim(),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.copyWith(
                                          color: _cardOnSurface(context),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            if (hasCategories) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  if (summary.totalIncome > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            widget.showAmounts
                                                ? const Color(0xFFE8F5E9)
                                                : const Color(0xFFF3F4F6),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: ObscurableAmount(
                                        amount:
                                            '+${summary.totalIncome.toStringAsFixed(2)}',
                                        visible: widget.showAmounts,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall?.copyWith(
                                          color:
                                              widget.showAmounts
                                                  ? const Color(0xFF1B5E20)
                                                  : const Color(0xFF6B7280),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  if (summary.totalIncome > 0 &&
                                      summary.totalExpenses > 0)
                                    const SizedBox(width: 6),
                                  if (summary.totalExpenses > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            widget.showAmounts
                                                ? const Color(0xFFFFEBEE)
                                                : const Color(0xFFF3F4F6),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: ObscurableAmount(
                                        amount:
                                            '-${summary.totalExpenses.toStringAsFixed(2)}',
                                        visible: widget.showAmounts,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.labelSmall?.copyWith(
                                          color:
                                              widget.showAmounts
                                                  ? const Color(0xFFD32F2F)
                                                  : const Color(0xFF6B7280),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  const Spacer(),
                                  Text(
                                    '${summary.totalCategories} categories',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall?.copyWith(
                                      color: _cardOnSurfaceMuted(context),
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Icon(
                                  _compareMode ? Icons.touch_app : Icons.edit,
                                  size: 16,
                                  color: _cardOnSurfaceMuted(context),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _compareMode
                                        ? 'Tap to select'
                                        : (hasCategories
                                            ? 'Tap to edit categories • Long press to edit note'
                                            : 'Tap to categorize • Long press to edit note'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall?.copyWith(
                                      color: _cardOnSurfaceMuted(context),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                  if (index != 0) return card;
                  return KeyedSubtree(key: tour?.historyDay, child: card);
                }, childCount: _historyDays.length),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
