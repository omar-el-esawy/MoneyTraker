import 'package:flutter/material.dart';

class Mission {
  final int? id; // Nullable for auto-increment
  final String name;
  final double targetAmount;
  final DateTime startDate;
  final DateTime endDate;
  double spentAmount;

  // Constructor with id (used for database operations)
  Mission({
    this.id,
    required this.name,
    required this.targetAmount,
    required this.startDate,
    required this.endDate,
    this.spentAmount = 0.0,
  });

  // Constructor without id (used for creating new missions)
  Mission.create({
    required this.name,
    required this.targetAmount,
    required this.startDate,
    required this.endDate,
    this.spentAmount = 0.0,
  }) : id = null;

  double get remainingAmount => targetAmount - spentAmount;

  bool get isOverTarget => remainingAmount < 0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'targetAmount': targetAmount,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'spentAmount': spentAmount,
      };

  factory Mission.fromMap(Map<String, dynamic> map) => Mission(
        id: map['id'],
        name: map['name'],
        targetAmount: map['targetAmount'],
        startDate: DateTime.parse(map['startDate']),
        endDate: DateTime.parse(map['endDate']),
        spentAmount: map['spentAmount'],
      );
}
