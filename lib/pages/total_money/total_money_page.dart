import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'widgets/add_money_source_dialog.dart';
import 'widgets/edit_money_source_dialog.dart';
import 'logic/money_logic.dart';
import 'package:money_traker/model/mission.dart';
import 'package:intl/intl.dart';

class TotalMoneyPage extends StatefulWidget {
  final Map<String, double> moneySources;
  final void Function(String, double) onAddSource;
  final void Function(String, String, double) onEditSource;
  final void Function(String) onDeleteSource;
  final Mission? mission;
  final void Function(Mission) onAddMission;

  const TotalMoneyPage({
    super.key,
    required this.moneySources,
    required this.onAddSource,
    required this.onEditSource,
    required this.onDeleteSource,
    this.mission,
    required this.onAddMission,
  });

  @override
  State<TotalMoneyPage> createState() => _TotalMoneyPageState();
}

class _TotalMoneyPageState extends State<TotalMoneyPage> {
  bool _showAmounts = true;
  Mission? _mission;

  @override
  void initState() {
    super.initState();
    _mission = widget.mission;
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

  void _showAddMissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AddMissionDialog(
        onAdd: (mission) {
          widget.onAddMission(mission);
          setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.moneySources.values.fold<double>(0, (a, b) => a + b);

    Mission? mission = _mission;
    double? missionRemaining;
    if (mission != null) {
      missionRemaining = mission.targetAmount - total;
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          children: [
            // // Add Mission Button
            // Row(
            //   mainAxisAlignment: MainAxisAlignment.end,
            //   children: [
            //     ElevatedButton.icon(
            //       icon: const Icon(Icons.flag),
            //       label: const Text('Add Mission'),
            //       onPressed: () => _showAddMissionDialog(context),
            //     ),
            //   ],
            // ),
            // // Mission Target Amount Display
            // if (mission != null)
            //   Padding(
            //     padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
            //     child: Row(
            //       mainAxisAlignment: MainAxisAlignment.center,
            //       children: [
            //         const Icon(Icons.flag, color: Colors.orange),
            //         const SizedBox(width: 8),
            //         Text(
            //           'Mission Target: ',
            //           style: Theme.of(context).textTheme.titleMedium,
            //         ),
            //         Text(
            //           mission.targetAmount.toStringAsFixed(2),
            //           style: Theme.of(context).textTheme.titleMedium?.copyWith(
            //                 color: Colors.blue,
            //                 fontWeight: FontWeight.bold,
            //               ),
            //         ),
            //       ],
            //     ),
            //   ),
            // // Mission Remaining Display
            // if (mission != null)
            //   Padding(
            //     padding: const EdgeInsets.only(bottom: 8.0),
            //     child: Row(
            //       mainAxisAlignment: MainAxisAlignment.center,
            //       children: [
            //         const Icon(Icons.flag, color: Colors.orange),
            //         const SizedBox(width: 8),
            //         Text(
            //           'Mission Remaining: ',
            //           style: Theme.of(context).textTheme.titleMedium,
            //         ),
            //         Text(
            //           missionRemaining!.toStringAsFixed(2),
            //           style: Theme.of(context).textTheme.titleMedium?.copyWith(
            //                 color: missionRemaining < 0 ? Colors.red : Colors.green,
            //                 fontWeight: FontWeight.bold,
            //               ),
            //         ),
            //       ],
            //     ),
            //   ),
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
                  Text(
                    _showAmounts ? total.toStringAsFixed(2) : '****',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // List of money sources using custom widget
            ...widget.moneySources.entries.map((entry) {
              return MoneySourceCard(
                sourceName: entry.key,
                amount: entry.value,
                showAmount: _showAmounts,
                onEdit: (newName, newAmount) => _showEditSourceDialog(context, entry.key, entry.value),
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

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(
          showAmount
              ? '$sourceName: ${amount.toStringAsFixed(2)}'
              : '$sourceName: ****',
        ),
        onTap: () => onEdit(sourceName, amount),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(FontAwesomeIcons.trashCan, color: Colors.red),
              onPressed: onDelete,
              tooltip: 'Delete',
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
