import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/model/tag.dart';
import 'package:money_traker/services/category_suggestions.dart';
import 'package:money_traker/services/manual_category_guard.dart';

void main() {
  test('famous categories are the ones used most', () {
    final tags = [
      const Tag(id: 1, name: 'Food', type: TagType.expense),
      const Tag(id: 2, name: 'Rent', type: TagType.expense),
      const Tag(id: 3, name: 'Coffee', type: TagType.expense),
      const Tag(id: 4, name: 'Others', type: TagType.expense),
      const Tag(id: 5, name: 'Salary', type: TagType.income),
    ];

    final picked = suggestFamousCategories(
      type: TagType.expense,
      tags: tags,
      usageByTagId: const {1: 2, 2: 9, 3: 4, 4: 100, 5: 50},
    );

    expect(picked.map((item) => item.name).toList(), ['Rent', 'Coffee', 'Food']);
  });

  test('everyday names fill the list when there are fewer than three', () {
    final picked = suggestFamousCategories(
      type: TagType.income,
      tags: const [Tag(id: 8, name: 'Salary', type: TagType.income)],
      usageByTagId: const {8: 3},
    );

    expect(picked.map((item) => item.name).toList(), ['Salary', 'Transfer', 'Gift']);
    expect(picked.first.tagId, 8);
    expect(picked[1].tagId, isNull);
  });

  test('a hand-picked category stays until a bank rule plans it', () {
    expect(keepHandPickedCategory(handPicked: true, rulePlanned: false), isTrue);
    expect(keepHandPickedCategory(handPicked: true, rulePlanned: true), isFalse);
    expect(keepHandPickedCategory(handPicked: false, rulePlanned: false), isFalse);
  });
}
