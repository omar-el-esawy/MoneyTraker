import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'widgets/add_money_source_dialog.dart';
import 'widgets/edit_money_source_dialog.dart';
import 'logic/money_logic.dart';

class TotalMoneyPage extends StatelessWidget {
  final Map<String, double> moneySources;
  final void Function(String, double) onAddSource;
  final void Function(String, String, double) onEditSource;
  final void Function(String) onDeleteSource;

  const TotalMoneyPage({
    super.key,
    required this.moneySources,
    required this.onAddSource,
    required this.onEditSource,
    required this.onDeleteSource,
  });

  void _showAddSourceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AddMoneySourceDialog(
        onAdd: (name, amount) => onAddSource(name, amount),
      ),
    );
  }

  void _showEditSourceDialog(BuildContext context, String oldName, double oldAmount) {
    showDialog(
      context: context,
      builder: (context) => EditMoneySourceDialog(
        oldName: oldName,
        oldAmount: oldAmount,
        onEdit: (newName, newAmount) => onEditSource(oldName, newName, newAmount),
      ),
    );
  }

  void _showDeleteConfirmationDialog(BuildContext context, String sourceName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Money Source'),
        content: Text('Are you sure you want to delete "$sourceName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              onDeleteSource(sourceName);
              Navigator.of(context).pop();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = moneySources.values.fold<double>(0, (a, b) => a + b);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Centered total money display
          Center(
            child: Column(
              children: [
                Text(
                  'Total Money',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  total.toStringAsFixed(2),
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // List of money sources
          ...moneySources.entries.map((entry) {
            return Card(
              child: ListTile(
                title: Text('${entry.key}: ${entry.value.toStringAsFixed(2)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const FaIcon(FontAwesomeIcons.edit), // Replaced with Font Awesome icon
                      onPressed: () => _showEditSourceDialog(context, entry.key, entry.value),
                    ),
                    IconButton(
                      icon: const FaIcon(FontAwesomeIcons.trashCan), // Replaced with Font Awesome icon
                      onPressed: () => _showDeleteConfirmationDialog(context, entry.key),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: ElevatedButton.icon(
                onPressed: () => _showAddSourceDialog(context),
                icon: const Icon(Icons.add),
                label: const Text('Add Money Source'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
