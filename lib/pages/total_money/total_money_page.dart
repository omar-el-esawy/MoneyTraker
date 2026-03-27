import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:intl/intl.dart';
import 'widgets/add_money_source_dialog.dart';
import 'package:money_traker/model/mission.dart';
import 'package:money_traker/model/goal.dart';
import 'package:money_traker/store/money_storage.dart';
import 'package:money_traker/pages/goals/goals_page.dart';
import 'package:money_traker/pages/goals/logic/goal_engine.dart';

class TotalMoneyPage extends StatefulWidget {
  final Map<String, double> moneySources;
  final void Function(String, double) onAddSource;
  final void Function(String, String, double) onEditSource;
  final void Function(String) onDeleteSource;

  final Future<void> Function(String sourceName, double amount) onQuickAdd;
  final Future<void> Function(String sourceName, double amount) onQuickSubtract;
  final Future<void> Function(String fromSource, String toSource, double amount) onTransfer;

  final Mission? mission;
  final void Function(Mission) onAddMission;

  const TotalMoneyPage({
    super.key,
    required this.moneySources,
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

class _TotalMoneyPageState extends State<TotalMoneyPage> {
  bool _showAmounts = true;
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

    final spentMode = p.goal.direction == GoalDirection.spendingLimit;
    final label = spentMode ? 'Spent' : 'Saved';

    // Remaining can become negative if exceeded.
    final remaining = p.goal.targetAmount - p.progress;
    final exceeded = remaining < 0;
    final remainingColor = exceeded ? Colors.red : const Color(0xFF6B7280);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          p.goal.name,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: ${p.progress.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(width: 10),
            Text(
              'Remaining: ${remaining.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: remainingColor, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openGoals() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GoalsPage()));
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
              Text('Goals', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton(onPressed: _openGoals, child: const Text('See all')),
            ],
          ),
        ),
        SizedBox(
          height: 140,
          child: _loadingGoals
              ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
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
                            border: Border.all(color: const Color(0xFFD0D0D0)),
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_circle_outline, size: 28, color: Color(0xFF9CA3AF)),
                                SizedBox(height: 4),
                                Text('New Goal', style: TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }

                    final p = _homeGoals[i];
                    final spentMode = p.goal.direction == GoalDirection.spendingLimit;
                    final cycleLabel = switch (p.goal.type) {
                      GoalType.monthly => 'Monthly',
                      GoalType.repeatingDays => '${p.goal.repeatEveryDays ?? 0} days',
                      GoalType.fixedPeriod => 'Fixed',
                    };
                    final accent = spentMode ? const Color(0xFFD32F2F) : const Color(0xFF1B5E20);
                    final bg = spentMode ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9);
                    final pct = p.percent.clamp(0.0, 1.0);

                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _openGoals,
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
                            )
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
                                  decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
                                  child: Icon(spentMode ? Icons.trending_down : Icons.flag_outlined, size: 16, color: accent),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    p.goal.name,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(cycleLabel, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF9CA3AF))),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 8,
                                backgroundColor: const Color(0xFFF0F0F0),
                                valueColor: AlwaysStoppedAnimation<Color>(accent),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  p.progress.toStringAsFixed(2),
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  ' / ${p.goal.targetAmount.toStringAsFixed(2)}',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF9CA3AF)),
                                ),
                                const Spacer(),
                                Text('${p.daysRemaining}d left', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF6B7280))),
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
    setState(() {
      _showAmounts = !_showAmounts;
    });
  }

  void _showAddSourceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AddMoneySourceDialog(
        onAdd: (name, amount) => widget.onAddSource(name, amount),
      ),
    );
  }

  Future<void> _showEditSourceDialog(BuildContext context, String oldName, double oldAmount) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => EditMoneySourceDialogWithMission(
        oldName: oldName,
        oldAmount: oldAmount,
        mission: _mission,
      ),
    );
    if (result != null) {
      final String newName = result['name'];
      final double newAmount = result['amount'];
      final bool decreaseMission = result['decreaseMission'] ?? false;
      final double decrement = result['decrement'] ?? 0.0;

      widget.onEditSource(oldName, newName, newAmount);

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
      builder: (context) => AlertDialog(
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

  Future<double?> _askAmount(BuildContext context, {required String title}) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final res = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Amount',
              hintText: '0.00',
            ),
            validator: (v) {
              final val = double.tryParse((v ?? '').trim());
              if (val == null) return 'Enter a valid number';
              if (val <= 0) return 'Amount must be > 0';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(double.parse(controller.text.trim()));
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );

    // NOTE: Don't manually dispose controller here; the dialog may still be
    // finalizing animations/layout when it returns, and disposing can cause
    // "used after being disposed" errors. Let GC handle it.
    return res;
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
                  Text(
                    'Current: ${currentAmount.toStringAsFixed(2)}',
                    style: Theme.of(sheetCtx)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(sheetCtx).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('Add amount'),
                    subtitle: const Text('Increase this source by a number'),
                    onTap: () async {
                      final amount = await _askAmount(sheetCtx, title: 'Add amount');
                      if (amount == null) return;
                      await widget.onQuickAdd(sourceName, amount);
                      if (!sheetCtx.mounted) return;
                      Navigator.of(sheetCtx).pop();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.remove_circle_outline),
                    title: const Text('Subtract amount'),
                    subtitle: const Text('Decrease this source by a number'),
                    onTap: () async {
                      final amount = await _askAmount(sheetCtx, title: 'Subtract amount');
                      if (amount == null) return;
                      await widget.onQuickSubtract(sourceName, amount);
                      if (!sheetCtx.mounted) return;
                      Navigator.of(sheetCtx).pop();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.swap_horiz),
                    title: const Text('Transfer to another source'),
                    subtitle: const Text('Move money from this source to another'),
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
                  const Divider(height: 20),
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('Edit name/amount'),
                    onTap: () async {
                      await _showEditSourceDialog(sheetCtx, sourceName, currentAmount);
                      if (!sheetCtx.mounted) return;
                      Navigator.of(sheetCtx).pop();
                    },
                  ),
                  ListTile(
                    leading: Icon(Icons.delete_outline, color: Theme.of(sheetCtx).colorScheme.error),
                    title: Text(
                      'Delete source',
                      style: TextStyle(color: Theme.of(sheetCtx).colorScheme.error),
                    ),
                    subtitle: const Text('Remove this money source'),
                    onTap: () async {
                      final confirmed = await showDialog<bool>(
                        context: sheetCtx,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Delete Money Source'),
                          content: Text('Are you sure you want to delete "$sourceName"?'),
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
    final targets = widget.moneySources.keys.where((k) => k != fromSource).toList()..sort();
    if (targets.isEmpty) return null;

    String toSource = targets.first;
    final amountController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transfer'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: toSource,
                  decoration: const InputDecoration(labelText: 'To'),
                  items: targets
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    toSource = v;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Amount'),
                  validator: (v) {
                    final val = double.tryParse((v ?? '').trim());
                    if (val == null) return 'Enter a valid number';
                    if (val <= 0) return 'Amount must be > 0';
                    if (val > fromCurrentAmount) {
                      return 'Not enough balance (max ${fromCurrentAmount.toStringAsFixed(2)})';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(ctx).pop(true);
              }
            },
            child: const Text('Transfer'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final amount = double.parse(amountController.text.trim());
      try {
        await widget.onTransfer(fromSource, toSource, amount);
      } catch (e) {
        if (!context.mounted) return confirmed;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer failed: $e')),
        );
        return false;
      }
    }

    return confirmed;
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.moneySources.values.fold<double>(0, (a, b) => a + b);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // Centered total money display with eye icon
            Center(
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
                        icon: Icon(
                          _showAmounts ? Icons.visibility : Icons.visibility_off,
                          color: Colors.grey,
                        ),
                        onPressed: _toggleAmountsVisibility,
                        tooltip: _showAmounts ? 'Hide amounts' : 'Show amounts',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _showAmounts ? total.toStringAsFixed(2) : '****',
                        style: Theme.of(context).textTheme.displayMedium?.copyWith(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(width: 14),
                      Flexible(child: _buildMainGoalInline(context)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _buildGoalsStrip(),

            const SizedBox(height: 16),
            // List of money sources using custom widget
            ...widget.moneySources.entries.map((entry) {
              return MoneySourceCard(
                sourceName: entry.key,
                amount: entry.value,
                showAmount: _showAmounts,
                onEdit: (newName, newAmount) => _showQuickActionsSheet(
                  context,
                  sourceName: entry.key,
                  currentAmount: entry.value,
                ),
                onDelete: () => _showDeleteConfirmationDialog(context, entry.key),
              );
            }).toList(),
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ElevatedButton.icon(
                  onPressed: () => _showAddSourceDialog(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Money Source'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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

// Custom widget for money source card with delete action and amount visibility toggle
class MoneySourceCard extends StatelessWidget {
  final String sourceName;
  final double amount;
  final bool showAmount;
  final void Function(String, double) onEdit;
  final VoidCallback onDelete;

  const MoneySourceCard({
    super.key,
    required this.sourceName,
    required this.amount,
    required this.showAmount,
    required this.onEdit,
    required this.onDelete,
  });

  Future<void> _showDeleteConfirmationDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Money Source'),
        content: Text('Are you sure you want to delete "$sourceName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    const double cardHeight = 56; // Standard ListTile height

    return Slidable(
      key: ValueKey(sourceName),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (_) => _showDeleteConfirmationDialog(context),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Delete',
            flex: 1,
            spacing: 0,
            autoClose: true,
          ),
        ],
      ),
      child: GestureDetector(
        onTap: () => onEdit(sourceName, amount),
        child: Container(
          height: cardHeight,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey[200], // Light grey background
            borderRadius: BorderRadius.zero, // No curves
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  showAmount
                      ? '$sourceName: ${amount.toStringAsFixed(2)}'
                      : '$sourceName: ****',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              // No trailing delete icon here; it's in the slide action
            ],
          ),
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
  final _amountController = TextEditingController();
  DateTime? _customStart;
  DateTime? _customEnd;
  bool _isCustom = false;

  @override
  void dispose() {
    _amountController.dispose();
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
    final amount = double.tryParse(_amountController.text) ?? 0.0;
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
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(labelText: 'Target Amount'),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              validator: (v) => (v == null || v.isEmpty) ? 'Enter amount' : null,
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
                        child: Text(_customStart == null
                            ? 'Start Date'
                            : 'Start: ${dateFormat.format(_customStart!)}'),
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
                        child: Text(_customEnd == null
                            ? 'End Date'
                            : 'End: ${dateFormat.format(_customEnd!)}'),
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
          onPressed: _submit,
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

  const EditMoneySourceDialogWithMission({
    super.key,
    required this.oldName,
    required this.oldAmount,
    this.mission,
  });

  @override
  State<EditMoneySourceDialogWithMission> createState() => _EditMoneySourceDialogWithMissionState();
}

class _EditMoneySourceDialogWithMissionState extends State<EditMoneySourceDialogWithMission> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late String _amount;
  bool _askMission = false;
  bool _decreaseMission = false;
  double _decrement = 0.0;

  @override
  void initState() {
    super.initState();
    _name = widget.oldName;
    _amount = widget.oldAmount.toString();
  }

  void _checkDecrement(String value) {
    final newAmount = double.tryParse(value) ?? widget.oldAmount;
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
              validator: (value) => value == null || value.isEmpty ? 'Enter a name' : null,
              onChanged: (value) => _name = value,
            ),
            TextFormField(
              initialValue: _amount,
              decoration: const InputDecoration(labelText: 'Amount'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Enter an amount';
                if (double.tryParse(value) == null) return 'Enter a valid number';
                return null;
              },
              onChanged: (value) {
                _amount = value;
                _checkDecrement(value);
              },
            ),
            if (_askMission)
              CheckboxListTile(
                value: _decreaseMission,
                onChanged: (v) => setState(() => _decreaseMission = v ?? false),
                title: Text('Decrease mission by $_decrement'),
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
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop({
                'name': _name,
                'amount': double.parse(_amount),
                'decreaseMission': _decreaseMission,
                'decrement': _decrement,
              });
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
