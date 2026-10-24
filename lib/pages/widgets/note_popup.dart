import 'package:flutter/material.dart';

class NotePopup extends StatefulWidget {
  final String? initialNote;

  const NotePopup({super.key, this.initialNote});

  @override
  State<NotePopup> createState() => _NotePopupState();
}

class _NotePopupState extends State<NotePopup> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add/Edit Note'),
      content: TextField(
        controller: _controller,
        decoration: const InputDecoration(
          labelText: 'Note (optional)',
        ),
        maxLines: 3,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(widget.initialNote),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
