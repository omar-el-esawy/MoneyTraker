import 'package:money_traker/model/tag.dart';

class SuggestedCategory {
  final int? tagId;
  final String name;
  final TagType type;

  const SuggestedCategory({
    this.tagId,
    required this.name,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
        'tagId': tagId,
        'name': name,
        'type': type.dbValue,
      };

  factory SuggestedCategory.fromJson(Map<String, dynamic> json) {
    final typeName = json['type']?.toString();
    return SuggestedCategory(
      tagId: (json['tagId'] as num?)?.toInt(),
      name: json['name']?.toString() ?? '',
      type: typeName == TagType.income.dbValue ? TagType.income : TagType.expense,
    );
  }
}

const expenseCategoryFallbacks = ['Food', 'Transport', 'Shopping'];
const incomeCategoryFallbacks = ['Salary', 'Transfer', 'Gift'];

/// The categories a person already uses the most, filled out to [limit]
/// with everyday names when they have fewer than that.
List<SuggestedCategory> suggestFamousCategories({
  required TagType type,
  required List<Tag> tags,
  required Map<int, int> usageByTagId,
  int limit = 3,
}) {
  final ranked = tags.where((tag) {
    final name = tag.name.trim().toLowerCase();
    return tag.type == type && tag.id != null && name.isNotEmpty && name != 'others';
  }).toList()
    ..sort((a, b) {
      final byUse = (usageByTagId[b.id!] ?? 0).compareTo(usageByTagId[a.id!] ?? 0);
      if (byUse != 0) return byUse;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  final picked = <SuggestedCategory>[];
  final names = <String>{};
  for (final tag in ranked) {
    if (picked.length >= limit) break;
    final key = tag.name.trim().toLowerCase();
    if (!names.add(key)) continue;
    picked.add(SuggestedCategory(tagId: tag.id, name: tag.name.trim(), type: type));
  }

  final fallbacks = type == TagType.expense ? expenseCategoryFallbacks : incomeCategoryFallbacks;
  for (final name in fallbacks) {
    if (picked.length >= limit) break;
    if (!names.add(name.toLowerCase())) continue;
    picked.add(SuggestedCategory(name: name, type: type));
  }
  return picked;
}
