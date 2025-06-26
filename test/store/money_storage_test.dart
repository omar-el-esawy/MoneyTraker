import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/model/money_source.dart';
import 'package:money_traker/model/total_money_day.dart';
import 'package:money_traker/store/money_storage.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'money_storage_test.mocks.dart';

@GenerateMocks([File])
void main() {
  late MockFile mockFile;
  late MoneyStorage storage;

  setUp(() {
    mockFile = MockFile();

    // Provide fake directory and file creation logic
    storage = MoneyStorage(
      directoryProvider: () async => Directory('/mock'),
      fileFactory: (_) => mockFile,
    );
  });

  group('saveMoneySources', () {
    test('writes correct JSON', () async {
      final sources = [
        MoneySource(name: 'Source1', amount: 100.0),
        MoneySource(name: 'Source2', amount: 200.0),
      ];

      when(mockFile.writeAsString(any)).thenAnswer((_) async => mockFile);

      await storage.saveMoneySources(sources);

      final expectedJson = jsonEncode([
        {'name': 'Source1', 'amount': 100.0},
        {'name': 'Source2', 'amount': 200.0},
      ]);
      verify(mockFile.writeAsString(expectedJson)).called(1);
    });
  });

  group('loadMoneySources', () {
    test('loads from JSON file', () async {
      final content = jsonEncode([
        {'name': 'Source1', 'amount': 100.0},
        {'name': 'Source2', 'amount': 200.0},
      ]);

      when(mockFile.exists()).thenAnswer((_) async => true);
      when(mockFile.readAsString()).thenAnswer((_) async => content);

      final sources = await storage.loadMoneySources();

      expect(sources.length, 2);
      expect(sources[0].name, 'Source1');
      expect(sources[1].amount, 200.0);
    });

    test('returns empty list if file missing', () async {
      when(mockFile.exists()).thenAnswer((_) async => false);

      final sources = await storage.loadMoneySources();
      expect(sources, isEmpty);
    });
  });

  group('updateMoneySourceAmount', () {
    test('updates specific entry', () async {
      final original = [
        {'name': 'Source1', 'amount': 100.0},
        {'name': 'Source2', 'amount': 200.0},
      ];

      when(mockFile.exists()).thenAnswer((_) async => true);
      when(mockFile.readAsString())
          .thenAnswer((_) async => jsonEncode(original));
      when(mockFile.writeAsString(any)).thenAnswer((_) async => mockFile);

      await storage.updateMoneySourceAmount('Source1', 150.0);

      verify(mockFile.writeAsString(jsonEncode([
        {'name': 'Source1', 'amount': 150.0},
        {'name': 'Source2', 'amount': 200.0},
      ]))).called(1);
    });
  });

  group('saveHistory', () {
    test('writes correct JSON', () async {
      final history = [
        TotalMoneyDay(date: DateTime(2023, 1, 1), totalAmount: 100.0),
        TotalMoneyDay(date: DateTime(2023, 1, 2), totalAmount: 200.0),
      ];

      when(mockFile.writeAsString(any)).thenAnswer((_) async => mockFile);
      await storage.saveHistory(history);

      verify(mockFile.writeAsString(jsonEncode([
        {'date': '2023-01-01T00:00:00.000', 'totalAmount': 100.0},
        {'date': '2023-01-02T00:00:00.000', 'totalAmount': 200.0},
      ]))).called(1);
    });
  });

  group('loadHistory', () {
    test('loads from JSON file', () async {
      final content = jsonEncode([
        {'date': '2023-01-01T00:00:00.000', 'totalAmount': 500.0},
        {'date': '2023-01-02T00:00:00.000', 'totalAmount': 600.0},
      ]);

      when(mockFile.exists()).thenAnswer((_) async => true);
      when(mockFile.readAsString()).thenAnswer((_) async => content);

      final history = await storage.loadHistory();

      expect(history.length, 2);
      expect(history[0].totalAmount, 500.0);
      expect(history[1].date, DateTime(2023, 1, 2));
    });

    test('returns empty list if file not found', () async {
      when(mockFile.exists()).thenAnswer((_) async => false);

      final history = await storage.loadHistory();
      expect(history, isEmpty);
    });
  });

  group('updateTotalMoneyOfDay', () {
    test('updates total if date exists', () async {
      final history = [
        {'date': '2023-01-01T00:00:00.000', 'totalAmount': 100.0},
      ];

      when(mockFile.exists()).thenAnswer((_) async => true);
      when(mockFile.readAsString())
          .thenAnswer((_) async => jsonEncode(history));
      when(mockFile.writeAsString(any)).thenAnswer((_) async => mockFile);

      await storage.updateTotalMoneyOfDay(DateTime(2023, 1, 1), 200.0);

      verify(mockFile.writeAsString(jsonEncode([
        {'date': '2023-01-01T00:00:00.000', 'totalAmount': 200.0}
      ]))).called(1);
    });

    test('adds new date if not present', () async {
      final history = [
        {'date': '2023-01-01T00:00:00.000', 'totalAmount': 100.0},
      ];

      when(mockFile.exists()).thenAnswer((_) async => true);
      when(mockFile.readAsString())
          .thenAnswer((_) async => jsonEncode(history));
      when(mockFile.writeAsString(any)).thenAnswer((_) async => mockFile);

      await storage.updateTotalMoneyOfDay(DateTime(2023, 1, 2), 300.0);

      verify(mockFile.writeAsString(jsonEncode([
        {'date': '2023-01-01T00:00:00.000', 'totalAmount': 100.0},
        {'date': '2023-01-02T00:00:00.000', 'totalAmount': 300.0}
      ]))).called(1);
    });
  });
}
