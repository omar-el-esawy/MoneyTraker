import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money_traker/model/mission.dart';

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
