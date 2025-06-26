import 'package:flutter/material.dart';

class Mission {
  final String id;
  final String name;
  final double targetAmount;
  final DateTime startDate;
  final DateTime endDate;
  double spentAmount;

  Mission({
    required this.id,
    required this.name,
    required this.targetAmount,
    required this.startDate,
    required this.endDate,
    this.spentAmount = 0.0,
  });

  double get remainingAmount => targetAmount - spentAmount;

  bool get isOverTarget => remainingAmount < 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'targetAmount': targetAmount,
        'startDate': startDate.toIso8601String(),
        'endDate': endDate.toIso8601String(),
        'spentAmount': spentAmount,
      };

  factory Mission.fromJson(Map<String, dynamic> json) => Mission(
        id: json['id'],
        name: json['name'],
        targetAmount: json['targetAmount'],
        startDate: DateTime.parse(json['startDate']),
        endDate: DateTime.parse(json['endDate']),
        spentAmount: json['spentAmount'],
      );
}
