class Mission {
  final int? id;
  final String name;
  final double targetAmount;
  final DateTime startDate;
  final DateTime endDate;

  Mission({
    this.id,
    required this.name,
    required this.targetAmount,
    required this.startDate,
    required this.endDate,
  });

  Mission.create({
    required this.name,
    required this.targetAmount,
    required this.startDate,
    required this.endDate,
  }) : id = null;

  Mission copyWith({
    int? id,
    String? name,
    double? targetAmount,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return Mission(
      id: id ?? this.id,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'targetAmount': targetAmount,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
    };
  }

  factory Mission.fromMap(Map<String, dynamic> map) {
    return Mission(
      id: map['id'],
      name: map['name'],
      targetAmount: map['targetAmount'],
      startDate: DateTime.parse(map['startDate']),
      endDate: DateTime.parse(map['endDate']),
    );
  }
}
