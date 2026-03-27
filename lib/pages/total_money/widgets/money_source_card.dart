import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

class MoneySourceCard extends StatelessWidget {
  final String sourceName;
  final double amount;
  final bool showAmount;
  final void Function(String, double) onEdit;
  final VoidCallback onDelete;

  const MoneySourceCard({
    super.key,
    required this.sourceName,
    required this.amount,
    required this.showAmount,
    required this.onEdit,
    required this.onDelete,
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
    const double cardHeight = 56;

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
      child: GestureDetector(
        onTap: () => onEdit(sourceName, amount),
        child: Container(
          height: cardHeight,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.zero,
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
                child: Text(
                  showAmount
                      ? '$sourceName: ${amount.toStringAsFixed(2)}'
                      : '$sourceName: ****',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              IconButton(
                tooltip: 'Delete',
                onPressed: () => _showDeleteConfirmationDialog(context),
                icon: const Icon(Icons.delete_outline),
                color: Theme.of(context).colorScheme.error,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
