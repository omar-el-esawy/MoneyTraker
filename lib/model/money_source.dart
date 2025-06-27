class MoneySource {
  final int? id; // Nullable for auto-increment
  final String name;
  double amount;

  // Constructor with id (used for database operations)
  MoneySource({
    this.id,
    required this.name,
    required this.amount,
  });

  // Constructor without id (used for creating new money sources)
  MoneySource.create({
    required this.name,
    required this.amount,
  }) : id = null;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'amount': amount,
      };

  factory MoneySource.fromMap(Map<String, dynamic> map) => MoneySource(
        id: map['id'],
        name: map['name'],
        amount: map['amount'],
      );
}
