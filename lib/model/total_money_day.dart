class TotalMoneyDay {
  final int? id;
  final DateTime date;
  final double totalAmount;
  final String? note;

  TotalMoneyDay({
    this.id,
    required this.date,
    required this.totalAmount,
    this.note,
  });

  TotalMoneyDay.create({
    required this.date,
    required this.totalAmount,
    this.note,
  }) : id = null;

  TotalMoneyDay copyWith({
    int? id,
    DateTime? date,
    double? totalAmount,
    String? note,
  }) {
    return TotalMoneyDay(
      id: id ?? this.id,
      date: date ?? this.date,
      totalAmount: totalAmount ?? this.totalAmount,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'totalAmount': totalAmount,
      'note': note,
    };
  }

  factory TotalMoneyDay.fromMap(Map<String, dynamic> map) {
    return TotalMoneyDay(
      id: map['id'],
      date: DateTime.parse(map['date']),
      totalAmount: map['totalAmount'],
      note: map['note'],
    );
  }
}
