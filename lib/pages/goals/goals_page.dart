import 'package:flutter/material.dart';
import 'package:money_traker/model/goal.dart';
import 'edit_goal_sheet.dart';
import 'package:money_traker/pages/goals/logic/goal_engine.dart';
import 'package:money_traker/store/money_storage.dart';
import 'goal_detail_view.dart';

class GoalsPage extends StatefulWidget {
  const GoalsPage({super.key});

  @override
  State<GoalsPage> createState() => _GoalsPageState();
}

class _GoalsPageState extends State<GoalsPage> {
  final MoneyStorage _storage = MoneyStorage();

  bool _loading = true;
  List<Goal> _goals = [];
  final Map<int, GoalProgress> _progress = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final goals = await _storage.getGoals(includeInactive: true);
    final engine = GoalEngine(_storage);

    _progress.clear();
    for (final g in goals.where((g) => g.id != null)) {
      _progress[g.id!] = await engine.computeProgress(g);
    }

    if (!mounted) return;
    setState(() {
      _goals = goals;
      _loading = false;
    });
  }

  Future<void> _createGoal() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => const EditGoalSheet(),
    );
    await _load();
  }

  Future<void> _editGoal(Goal goal) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => EditGoalSheet(goal: goal),
    );
    await _load();
  }

  Future<void> _toggleActive(Goal goal) async {
    final updated = goal.copyWith(isActive: !goal.isActive);
    await _storage.updateGoal(updated);
    await _load();
  }

  Future<void> _deleteGoal(Goal goal) async {
    if (goal.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete goal'),
        content: Text('Delete "${goal.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _storage.deleteGoal(goal.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Goals'),
        actions: [
          IconButton(onPressed: _createGoal, icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _goals.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.flag_outlined, size: 42, color: Colors.grey),
                      const SizedBox(height: 8),
                      const Text('No goals yet'),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(onPressed: _createGoal, icon: const Icon(Icons.add), label: const Text('Create goal')),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _goals.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (ctx, i) {
                    final g = _goals[i];
                    final p = g.id == null ? null : _progress[g.id!];
                    final pct = p == null ? 0.0 : p.percent.clamp(0.0, 1.0);

                    final spentMode = g.direction == GoalDirection.spendingLimit;
                    final accent = spentMode ? const Color(0xFFD32F2F) : const Color(0xFF1B5E20);

                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                                      onTap: () async {
                        await Navigator.of(ctx).push(
                          MaterialPageRoute(builder: (_) => GoalDetailPageView(goal: g)),
                        );
                        await _load();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
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
                                    color: spentMode ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    spentMode ? Icons.trending_down : Icons.flag_outlined,
                                    size: 16,
                                    color: accent,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    g.name,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (v) {
                                    if (v == 'edit') _editGoal(g);
                                    if (v == 'toggle') _toggleActive(g);
                                    if (v == 'delete') _deleteGoal(g);
                                  },
                                  itemBuilder: (ctx) => [
                                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                    PopupMenuItem(value: 'toggle', child: Text(g.isActive ? 'Pause' : 'Resume')),
                                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: pct,
                                minHeight: 10,
                                backgroundColor: const Color(0xFFF0F0F0),
                                valueColor: AlwaysStoppedAnimation<Color>(accent),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Text(
                                  p == null ? '0.00' : p.progress.toStringAsFixed(2),
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  ' / ${g.targetAmount.toStringAsFixed(2)}',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF9CA3AF)),
                                ),
                                if (!g.isActive)
                                  Text(
                                    'Paused',
                                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                      color: const Color(0xFF9CA3AF),
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                else if (g.isMain)
                                  Text(
                                    'Main',
                                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                      color: accent,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                const Spacer(),
                                if (p != null)
                                  Text(
                                    '${p.daysRemaining}d left',
                                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: const Color(0xFF6B7280)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}


