import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  late String _amount;

  @override
  void initState() {
    super.initState();
    _name = widget.oldName;
    _amount = widget.oldAmount.toString();
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
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              validator: (value) {
                if (value == null || value.isEmpty) return 'Enter an amount';
                if (double.tryParse(value) == null) return 'Enter a valid number';
                return null;
              },
              onChanged: (value) => _amount = value,
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
              widget.onEdit(_name, double.parse(_amount));
              Navigator.of(context).pop();
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
