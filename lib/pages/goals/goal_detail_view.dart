import 'package:flutter/material.dart';
import 'package:money_traker/model/goal.dart';
import 'package:money_traker/pages/goals/edit_goal_sheet.dart';
import 'package:money_traker/pages/goals/logic/goal_engine.dart';
import 'package:money_traker/pages/goals/widget/zoomable_goal_chart.dart';
import 'package:money_traker/store/money_storage.dart';

class GoalDetailPageView extends StatefulWidget {
  final Goal goal;

  const GoalDetailPageView({super.key, required this.goal});

  @override
  State<GoalDetailPageView> createState() => _GoalDetailPageViewState();
}

class _GoalDetailPageViewState extends State<GoalDetailPageView> {
  final MoneyStorage _storage = MoneyStorage();
  bool _loading = true;
  late Goal _goal;
  GoalProgress? _progress;

  @override
  void initState() {
    super.initState();
    _goal = widget.goal;
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      var goal = _goal;
      if (goal.id != null) {
        final goals = await _storage.getGoals(includeInactive: true);
        for (final saved in goals) {
          if (saved.id == goal.id) {
            goal = saved;
            break;
          }
        }
      }

      final engine = GoalEngine(_storage);
      final progress = await engine.computeProgress(goal);

      if (!mounted) return;
      setState(() {
        _goal = goal;
        _progress = progress;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading goal progress: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _edit() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => EditGoalSheet(goal: _goal),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final spentMode = _goal.direction == GoalDirection.spendingLimit;
    final accent = spentMode ? const Color(0xFFD32F2F) : const Color(0xFF1B5E20);
    final bgColor = spentMode ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9);

    return Scaffold(
      appBar: AppBar(
        title: Text(_goal.name),
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _loading ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit goal',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
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
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  spentMode ? Icons.trending_down : Icons.flag_outlined,
                                  color: accent,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _goal.name,
                                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    Text(
                                      spentMode ? 'Spending Limit' : 'Savings Target',
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: _progress == null ? 0 : (_progress!.percent.clamp(0.0, 1.0)),
                              minHeight: 12,
                              backgroundColor: const Color(0xFFF0F0F0),
                              valueColor: AlwaysStoppedAnimation<Color>(accent),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Progress',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey),
                                  ),
                                  Text(
                                    _progress == null ? '0.00' : '${_progress!.progress.toStringAsFixed(2)} / ${_goal.targetAmount.toStringAsFixed(2)}',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Days Remaining',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey),
                                  ),
                                  Text(
                                    '${_progress?.daysRemaining ?? 0} days',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: ZoomableGoalChart(goal: _goal),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}

