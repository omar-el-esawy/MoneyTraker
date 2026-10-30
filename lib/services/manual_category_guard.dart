import 'package:shared_preferences/shared_preferences.dart';

/// A category the person picked from a notification, with no bank rule behind it.
/// The next SMS sync leaves that choice in place until a rule matches.
bool keepHandPickedCategory({required bool handPicked, required bool rulePlanned}) {
  return handPicked && !rulePlanned;
}

class ManualCategoryGuard {
  static const _key = 'manual_category_tx_ids';

  static Future<Set<int>> ids() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? const <String>[];
    return raw.map(int.tryParse).whereType<int>().toSet();
  }

  static Future<void> remember(int id) async {
    final current = await ids();
    if (current.contains(id)) return;
    current.add(id);
    await _save(current);
  }

  static Future<void> forgetAll(Set<int> idsToDrop) async {
    if (idsToDrop.isEmpty) return;
    final current = await ids();
    final next = current.difference(idsToDrop);
    if (next.length == current.length) return;
    await _save(next);
  }

  static Future<void> _save(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final values = [for (final id in ids) '$id']..sort();
    await prefs.setStringList(_key, values);
  }
}
