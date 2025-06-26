class TotalMoneyDay {
  DateTime date;
  double totalAmount;

  TotalMoneyDay({required this.date, required this.totalAmount});

  Map<String, dynamic> toMap() => {
        'date': date.toIso8601String(),
        'totalAmount': totalAmount,
      };

  factory TotalMoneyDay.fromMap(Map<String, dynamic> map) => TotalMoneyDay(
        date: DateTime.parse(map['date']),
        totalAmount: map['totalAmount'],
      );
}
