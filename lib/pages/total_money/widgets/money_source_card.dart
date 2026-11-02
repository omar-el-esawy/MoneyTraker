import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:money_traker/pages/widgets/obscurable_amount.dart';

class MoneySourceCard extends StatelessWidget {
  final String sourceName;
  final double amount;
  final bool showAmount;
  final void Function(String, double) onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAdd;
  final VoidCallback onSubtract;
  final VoidCallback onTransfer;

  const MoneySourceCard({
    super.key,
    required this.sourceName,
    required this.amount,
    required this.showAmount,
    required this.onEdit,
    required this.onDelete,
    required this.onAdd,
    required this.onSubtract,
    required this.onTransfer,
  });

  Future<void> _showDeleteConfirmationDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Money Source'),
        content: Text('Are you sure you want to delete "$sourceName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      onDelete();
    }
  }

  @override
  Widget build(BuildContext context) {
    const double cardHeight = 60;
    final style = Theme.of(context).textTheme.bodyLarge;

    return Slidable(
      key: ValueKey(sourceName),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.25,
        children: [
          SlidableAction(
            onPressed: (_) => _showDeleteConfirmationDialog(context),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Delete',
            flex: 1,
            spacing: 0,
            autoClose: true,
          ),
        ],
      ),
      child: Container(
        height: cardHeight,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8ECE8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onEdit(sourceName, amount),
                child: Text.rich(
                  TextSpan(
                    style: style,
                    children: [
                      TextSpan(text: '$sourceName: '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: ObscurableAmount(
                          amount: amount.toStringAsFixed(2),
                          visible: showAmount,
                          style: style,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            _SourceActionIcon(
              tooltip: 'Add',
              icon: Icons.add,
              color: const Color(0xFF1B5E20),
              background: const Color(0xFFE8F5E9),
              onPressed: onAdd,
            ),
            _SourceActionIcon(
              tooltip: 'Subtract',
              icon: Icons.remove,
              color: const Color(0xFFC62828),
              background: const Color(0xFFFFEBEE),
              onPressed: onSubtract,
            ),
            _SourceActionIcon(
              tooltip: 'Transfer',
              icon: Icons.swap_horiz,
              color: const Color(0xFF1565C0),
              background: const Color(0xFFE3F2FD),
              onPressed: onTransfer,
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceActionIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color color;
  final Color background;
  final VoidCallback onPressed;

  const _SourceActionIcon({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.background,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 28,
              height: 28,
              child: Icon(icon, size: 16, color: color),
            ),
          ),
        ),
      ),
    );
  }
}
