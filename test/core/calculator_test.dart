import 'package:flutter_test/flutter_test.dart';
import 'package:so_account/core/money/calculator.dart';

void main() {
  test('calculator uses precedence and exact decimal rounding', () {
    expect(calculateMinor('0.1+0.2', 'CNY'), 30);
    expect(calculateMinor('10+2×3-4÷2', 'CNY'), 1400);
    expect(calculateMinor('1÷3', 'CNY'), 33);
    expect(calculateMinor('1÷8', 'CNY'), 13);
    expect(calculateMinor('9÷2', 'JPY'), 5);
    for (final input in ['2÷0', '1+', '-1', '1..2', '99999999999999×9']) {
      expect(() => calculateMinor(input, 'CNY'), throwsFormatException);
    }
  });
}
