class MoneySource {
  final int? id;
  final String name;
  final double amount;

  MoneySource({
    this.id,
    required this.name,
    required this.amount,
  });

  MoneySource.create({
    required this.name,
    required this.amount,
  }) : id = null;

  MoneySource copyWith({
    int? id,
    String? name,
    double? amount,
  }) {
    return MoneySource(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'amount': amount,
    };
  }

  factory MoneySource.fromMap(Map<String, dynamic> map) {
    return MoneySource(
      id: map['id'],
      name: map['name'],
      amount: map['amount'],
    );
  }
}
