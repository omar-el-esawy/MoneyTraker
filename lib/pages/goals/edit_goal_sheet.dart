import 'package:flutter/material.dart';
import 'package:money_traker/model/goal.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/store/money_storage.dart';

class EditGoalSheet extends StatefulWidget {
  final Goal? goal;

  const EditGoalSheet({super.key, this.goal});

  @override
  State<EditGoalSheet> createState() => _EditGoalSheetState();
}

class _EditGoalSheetState extends State<EditGoalSheet> {
  final MoneyStorage _storage = MoneyStorage();

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _target;

  GoalDirection _direction = GoalDirection.spendingLimit;
  GoalType _type = GoalType.monthly;

  int _monthStartDay = 1;
  int _repeatEveryDays = 14;
  DateTime _repeatStartDate = DateTime.now();
  DateTime _periodStart = DateTime.now();
  DateTime _periodEnd = DateTime.now();

  bool _isActive = true;
  bool _isMain = false;
  final Set<int> _excludedTagIds = {};

  bool _loadingTags = true;
  List<Tag> _expenseTags = [];

  @override
  void initState() {
    super.initState();

    final g = widget.goal;
    _name = TextEditingController(text: g?.name ?? '');
    _target = TextEditingController(text: g == null ? '' : g.targetAmount.toStringAsFixed(2));

    if (g != null) {
      _direction = g.direction;
      _type = g.type;
      _monthStartDay = g.monthStartDay ?? 1;
      _repeatEveryDays = g.repeatEveryDays ?? 14;
      _repeatStartDate = g.repeatStartDate ?? DateTime.now();
      _periodStart = g.periodStart ?? DateTime.now();
      _periodEnd = g.periodEnd ?? DateTime.now();
      _isActive = g.isActive;
      _isMain = g.isMain;
      _excludedTagIds.addAll(g.excludedTagIds);
    }

    _loadTags();
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    final tags = await _storage.getTags(type: TagType.expense);
    if (!mounted) return;
    setState(() {
      _expenseTags = tags;
      _loadingTags = false;
    });
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _periodStart : _periodEnd,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _periodStart = picked;
        if (_periodEnd.isBefore(_periodStart)) {
          _periodEnd = _periodStart;
        }
      } else {
        _periodEnd = picked;
        if (_periodEnd.isBefore(_periodStart)) {
          _periodStart = _periodEnd;
        }
      }
    });
  }

  Future<void> _pickRepeatStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _repeatStartDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _repeatStartDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final target = double.parse(_target.text.trim().replaceAll(',', '.'));

    final createdAt = widget.goal?.createdAt ?? DateTime.now();

    final Goal goal = Goal(
      id: widget.goal?.id,
      name: _name.text.trim(),
      targetAmount: target,
      type: _type,
      direction: _direction,
      monthStartDay: _type == GoalType.monthly ? _monthStartDay : null,
      repeatEveryDays: _type == GoalType.repeatingDays ? _repeatEveryDays : null,
      repeatStartDate: _type == GoalType.repeatingDays ? _repeatStartDate : null,
      periodStart: _type == GoalType.fixedPeriod ? _periodStart : null,
      periodEnd: _type == GoalType.fixedPeriod ? _periodEnd : null,
      excludedTagIds: _excludedTagIds.toList()..sort(),
      isMain: _isMain,
      isActive: _isActive,
      createdAt: createdAt,
    );

    if (goal.id == null) {
      final newId = await _storage.addGoal(goal);
      if (_isMain) {
        await _storage.setMainGoal(newId);
      }
    } else {
      await _storage.updateGoal(goal);
      if (_isMain) {
        await _storage.setMainGoal(goal.id);
      } else {
        // If this goal used to be main, unset it.
        final currentMain = await _storage.getMainGoal();
        if (currentMain?.id == goal.id) {
          await _storage.setMainGoal(null);
        }
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottom),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.goal == null ? 'Create Goal' : 'Edit Goal',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g., Monthly Budget'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Spending Limit'),
                        selected: _direction == GoalDirection.spendingLimit,
                        onSelected: (_) => setState(() => _direction = GoalDirection.spendingLimit),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Savings Target'),
                        selected: _direction == GoalDirection.savingsTarget,
                        onSelected: (_) => setState(() => _direction = GoalDirection.savingsTarget),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _target,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Target Amount', hintText: '0.00'),
                  validator: (v) {
                    final parsed = double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                    if (parsed == null) return 'Enter a number';
                    if (parsed <= 0) return 'Must be > 0';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Text('Repeats', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                RadioListTile<GoalType>(
                  value: GoalType.monthly,
                  groupValue: _type,
                  title: const Text('Monthly'),
                  subtitle: const Text('Resets on a specific day each month'),
                  onChanged: (v) => setState(() => _type = v!),
                ),
                if (_type == GoalType.monthly)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                    child: Row(
                      children: [
                        const Text('Starts on day'),
                        const SizedBox(width: 8),
                        DropdownButton<int>(
                          value: _monthStartDay,
                          items: [
                            for (int i = 1; i <= 28; i++) DropdownMenuItem(value: i, child: Text('$i')),
                          ],
                          onChanged: (v) => setState(() => _monthStartDay = v ?? 1),
                        ),
                      ],
                    ),
                  ),
                RadioListTile<GoalType>(
                  value: GoalType.repeatingDays,
                  groupValue: _type,
                  title: const Text('Every X days'),
                  subtitle: const Text('Repeats on a custom cycle'),
                  onChanged: (v) => setState(() => _type = v!),
                ),
                if (_type == GoalType.repeatingDays)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Every'),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 80,
                              child: TextFormField(
                                initialValue: _repeatEveryDays.toString(),
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(isDense: true),
                                onChanged: (v) {
                                  final p = int.tryParse(v.trim());
                                  if (p == null) return;
                                  setState(() => _repeatEveryDays = p.clamp(1, 3650));
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('days'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('Starting from'),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _pickRepeatStart,
                              child: Text('${_repeatStartDate.year}-${_repeatStartDate.month.toString().padLeft(2, '0')}-${_repeatStartDate.day.toString().padLeft(2, '0')}'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                RadioListTile<GoalType>(
                  value: GoalType.fixedPeriod,
                  groupValue: _type,
                  title: const Text('Fixed period'),
                  subtitle: const Text('One-time, does not repeat'),
                  onChanged: (v) => setState(() => _type = v!),
                ),
                if (_type == GoalType.fixedPeriod)
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
                    child: Row(
                      children: [
                        OutlinedButton(
                          onPressed: () => _pickDate(isStart: true),
                          child: Text('Start: ${_periodStart.year}-${_periodStart.month.toString().padLeft(2, '0')}-${_periodStart.day.toString().padLeft(2, '0')}'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => _pickDate(isStart: false),
                          child: Text('End: ${_periodEnd.year}-${_periodEnd.month.toString().padLeft(2, '0')}-${_periodEnd.day.toString().padLeft(2, '0')}'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  title: const Text('Active'),
                ),
                SwitchListTile(
                  value: _isMain,
                  onChanged: (v) => setState(() => _isMain = v),
                  title: const Text('Show as main goal'),
                  subtitle: const Text('This goal will be highlighted in Total Money and Insights.'),
                ),
                const SizedBox(height: 8),
                Text('Exclude Categories', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text('These categories won\'t count toward this goal', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                const SizedBox(height: 8),
                if (_loadingTags)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _expenseTags.map((t) {
                      final selected = _excludedTagIds.contains(t.id);
                      return FilterChip(
                        label: Text(t.name),
                        selected: selected,
                        onSelected: (v) {
                          if (t.id == null) return;
                          setState(() {
                            if (v) {
                              _excludedTagIds.add(t.id!);
                            } else {
                              _excludedTagIds.remove(t.id!);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _save,
                    child: const Text('Save Goal'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

