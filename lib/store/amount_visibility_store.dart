import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether money amounts on the home page are visible.
class AmountVisibilityStore {
  static const _key = 'show_amounts';

  static Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? true;
  }

  static Future<void> save(bool showAmounts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, showAmounts);
  }
}
