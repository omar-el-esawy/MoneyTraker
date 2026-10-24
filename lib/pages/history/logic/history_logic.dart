import 'package:money_traker/model/total_money_day.dart';

enum ChangeType { increase, decrease, same }

ChangeType getChangeType(TotalMoneyDay previous, TotalMoneyDay current) {
  if (current.totalAmount > previous.totalAmount) {
    return ChangeType.increase;
  } else if (current.totalAmount < previous.totalAmount) {
    return ChangeType.decrease;
  } else {
    return ChangeType.same;
  }
}
