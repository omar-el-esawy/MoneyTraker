import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money_traker/pages/widgets/obscurable_amount.dart';
import 'widgets/add_money_source_dialog.dart';
import 'widgets/money_source_card.dart';
import 'package:money_traker/model/mission.dart';
import 'package:money_traker/model/goal.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/store/money_storage.dart';
import 'package:money_traker/pages/goals/goal_detail_view.dart';
import 'package:money_traker/pages/goals/goals_page.dart';
import 'package:money_traker/pages/goals/logic/goal_engine.dart';
import 'package:money_traker/pages/widgets/amount_calculator_sheet.dart';
import 'package:money_traker/pages/total_money/source_history_page.dart';
import 'package:money_traker/tour/app_tour.dart';

class TotalMoneyPage extends StatefulWidget {
  final bool showAmounts;
  final ValueChanged<bool> onShowAmountsChanged;
  final Map<String, double> moneySources;
  final Map<String, int> sourceIds;
  final void Function(String, double) onAddSource;
  final void Function(String, String, double, {DateTime? effectiveDate})
  onEditSource;
  final void Function(String) onDeleteSource;

  final Future<void> Function(
    String sourceName,
    double amount, {
    String? categoryName,
    double? categoryAmount,
    DateTime? effectiveDate,
  })
  onQuickAdd;
  final Future<void> Function(
    String sourceName,
    double amount, {
    String? categoryName,
    double? categoryAmount,
    DateTime? effectiveDate,
  })
  onQuickSubtract;
  final Future<void> Function(String fromSource, String toSource, double amount)
  onTransfer;

  final Mission? mission;
  final void Function(Mission) onAddMission;

  const TotalMoneyPage({
    super.key,
    required this.showAmounts,
    required this.onShowAmountsChanged,
    required this.moneySources,
    required this.sourceIds,
    required this.onAddSource,
    required this.onEditSource,
    required this.onDeleteSource,
    required this.onQuickAdd,
    required this.onQuickSubtract,
    required this.onTransfer,
    this.mission,
    required this.onAddMission,
  });

  @override
  State<TotalMoneyPage> createState() => _TotalMoneyPageState();
}

class _TransferDraft {
  final String toSource;
  final double amount;

  const _TransferDraft({required this.toSource, required this.amount});
}

class _QuickAdjustmentDraft {
  final double amount;
  final String? categoryName;
  final double? categoryAmount;
  final DateTime? effectiveDate;

  const _QuickAdjustmentDraft({
    required this.amount,
    this.categoryName,
    this.categoryAmount,
    this.effectiveDate,
  });
}

class _TotalMoneyPageState extends State<TotalMoneyPage> {
  Mission? _mission;

  final MoneyStorage _storage = MoneyStorage();
  bool _loadingGoals = true;
  List<GoalProgress> _homeGoals = [];
  GoalProgress? _mainGoal;

  @override
  void initState() {
    super.initState();
    _mission = widget.mission;
    _loadGoals();
  }

  Future<void> _openSourceHistory(
    BuildContext context,
    String sourceName,
  ) async {
    final sourceId = widget.sourceIds[sourceName];
    if (sourceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Source history is unavailable right now.'),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (_) => SourceHistoryPage(
              sourceId: sourceId,
              sourceName: sourceName,
              showAmounts: widget.showAmounts,
            ),
      ),
    );
  }

  Future<void> _loadGoals() async {
    final goals = await _storage.getGoals(includeInactive: false);
    final engine = GoalEngine(_storage);

    final progresses = <GoalProgress>[];
    for (final g in goals.where((g) => g.isActive)) {
      progresses.add(await engine.computeProgress(g));
    }

    // Main goal (single) to be shown next to total money.
    GoalProgress? main;
    try {
      final mg = await _storage.getMainGoal();
      if (mg != null && mg.isActive) {
        main = await engine.computeProgress(mg);
      }
    } catch (_) {
      // If migration hasn't run yet or any issue occurs, just skip main goal.
      main = null;
    }

    if (!mounted) return;
    setState(() {
      _homeGoals = progresses;
      _mainGoal = main;
      _loadingGoals = false;
    });
  }

  Widget _buildMainGoalInline(BuildContext context) {
    final p = _mainGoal;
    if (p == null) return const SizedBox.shrink();

    // Remaining can become negative if exceeded.
    final remaining = p.goal.targetAmount - p.progress;
    final exceeded = remaining < 0;
    final remainingColor =
        !widget.showAmounts
            ? const Color(0xFF6B7280)
            : (exceeded ? Colors.red : const Color(0xFF6B7280));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p.goal.name,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        ObscurableAmount(
          amount: remaining.toStringAsFixed(2),
          visible: widget.showAmounts,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: remainingColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Future<void> _openGoals() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const GoalsPage()));
    // Refresh in case user edited goals.
    await _loadGoals();
  }

  Widget _buildGoalsStrip() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Text(
                'Goals',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              TextButton(onPressed: _openGoals, child: const Text('See all')),
            ],
          ),
        ),
        SizedBox(
          height: 140,
          child:
              _loadingGoals
                  ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                  : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    itemBuilder: (ctx, i) {
                      if (i == _homeGoals.length) {
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _openGoals,
                          child: Container(
                            width: 120,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFD0D0D0),
                              ),
                            ),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.add_circle_outline,
                                    size: 28,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'New Goal',
                                    style: TextStyle(
                                      color: Color(0xFF9CA3AF),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      final p = _homeGoals[i];
                      final spentMode =
                          p.goal.direction == GoalDirection.spendingLimit;
                      final cycleLabel = switch (p.goal.type) {
                        GoalType.monthly => 'Monthly',
                        GoalType.repeatingDays =>
                          '${p.goal.repeatEveryDays ?? 0} days',
                        GoalType.fixedPeriod => 'Fixed',
                      };
                      final accent =
                          spentMode
                              ? const Color(0xFFD32F2F)
                              : const Color(0xFF1B5E20);
                      final bg =
                          spentMode
                              ? const Color(0xFFFFEBEE)
                              : const Color(0xFFE8F5E9);
                      final pct = p.percent.clamp(0.0, 1.0);

                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => GoalDetailPageView(goal: p.goal),
                            ),
                          );
                          await _loadGoals();
                        },
                        child: Container(
                          width: 220,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFF0F0F0)),
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
                              Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: bg,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      spentMode
                                          ? Icons.trending_down
                                          : Icons.flag_outlined,
                                      size: 16,
                                      color: accent,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      p.goal.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    cycleLabel,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall?.copyWith(
                                      color: const Color(0xFF9CA3AF),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: widget.showAmounts ? pct : 0,
                                  minHeight: 8,
                                  backgroundColor: const Color(0xFFF0F0F0),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    widget.showAmounts
                                        ? accent
                                        : const Color(0xFFE5E7EB),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  ObscurableAmount(
                                    amount: p.progress.toStringAsFixed(2),
                                    visible: widget.showAmounts,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  ObscurableAmount(
                                    amount:
                                        ' / ${p.goal.targetAmount.toStringAsFixed(2)}',
                                    visible: widget.showAmounts,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyMedium?.copyWith(
                                      color: const Color(0xFF9CA3AF),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${p.daysRemaining}d left',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall?.copyWith(
                                      color: const Color(0xFF6B7280),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemCount: _homeGoals.length + 1,
                  ),
        ),
      ],
    );
  }

  void _toggleAmountsVisibility() {
    widget.onShowAmountsChanged(!widget.showAmounts);
  }

  void _showAddSourceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder:
          (context) => AddMoneySourceDialog(
            onAdd: (name, amount) => widget.onAddSource(name, amount),
          ),
    );
  }

  Future<void> _showEditSourceDialog(
    BuildContext context,
    String oldName,
    double oldAmount,
  ) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (context) => EditMoneySourceDialogWithMission(
            oldName: oldName,
            oldAmount: oldAmount,
            mission: _mission,
            showAmounts: widget.showAmounts,
          ),
    );
    if (result != null) {
      final String newName = result['name'];
      final double newAmount = result['amount'];
      final bool decreaseMission = result['decreaseMission'] ?? false;
      final double decrement = result['decrement'] ?? 0.0;
      final DateTime? effectiveDate = result['effectiveDate'] as DateTime?;

      widget.onEditSource(
        oldName,
        newName,
        newAmount,
        effectiveDate: effectiveDate,
      );

      // Only decrease mission.targetAmount if user confirmed and mission exists
      if (_mission != null && decreaseMission && decrement > 0) {
        setState(() {
          _mission = Mission(
            id: _mission!.id,
            name: _mission!.name,
            targetAmount: _mission!.targetAmount - decrement,
            startDate: _mission!.startDate,
            endDate: _mission!.endDate,
          );
        });
        widget.onAddMission(_mission!); // Save updated mission
      }
    }
  }

  void _showDeleteConfirmationDialog(BuildContext context, String sourceName) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete Money Source'),
            content: Text('Are you sure you want to delete "$sourceName"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  widget.onDeleteSource(sourceName);
                  Navigator.of(context).pop();
                },
                child: const Text('Delete'),
              ),
            ],
          ),
    );
  }

  Future<_QuickAdjustmentDraft?> _showQuickAdjustmentDialog(
    BuildContext context, {
    required bool isAdd,
    required String sourceName,
    required double currentAmount,
  }) async {
    final amount = await showAmountCalculatorSheet(
      context,
      title: isAdd ? 'Add amount' : 'Subtract amount',
      maxAmount: isAdd ? null : currentAmount,
      allowZero: false,
      announceMax: widget.showAmounts,
    );
    if (amount == null) return null;

    final type = isAdd ? TagType.income : TagType.expense;
    final tags = await _storage.getTags(type: type);
    final categoryNames =
        tags.map((e) => e.name).toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (!context.mounted) return null;

    bool categorize = false;
    bool customCategory = categoryNames.isEmpty;
    String? selectedCategory =
        categoryNames.isEmpty ? null : categoryNames.first;
    final categoryController = TextEditingController();
    double? customCategoryAmount;
    bool backdate = false;
    DateTime selectedDate = DateTime.now();

    final draft = await showDialog<_QuickAdjustmentDraft>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setLocal) => AlertDialog(
                  title: Text(
                    isAdd ? 'Add to $sourceName' : 'Subtract from $sourceName',
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Amount: ${amount.toStringAsFixed(2)}'),
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          value: categorize,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Categorize this change (optional)',
                          ),
                          onChanged:
                              (v) => setLocal(() => categorize = v ?? false),
                        ),
                        if (categorize) ...[
                          const SizedBox(height: 8),
                          if (categoryNames.isNotEmpty)
                            DropdownButtonFormField<String>(
                              initialValue:
                                  customCategory
                                      ? '__custom__'
                                      : selectedCategory,
                              decoration: const InputDecoration(
                                labelText: 'Category',
                              ),
                              items: [
                                ...categoryNames.map(
                                  (n) => DropdownMenuItem(
                                    value: n,
                                    child: Text(n),
                                  ),
                                ),
                                const DropdownMenuItem(
                                  value: '__custom__',
                                  child: Text('Custom...'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setLocal(() {
                                  customCategory = v == '__custom__';
                                  if (!customCategory) {
                                    selectedCategory = v;
                                  }
                                });
                              },
                            ),
                          if (customCategory) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: categoryController,
                              decoration: const InputDecoration(
                                labelText: 'Category name',
                              ),
                              autofocus: categoryNames.isEmpty,
                            ),
                          ],
                          const SizedBox(height: 12),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              final v = await showAmountCalculatorSheet(
                                ctx,
                                title: 'Category amount',
                                initialValue: customCategoryAmount,
                                maxAmount: amount,
                                allowZero: false,
                              );
                              if (v == null) return;
                              setLocal(() => customCategoryAmount = v);
                            },
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Category amount (optional)',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                customCategoryAmount == null
                                    ? 'Tap to set (defaults to full amount)'
                                    : customCategoryAmount!.toStringAsFixed(2),
                                style: TextStyle(
                                  color:
                                      customCategoryAmount == null
                                          ? Theme.of(ctx).hintColor
                                          : Theme.of(
                                            ctx,
                                          ).textTheme.bodyLarge?.color,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          value: backdate,
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Log this change to a different date',
                          ),
                          subtitle: const Text(
                            'Choose if this was a late entry (backdate)',
                          ),
                          onChanged:
                              (v) => setLocal(() => backdate = v ?? false),
                        ),
                        if (backdate) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  DateFormat('yyyy-MM-dd').format(selectedDate),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.calendar_today),
                                onPressed: () async {
                                  final now = DateTime.now();
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: selectedDate,
                                    firstDate: DateTime(now.year - 3),
                                    lastDate: DateTime(
                                      now.year,
                                      now.month,
                                      now.day,
                                    ),
                                  );
                                  if (picked != null)
                                    setLocal(() => selectedDate = picked);
                                },
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        String? categoryName;
                        if (categorize) {
                          categoryName =
                              customCategory
                                  ? categoryController.text.trim()
                                  : selectedCategory;
                          if (categoryName == null || categoryName.isEmpty)
                            return;
                        }

                        Navigator.of(ctx).pop(
                          _QuickAdjustmentDraft(
                            amount: amount,
                            categoryName: categoryName,
                            categoryAmount:
                                categorize
                                    ? (customCategoryAmount ?? amount)
                                    : null,
                            effectiveDate: backdate ? selectedDate : null,
                          ),
                        );
                      },
                      child: const Text('Save'),
                    ),
                  ],
                ),
          ),
    );

    categoryController.dispose();
    return draft;
  }

  Future<void> _showQuickActionsSheet(
    BuildContext context, {
    required String sourceName,
    required double currentAmount,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + MediaQuery.of(sheetCtx).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sourceName,
                    style: Theme.of(sheetCtx).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  ObscurableAmount(
                    amount: 'Current: ${currentAmount.toStringAsFixed(2)}',
                    visible: widget.showAmounts,
                    style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(sheetCtx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('Add amount'),
                    subtitle: const Text('Increase this source by a number'),
                    onTap: () async {
                      final draft = await _showQuickAdjustmentDialog(
                        sheetCtx,
                        isAdd: true,
                        sourceName: sourceName,
                        currentAmount: currentAmount,
                      );
                      if (draft == null) return;
                      await widget.onQuickAdd(
                        sourceName,
                        draft.amount,
                        categoryName: draft.categoryName,
                        categoryAmount: draft.categoryAmount,
                        effectiveDate: draft.effectiveDate,
                      );
                      if (!sheetCtx.mounted) return;
                      Navigator.of(sheetCtx).pop();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.remove_circle_outline),
                    title: const Text('Subtract amount'),
                    subtitle: const Text('Decrease this source by a number'),
                    onTap: () async {
                      final draft = await _showQuickAdjustmentDialog(
                        sheetCtx,
                        isAdd: false,
                        sourceName: sourceName,
                        currentAmount: currentAmount,
                      );
                      if (draft == null) return;
                      await widget.onQuickSubtract(
                        sourceName,
                        draft.amount,
                        categoryName: draft.categoryName,
                        categoryAmount: draft.categoryAmount,
                        effectiveDate: draft.effectiveDate,
                      );
                      if (!sheetCtx.mounted) return;
                      Navigator.of(sheetCtx).pop();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: const Text('Transfer to another source'),
                    subtitle: const Text(
                      'Move money from this source to another',
                    ),
                    onTap: () async {
                      final didTransfer = await _showTransferDialog(
                        sheetCtx,
                        fromSource: sourceName,
                        fromCurrentAmount: currentAmount,
                      );
                      if (didTransfer != true) return;
                      if (!sheetCtx.mounted) return;
                      Navigator.of(sheetCtx).pop();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.show_chart),
                    title: const Text('View source history'),
                    subtitle: const Text(
                      'Graph and cards for this source changes',
                    ),
                    onTap: () async {
                      await _openSourceHistory(sheetCtx, sourceName);
                    },
                  ),
                  const Divider(height: 20),
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('Edit name/amount'),
                    onTap: () async {
                      await _showEditSourceDialog(
                        sheetCtx,
                        sourceName,
                        currentAmount,
                      );
                      if (!sheetCtx.mounted) return;
                      Navigator.of(sheetCtx).pop();
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: Theme.of(sheetCtx).colorScheme.error,
                    ),
                    title: Text(
                      'Delete source',
                      style: TextStyle(
                        color: Theme.of(sheetCtx).colorScheme.error,
                      ),
                    ),
                    subtitle: const Text('Remove this money source'),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: sheetCtx,
                        builder:
                            (ctx) => AlertDialog(
                              title: const Text('Delete Money Source'),
                              content: Text(
                                'Are you sure you want to delete "$sourceName"?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                      );

                      if (confirmed == true) {
                        widget.onDeleteSource(sourceName);
                        if (!sheetCtx.mounted) return;
                        Navigator.of(sheetCtx).pop();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _showTransferDialog(
    BuildContext context, {
    required String fromSource,
    required double fromCurrentAmount,
  }) async {
    final targets =
        widget.moneySources.keys.where((k) => k != fromSource).toList()..sort();
    if (targets.isEmpty) return null;

    String toSource = targets.first;

    final res = await showDialog<_TransferDraft>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Transfer'),
            content: StatefulBuilder(
              builder:
                  (ctx, setLocal) => DropdownButtonFormField<String>(
                    initialValue: toSource,
                    decoration: const InputDecoration(labelText: 'To'),
                    items:
                        targets
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setLocal(() => toSource = v);
                    },
                  ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final amount = await showAmountCalculatorSheet(
                    ctx,
                    title: 'Amount',
                    maxAmount: fromCurrentAmount,
                    allowZero: false,
                    announceMax: widget.showAmounts,
                  );
                  if (amount == null) return;
                  if (!ctx.mounted) return;
                  Navigator.of(
                    ctx,
                  ).pop(_TransferDraft(toSource: toSource, amount: amount));
                },
                child: const Text('Enter amount'),
              ),
            ],
          ),
    );

    if (res == null) return false;
    try {
      await widget.onTransfer(fromSource, res.toSource, res.amount);
      return true;
    } catch (e) {
      if (!context.mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Transfer failed: $e')));
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.moneySources.values.fold<double>(0, (a, b) => a + b);
    final tour = AppTourScope.maybeOf(context);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Centered total money display with eye icon
            KeyedSubtree(
              key: tour?.totalMoney,
              child: Center(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Total Money',
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        IconButton(
                          key: tour?.hideAmounts,
                          icon: Icon(
                            widget.showAmounts
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.grey,
                          ),
                          onPressed: _toggleAmountsVisibility,
                          tooltip:
                              widget.showAmounts
                                  ? 'Hide amounts'
                                  : 'Show amounts',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact = constraints.maxWidth < 560;
                        final amountText = ObscurableAmount(
                          amount: total.toStringAsFixed(2),
                          visible: widget.showAmounts,
                          textAlign: TextAlign.center,
                          style: Theme.of(
                            context,
                          ).textTheme.displayMedium?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        );

                        if (isCompact) {
                          return Column(
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: amountText,
                              ),
                              const SizedBox(height: 8),
                              _buildMainGoalInline(context),
                            ],
                          );
                        }

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: amountText,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Flexible(child: _buildMainGoalInline(context)),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            KeyedSubtree(key: tour?.goals, child: _buildGoalsStrip()),

            const SizedBox(height: 16),
            // List of money sources using custom widget
            ...widget.moneySources.entries.toList().asMap().entries.map((
              indexed,
            ) {
              final entry = indexed.value;
              return MoneySourceCard(
                key: indexed.key == 0 ? tour?.firstSource : ValueKey(entry.key),
                sourceName: entry.key,
                amount: entry.value,
                showAmount: widget.showAmounts,
                onEdit:
                    (newName, newAmount) => _showQuickActionsSheet(
                      context,
                      sourceName: entry.key,
                      currentAmount: entry.value,
                    ),
                onDelete:
                    () => _showDeleteConfirmationDialog(context, entry.key),
              );
            }),
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ElevatedButton.icon(
                  key: tour?.addSource,
                  onPressed: () => _showAddSourceDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Money Source'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Dialog for adding a mission
class AddMissionDialog extends StatefulWidget {
  final void Function(Mission) onAdd;

  const AddMissionDialog({super.key, required this.onAdd});

  @override
  State<AddMissionDialog> createState() => _AddMissionDialogState();
}

class _AddMissionDialogState extends State<AddMissionDialog> {
  final _formKey = GlobalKey<FormState>();
  double? _amount;
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _isCustom = false;

  @override
  void dispose() {
    super.dispose();
  }

  void _pickDate(BuildContext context, bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _customStart = picked;
        } else {
          _customEnd = picked;
        }
      });
    }
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final amount = _amount;
    if (amount == null || amount <= 0) return;
    DateTime start, end;
    if (_isCustom) {
      if (_customStart == null || _customEnd == null) return;
      start = _customStart!;
      end = _customEnd!;
    } else {
      final now = DateTime.now();
      start = DateTime(now.year, now.month + 1, 1);
      end = DateTime(now.year, now.month + 2, 0);
    }
    final mission = Mission.create(
      name: 'Mission',
      targetAmount: amount,
      startDate: start,
      endDate: end,
    );
    widget.onAdd(mission);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    return AlertDialog(
      title: const Text('Add Mission'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final v = await showAmountCalculatorSheet(
                  context,
                  title: 'Target Amount',
                  initialValue: _amount,
                  allowZero: false,
                );
                if (!mounted) return;
                setState(() => _amount = v);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Target Amount',
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  _amount == null
                      ? 'Tap to enter'
                      : _amount!.toStringAsFixed(2),
                  style: TextStyle(
                    color:
                        _amount == null
                            ? Theme.of(context).hintColor
                            : Theme.of(context).textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<bool>(
                    title: const Text('Start of next month'),
                    value: false,
                    groupValue: _isCustom,
                    onChanged: (v) => setState(() => _isCustom = v!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<bool>(
                    title: const Text('Custom'),
                    value: true,
                    groupValue: _isCustom,
                    onChanged: (v) => setState(() => _isCustom = v!),
                  ),
                ),
              ],
            ),
            if (_isCustom)
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _customStart == null
                              ? 'Start Date'
                              : 'Start: ${dateFormat.format(_customStart!)}',
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () => _pickDate(context, true),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _customEnd == null
                              ? 'End Date'
                              : 'End: ${dateFormat.format(_customEnd!)}',
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.calendar_today),
                        onPressed: () => _pickDate(context, false),
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: (_amount == null) ? null : _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

// New: Dialog for editing a money source with mission decrement logic
class EditMoneySourceDialogWithMission extends StatefulWidget {
  final String oldName;
  final double oldAmount;
  final Mission? mission;
  final bool showAmounts;

  const EditMoneySourceDialogWithMission({
    super.key,
    required this.oldName,
    required this.oldAmount,
    this.mission,
    this.showAmounts = true,
  });

  @override
  State<EditMoneySourceDialogWithMission> createState() =>
      _EditMoneySourceDialogWithMissionState();
}

class _EditMoneySourceDialogWithMissionState
    extends State<EditMoneySourceDialogWithMission> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late double _amount;
  bool _askMission = false;
  bool _decreaseMission = false;
  double _decrement = 0.0;
  bool _backdate = false;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _name = widget.oldName;
    _amount = widget.oldAmount;
  }

  void _checkDecrement(double newAmount) {
    final diff = widget.oldAmount - newAmount;
    if (diff > 0 && widget.mission != null) {
      setState(() {
        _askMission = true;
        _decrement = diff;
      });
    } else {
      setState(() {
        _askMission = false;
        _decrement = 0.0;
        _decreaseMission = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Money Source'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              initialValue: _name,
              decoration: const InputDecoration(labelText: 'Source Name'),
              validator:
                  (value) =>
                      value == null || value.isEmpty ? 'Enter a name' : null,
              onChanged: (value) => _name = value,
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final v = await showAmountCalculatorSheet(
                  context,
                  title: 'Amount',
                  initialValue: _amount,
                  allowZero: true,
                );
                if (v == null) return;
                if (!mounted) return;
                setState(() => _amount = v);
                _checkDecrement(v);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                ),
                child: ObscurableAmount(
                  amount: _amount.toStringAsFixed(2),
                  visible: widget.showAmounts,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            if (_askMission)
              CheckboxListTile(
                value: _decreaseMission,
                onChanged: (v) => setState(() => _decreaseMission = v ?? false),
                title: ObscurableAmount(
                  amount: 'Decrease mission by ${_decrement.toStringAsFixed(2)}',
                  visible: widget.showAmounts,
                ),
              ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _backdate,
              contentPadding: EdgeInsets.zero,
              title: const Text('Log edit to a different date'),
              subtitle: const Text(
                'Choose if this edit applies to an older date',
              ),
              onChanged: (v) => setState(() => _backdate = v ?? false),
            ),
            if (_backdate) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(DateFormat('yyyy-MM-dd').format(_selectedDate)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(now.year - 3),
                        lastDate: DateTime(now.year, now.month, now.day),
                      );
                      if (picked != null)
                        setState(() => _selectedDate = picked);
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop({
                'name': _name,
                'amount': _amount,
                'decreaseMission': _decreaseMission,
                'decrement': _decrement,
                'effectiveDate': _backdate ? _selectedDate : null,
              });
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
