const currencies = ['CNY', 'USD', 'EUR', 'GBP', 'JPY', 'HKD'];

int fractionDigits(String currency) {
  if (!currencies.contains(currency)) {
    throw ArgumentError('不支持的币种');
  }
  return currency == 'JPY' ? 0 : 2;
}

/// Parse decimal input without a floating point round trip.
int parseMoney(String input, String currency, {bool signed = false}) {
  final text = input.trim();
  final digits = fractionDigits(currency);
  final pattern = signed ? r'^-?\d+(\.\d+)?$' : r'^\d+(\.\d+)?$';
  if (!RegExp(pattern).hasMatch(text)) throw const FormatException('请输入有效金额');
  final negative = text.startsWith('-');
  final parts = (negative ? text.substring(1) : text).split('.');
  final fraction = parts.length == 2 ? parts[1] : '';
  if (fraction.length > digits) throw FormatException('此币种最多 $digits 位小数');
  final factor = digits == 0 ? 1 : 100;
  final value = int.tryParse(parts[0]);
  if (value == null || value > 9999999999) throw const FormatException('金额过大');
  final minor =
      value * factor +
      (fraction.isEmpty ? 0 : int.parse(fraction.padRight(digits, '0')));
  return negative ? -minor : minor;
}

String decimalMoney(int minor, String currency) {
  final digits = fractionDigits(currency);
  final sign = minor < 0 ? '-' : '';
  final value = minor.abs();
  return digits == 0
      ? '$sign$value'
      : '$sign${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';
}

String money(int minor, String currency) =>
    '$currency ${decimalMoney(minor, currency)}';
