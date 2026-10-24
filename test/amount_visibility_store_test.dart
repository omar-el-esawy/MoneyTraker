import 'package:flutter_test/flutter_test.dart';
import 'package:money_traker/store/amount_visibility_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('amount visibility defaults to shown and round-trips', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await AmountVisibilityStore.load(), isTrue);

    await AmountVisibilityStore.save(false);
    expect(await AmountVisibilityStore.load(), isFalse);

    await AmountVisibilityStore.save(true);
    expect(await AmountVisibilityStore.load(), isTrue);
  });
}
