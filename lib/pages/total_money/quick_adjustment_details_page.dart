import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:money_traker/model/tag.dart';

class QuickAdjustmentDetailsResult {
  final String? categoryName;
  final DateTime selectedDate;

  const QuickAdjustmentDetailsResult({
    required this.categoryName,
    required this.selectedDate,
  });
}

class QuickAdjustmentDetailsPage extends StatefulWidget {
  final bool isAdd;
  final String sourceName;
  final double amount;
  final List<Tag> categories;

  const QuickAdjustmentDetailsPage({
    super.key,
    required this.isAdd,
    required this.sourceName,
    required this.amount,
    required this.categories,
  });

  @override
  State<QuickAdjustmentDetailsPage> createState() =>
      _QuickAdjustmentDetailsPageState();
}

class _QuickAdjustmentDetailsPageState
    extends State<QuickAdjustmentDetailsPage> {
  static const int _visibleDayCount = 31;

  final ScrollController _dateController = ScrollController();
  final TextEditingController _customCategoryController =
      TextEditingController();
  final FocusNode _customCategoryFocus = FocusNode();

  late final List<DateTime> _recentDays;
  late DateTime _selectedDate;
  String? _selectedCategory;
  bool _usingCustomCategory = false;

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = _today;
    _recentDays = List.generate(
      _visibleDayCount,
      (index) => _today.subtract(Duration(days: _visibleDayCount - index - 1)),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_dateController.hasClients) return;
      _dateController.jumpTo(_dateController.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _dateController.dispose();
    _customCategoryController.dispose();
    _customCategoryFocus.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dateLabel(DateTime date) {
    if (_isSameDay(date, _today)) {
      return 'Today, ${DateFormat('MMM d').format(date)}';
    }
    if (_isSameDay(date, _today.subtract(const Duration(days: 1)))) {
      return 'Yesterday, ${DateFormat('MMM d').format(date)}';
    }
    return DateFormat('EEEE, MMM d').format(date);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(_today.year - 3),
      lastDate: _today,
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedDate = picked);

    final recentIndex = _recentDays.indexWhere(
      (day) => _isSameDay(day, picked),
    );
    if (recentIndex >= 0 && _dateController.hasClients) {
      const itemExtent = 68.0;
      _dateController.animateTo(
        (recentIndex * itemExtent).clamp(
          0.0,
          _dateController.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _selectSavedCategory(String? name) {
    setState(() {
      _selectedCategory = name;
      _usingCustomCategory = false;
    });
    _customCategoryFocus.unfocus();
  }

  void _selectCustomCategory() {
    setState(() {
      _selectedCategory = null;
      _usingCustomCategory = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _customCategoryFocus.requestFocus();
    });
  }

  void _finish() {
    final customName = _customCategoryController.text.trim();
    if (_usingCustomCategory && customName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a category name first.')),
      );
      _customCategoryFocus.requestFocus();
      return;
    }

    Navigator.of(context).pop(
      QuickAdjustmentDetailsResult(
        categoryName: _usingCustomCategory ? customName : _selectedCategory,
        selectedDate: _selectedDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent = widget.isAdd ? const Color(0xFF16845B) : colors.error;
    final categories = [...widget.categories]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isAdd ? 'Add money' : 'Subtract money'),
        actions: [
          TextButton(
            onPressed: _finish,
            child: const Text(
              'Done',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: _finish,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Done'),
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            minimumSize: const Size.fromHeight(52),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    widget.isAdd ? Icons.add_rounded : Icons.remove_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.sourceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.isAdd ? '+' : '−'}${widget.amount.toStringAsFixed(2)}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          color: accent,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'When?',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _dateLabel(_selectedDate),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Choose from calendar',
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_month_outlined),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 76,
            child: ListView.separated(
              controller: _dateController,
              scrollDirection: Axis.horizontal,
              itemCount: _recentDays.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final day = _recentDays[index];
                final selected = _isSameDay(day, _selectedDate);
                final isToday = _isSameDay(day, _today);
                return Semantics(
                  selected: selected,
                  label: DateFormat('EEEE, MMMM d').format(day),
                  child: InkWell(
                    onTap: () => setState(() => _selectedDate = day),
                    borderRadius: BorderRadius.circular(16),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 60,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: selected ? accent : colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected
                              ? accent
                              : colors.outlineVariant.withValues(alpha: 0.7),
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            isToday
                                ? 'TODAY'
                                : DateFormat('EEE').format(day).toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: selected
                                  ? Colors.white
                                  : colors.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                              fontSize: isToday ? 9 : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${day.day}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: selected ? Colors.white : colors.onSurface,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Category',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Optional — you can simply press Done.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _CategoryTile(
            title: 'No category',
            icon: Icons.do_not_disturb_alt_outlined,
            selected: !_usingCustomCategory && _selectedCategory == null,
            accent: accent,
            onTap: () => _selectSavedCategory(null),
          ),
          ...categories.map(
            (category) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: _CategoryTile(
                title: category.name,
                icon: widget.isAdd
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                selected:
                    !_usingCustomCategory && _selectedCategory == category.name,
                accent: accent,
                onTap: () => _selectSavedCategory(category.name),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _CategoryTile(
              title: 'New category',
              icon: Icons.add_rounded,
              selected: _usingCustomCategory,
              accent: accent,
              onTap: _selectCustomCategory,
            ),
          ),
          if (_usingCustomCategory)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextField(
                controller: _customCategoryController,
                focusNode: _customCategoryFocus,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _finish(),
                decoration: const InputDecoration(
                  labelText: 'Category name',
                  hintText: 'e.g. Salary, Food, Transport',
                  prefixIcon: Icon(Icons.edit_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.title,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? accent.withValues(alpha: 0.09)
          : colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? accent : colors.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: selected
                      ? accent.withValues(alpha: 0.14)
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: selected ? accent : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? accent : colors.outlineVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
