import 'package:flutter/material.dart';
import 'package:money_traker/model/mission.dart';
import 'package:money_traker/pages/widgets/amount_calculator_sheet.dart';

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
  late double _amount;
  bool _askMission = false;
  bool _decreaseMission = false;
  double _decrement = 0.0;

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
              validator: (value) => value == null || value.isEmpty ? 'Enter a name' : null,
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
                child: Text(
                  _amount.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
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
                'amount': _amount,
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
