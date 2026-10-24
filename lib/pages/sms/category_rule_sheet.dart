import 'package:flutter/material.dart';

import 'package:money_traker/model/tag.dart';
import 'package:money_traker/sms/sms_strings.dart';
import 'package:money_traker/store/money_storage.dart';

Future<Tag?> showSmsCategoryPicker({
  required BuildContext context,
  required bool arabic,
  required String word,
}) {
  return showModalBottomSheet<Tag>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _SmsCategoryPicker(arabic: arabic, word: word),
  );
}

class _SmsCategoryPicker extends StatefulWidget {
  final bool arabic;
  final String word;

  const _SmsCategoryPicker({required this.arabic, required this.word});

  @override
  State<_SmsCategoryPicker> createState() => _SmsCategoryPickerState();
}

class _SmsCategoryPickerState extends State<_SmsCategoryPicker> {
  final _storage = MoneyStorage();
  final _name = TextEditingController();

  List<Tag> _tags = [];
  TagType _type = TagType.expense;
  int? _selectedId;
  bool _loading = true;
  bool _saving = false;

  SmsStrings get _s => SmsStrings(widget.arabic);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final tags = await _storage.getTags();
    tags.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _tags = tags;
      _loading = false;
    });
  }

  List<Tag> get _visible => _tags.where((tag) => tag.type == _type && tag.id != null).toList();

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty && _selectedId == null) return;
    setState(() => _saving = true);
    try {
      final Tag tag;
      if (name.isNotEmpty) {
        tag = await _storage.ensureTag(name: name, type: _type);
      } else {
        tag = _visible.firstWhere((item) => item.id == _selectedId);
      }
      if (!mounted) return;
      Navigator.pop(context, tag);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Directionality(
      textDirection: s.ar ? TextDirection.rtl : TextDirection.ltr,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottom),
        child: _loading
            ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(s.pickCategory, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(s.pickCategoryHint(widget.word)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(s.expenses),
                        selected: _type == TagType.expense,
                        onSelected: (_) => setState(() {
                          _type = TagType.expense;
                          _selectedId = null;
                        }),
                      ),
                      ChoiceChip(
                        label: Text(s.income),
                        selected: _type == TagType.income,
                        onSelected: (_) => setState(() {
                          _type = TagType.income;
                          _selectedId = null;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_visible.isEmpty)
                    Text(s.noCategoryTags, style: Theme.of(context).textTheme.bodyMedium)
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in _visible)
                          ChoiceChip(
                            label: Text(tag.name),
                            selected: _name.text.isEmpty && _selectedId == tag.id,
                            onSelected: (_) => setState(() {
                              _name.clear();
                              _selectedId = tag.id;
                            }),
                          ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(labelText: s.newCategory),
                    onChanged: (_) => setState(() => _selectedId = null),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving || (_name.text.trim().isEmpty && _selectedId == null) ? null : _save,
                    child: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(s.save),
                  ),
                ],
              ),
            ),
      ),
    );
  }
}
