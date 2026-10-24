import 'package:flutter/material.dart';
import 'package:money_traker/model/resource_sync_config.dart';
import 'package:money_traker/model/money_source_change.dart';
import 'package:money_traker/model/money_source.dart';
import 'package:money_traker/store/money_storage.dart';
/// Manages syncing money from a transaction (income/expense) to a money resource
class ResourceSyncManager {
  final MoneyStorage _storage = MoneyStorage();
  /// Sync a transaction amount to a money resource
  /// 
  /// [amount] should be positive. The actual change applied depends on [syncType]:
  /// - income: adds amount to resource
  /// - expense: subtracts amount from resource
  /// - both: not applicable for single transaction
  Future<void> syncAmountToResource({
    required MoneySource resource,
    required double amount,
    required SyncType syncType,
    required DateTime transactionDate,
    String? note,
  }) async {
    if (amount <= 0) return;
    double deltaAmount = 0;
    if (syncType == SyncType.income) {
      deltaAmount = amount;
    } else if (syncType == SyncType.expense) {
      deltaAmount = -amount;
    }
    if (deltaAmount == 0 || resource.id == null) return;
    final updatedResource = resource.copyWith(
      amount: resource.amount + deltaAmount,
    );
    await _storage.updateMoneySource(updatedResource);
    // Log the change
    await _storage.addMoneySourceChange(
      MoneySourceChange(
        sourceId: resource.id!,
        deltaAmount: deltaAmount,
        resultingAmount: updatedResource.amount,
        createdAt: transactionDate,
        type: deltaAmount > 0 ? MoneySourceChangeType.add : MoneySourceChangeType.subtract,
        note: note,
      ),
    );
  }
  /// Get all available resources
  Future<List<MoneySource>> getResources() async {
    return await _storage.getMoneySources();
  }
}
