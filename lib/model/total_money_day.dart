class TotalMoneyDay {
  final int? id; // Nullable for auto-increment
  final DateTime date;
  final double totalAmount;
  final String? note; // Optional note

  // Constructor with id (used for database operations)
  TotalMoneyDay({
    this.id,
    required this.date,
    required this.totalAmount,
    this.note,
  });

  // Constructor without id (used for creating new total money days)
  TotalMoneyDay.create({
    required this.date,
    required this.totalAmount,
    this.note,
  }) : id = null;

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date.toIso8601String(),
        'totalAmount': totalAmount,
        'note': note,
      };

  factory TotalMoneyDay.fromMap(Map<String, dynamic> map) => TotalMoneyDay(
        id: map['id'],
        date: DateTime.parse(map['date']),
        totalAmount: map['totalAmount'],
        note: map['note'],
      );
}
