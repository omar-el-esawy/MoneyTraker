enum TagType {
  income,
  expense,
}

extension TagTypeDb on TagType {
  String get dbValue => this == TagType.income ? 'income' : 'expense';

  static TagType fromDb(String v) {
    switch (v) {
      case 'income':
        return TagType.income;
      case 'expense':
        return TagType.expense;
      default:
        throw Exception('Unknown TagType: $v');
    }
  }
}

class Tag {
  final int? id;
  final String name;
  final TagType type;

  const Tag({
    this.id,
    required this.name,
    required this.type,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.dbValue,
    };
  }

  factory Tag.fromMap(Map<String, dynamic> map) {
    return Tag(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: TagTypeDb.fromDb(map['type'] as String),
    );
  }
}

