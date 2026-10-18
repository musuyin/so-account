import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/core/money/money.dart';
import 'package:so_account/core/time/business_date.dart';

void main() {
  test('decimal input uses exact minor units and validates precision', () {
    expect(parseMoney('0.29', 'CNY'), 29);
    expect(parseMoney('12.3', 'USD'), 1230);
    expect(parseMoney('-2.01', 'CNY', signed: true), -201);
    expect(parseMoney('200', 'JPY'), 200);
    for (final text in ['1.001', '-1', 'NaN', '1e4', '1,000', '']) {
      expect(() => parseMoney(text, 'CNY'), throwsFormatException);
    }
    expect(() => parseMoney('1.0', 'JPY'), throwsFormatException);
    expect(decimalMoney(-201, 'CNY'), '-2.01');
  });
  test(
    'business dates reject normalized invalid dates and count calendar days',
    () {
      expect(() => parseDate('2026-02-30'), throwsFormatException);
      expect(ownershipDays('2026-10-18', DateTime(2026, 10, 18, 23)), 1);
      expect(ownershipDays('2024-02-28', DateTime(2024, 3, 1)), 3);
      expect(
        () => ownershipDays('2026-10-19', DateTime(2026, 10, 18)),
        throwsFormatException,
      );
    },
  );
}
