enum MoneySourceChangeType {
  created,
  edited,
  add,
  subtract,
  transferIn,
  transferOut,
}

extension MoneySourceChangeTypeDb on MoneySourceChangeType {
  String get dbValue {
    switch (this) {
      case MoneySourceChangeType.created:
        return 'created';
      case MoneySourceChangeType.edited:
        return 'edited';
      case MoneySourceChangeType.add:
        return 'add';
      case MoneySourceChangeType.subtract:
        return 'subtract';
      case MoneySourceChangeType.transferIn:
        return 'transferIn';
      case MoneySourceChangeType.transferOut:
        return 'transferOut';
    }
  }

  static MoneySourceChangeType fromDb(String value) {
    switch (value) {
      case 'created':
        return MoneySourceChangeType.created;
      case 'edited':
        return MoneySourceChangeType.edited;
      case 'add':
        return MoneySourceChangeType.add;
      case 'subtract':
        return MoneySourceChangeType.subtract;
      case 'transferIn':
        return MoneySourceChangeType.transferIn;
      case 'transferOut':
        return MoneySourceChangeType.transferOut;
      default:
        throw Exception('Unknown MoneySourceChangeType: $value');
    }
  }
}

class MoneySourceChange {
  final int? id;
  final int sourceId;
  final double deltaAmount;
  final double resultingAmount;
  final DateTime createdAt;
  final MoneySourceChangeType type;
  final String? note;

  const MoneySourceChange({
    this.id,
    required this.sourceId,
    required this.deltaAmount,
    required this.resultingAmount,
    required this.createdAt,
    required this.type,
    this.note,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'sourceId': sourceId,
      'deltaAmount': deltaAmount,
      'resultingAmount': resultingAmount,
      'createdAt': createdAt.toIso8601String(),
      'type': type.dbValue,
      'note': note,
    };
  }

  factory MoneySourceChange.fromMap(Map<String, dynamic> map) {
    return MoneySourceChange(
      id: map['id'] as int?,
      sourceId: map['sourceId'] as int,
      deltaAmount: (map['deltaAmount'] as num).toDouble(),
      resultingAmount: (map['resultingAmount'] as num).toDouble(),
      createdAt: DateTime.parse(map['createdAt'] as String),
      type: MoneySourceChangeTypeDb.fromDb(map['type'] as String),
      note: map['note'] as String?,
    );
  }
}

