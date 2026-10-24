import 'package:money_traker/data/database_helper.dart';
import 'package:money_traker/domain/entities/transaction_entity.dart';

class TransactionRepository {
  TransactionRepository._();
  static final TransactionRepository instance = TransactionRepository._();

  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<List<TransactionEntity>> getAll() async {
    return _db.getAllTransactions();
  }

  Future<int> insert(TransactionEntity transaction) async {
    return _db.insertTransaction(transaction);
  }

  Future<TransactionEntity> upsert(TransactionEntity transaction) async {
    return _db.upsertTransaction(transaction);
  }

  Future<List<TransactionEntity>> getRecentFromSms({int limit = 20}) async {
    final db = await _db.database;
    final result = await db.query(
      'transactions',
      where: 'sms_id IS NOT NULL',
      orderBy: 'date DESC',
      limit: limit,
    );
    return result.map(TransactionEntity.fromMap).toList();
  }
}

