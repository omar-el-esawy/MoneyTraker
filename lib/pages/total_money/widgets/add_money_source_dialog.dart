import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AddMoneySourceDialog extends StatefulWidget {
  final void Function(String, double) onAdd;

  const AddMoneySourceDialog({super.key, required this.onAdd});

  @override
  State<AddMoneySourceDialog> createState() => _AddMoneySourceDialogState();
}

class _AddMoneySourceDialogState extends State<AddMoneySourceDialog> {
  final _formKey = GlobalKey<FormState>();
  String _name = '';
  String _amount = '';

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
            TextFormField(
              decoration: const InputDecoration(labelText: 'Initial Amount'),
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
              widget.onAdd(_name, double.parse(_amount));
              Navigator.of(context).pop();
            }
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
