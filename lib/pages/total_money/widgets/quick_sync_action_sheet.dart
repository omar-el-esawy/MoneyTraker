import 'package:flutter/material.dart';
import 'package:money_traker/model/resource_sync_config.dart';
import 'package:money_traker/model/money_source.dart';
import 'resource_sync_sheet.dart';
/// Shows a quick action sheet after a transaction to optionally sync to a resource
class QuickSyncActionSheet extends StatelessWidget {
  final String transactionType; // "Income" or "Expense"
  final double amount;
  final List<MoneySource> availableResources;
  final Function(ResourceSyncResult result) onSync;
  const QuickSyncActionSheet({
    Key? key,
    required this.transactionType,
    required this.amount,
    required this.availableResources,
    required this.onSync,
  }) : super(key: key);
  static Future<void> showAndSync(
    BuildContext context, {
    required String transactionType,
    required double amount,
    required List<MoneySource> availableResources,
    required Function(ResourceSyncResult result) onSync,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => QuickSyncActionSheet(
        transactionType: transactionType,
        amount: amount,
        availableResources: availableResources,
        onSync: onSync,
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: transactionType == "Income"
                          ? const Color(0xFFECFDF5)
                          : const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      transactionType == "Income"
                          ? Icons.trending_up
                          : Icons.trending_down,
                      color: transactionType == "Income"
                          ? const Color(0xFF059669)
                          : const Color(0xFFDC2626),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add to Money Resource?',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Automatically sync this $transactionType to a money account',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: const Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: transactionType == "Income"
                      ? const Color(0xFFF0FDF4)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: transactionType == "Income"
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFECDCD),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      transactionType,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            color: transactionType == "Income"
                                ? const Color(0xFF047857)
                                : const Color(0xFFB91C1C),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '\$${amount.toStringAsFixed(2)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            color: transactionType == "Income"
                                ? const Color(0xFF059669)
                                : const Color(0xFFDC2626),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF3F4F6),
                        foregroundColor: const Color(0xFF6B7280),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Skip'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: transactionType == "Income"
                            ? const Color(0xFF059669)
                            : const Color(0xFFDC2626),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        final result = await showResourceSyncSheet(
                          context,
                          availableResources: availableResources,
                          title: 'Select Account',
                          subtitle: 'Choose where to add this transaction',
                          showSyncTypeSelector: false,
                        );
                        if (result != null) {
                          onSync(result);
                        }
                      },
                      child: const Text('Add to Account'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
