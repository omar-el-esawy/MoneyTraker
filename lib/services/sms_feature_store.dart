import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:money_traker/sms/sms_models.dart';

class SmsFeatureStore {
  SmsFeatureStore._();
  static final SmsFeatureStore instance = SmsFeatureStore._();

  static const prefsKey = 'sms_feature_config_v1';

  Future<SmsFeatureConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null || raw.isEmpty) {
      final code = WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'ar' ? 'ar' : 'en';
      return SmsFeatureConfig.fresh(languageCode: code);
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return SmsFeatureConfig.fresh();
    return SmsFeatureConfig.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> save(SmsFeatureConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, jsonEncode(config.toJson()));
  }

  Future<int> bumpRuleVersion(String bankId) async {
    final config = await load();
    var next = 1;
    final banks = [
      for (final bank in config.banks)
        if (bank.id == bankId)
          bank.copyWith(ruleVersion: next = bank.ruleVersion + 1)
        else
          bank,
    ];
    await save(config.copyWith(banks: banks));
    return next;
  }
}
