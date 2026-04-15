import 'package:flutter/material.dart';

import 'package:money_traker/pages/widgets/amount_calculator_sheet.dart';

class EditMoneySourceDialog extends StatefulWidget {
  final String oldName;
  final double oldAmount;
  final void Function(String, double) onEdit;

  const EditMoneySourceDialog({
    super.key,
    required this.oldName,
    required this.oldAmount,
    required this.onEdit,
  });

  @override
  State<EditMoneySourceDialog> createState() => _EditMoneySourceDialogState();
}

class _EditMoneySourceDialogState extends State<EditMoneySourceDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late double _amount;

  @override
  void initState() {
    super.initState();
    _name = widget.oldName;
    _amount = widget.oldAmount;
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
              widget.onEdit(_name, _amount);
              Navigator.of(context).pop();
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
