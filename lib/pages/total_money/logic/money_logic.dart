import 'package:money_traker/model/money_source.dart';

class MoneyLogic {
  final List<MoneySource> _sources = [];

  void storeSources(List<Map<String, double>> sources) {
    _sources.clear();
    for (var entry in sources) {
      entry.forEach((name, amount) {
        _sources.add(MoneySource(
          name: name,
          amount: amount,
        ));
      });
    }
  }

  double getTotalMoney() {
    return _sources.fold(0.0, (sum, source) => sum + source.amount);
  }

  List<MoneySource> get sources => List.unmodifiable(_sources);
}
