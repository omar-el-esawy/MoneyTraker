import 'package:flutter/material.dart';

import 'package:money_traker/pages/widgets/amount_calculator_sheet.dart';

class AddMoneySourceDialog extends StatefulWidget {
  final void Function(String, double) onAdd;

  const AddMoneySourceDialog({super.key, required this.onAdd});

  @override
  State<AddMoneySourceDialog> createState() => _AddMoneySourceDialogState();
}

class _AddMoneySourceDialogState extends State<AddMoneySourceDialog> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  double? _amount;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Money Source'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
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
                  title: 'Initial Amount',
                  initialValue: _amount,
                  allowZero: true,
                );
                if (!mounted) return;
                setState(() => _amount = v);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Initial Amount',
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  _amount == null ? 'Tap to enter' : _amount!.toStringAsFixed(2),
                  style: TextStyle(
                    color: _amount == null
                        ? Theme.of(context).hintColor
                        : Theme.of(context).textTheme.bodyLarge?.color,
                    fontWeight: FontWeight.w700,
                  ),
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
            if (!_formKey.currentState!.validate()) return;
            final amount = _amount;
            if (amount == null) return;
            widget.onAdd(_name, amount);
            Navigator.of(context).pop();
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
