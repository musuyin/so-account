import 'money.dart';

class _Fraction {
  _Fraction(this.n, this.d);
  final BigInt n, d;
  _Fraction add(_Fraction b) => _Fraction(n * b.d + b.n * d, d * b.d);
  _Fraction multiply(_Fraction b) => _Fraction(n * b.n, d * b.d);
  _Fraction divide(_Fraction b) {
    if (b.n == BigInt.zero) throw const FormatException('不能除以零');
    return _Fraction(n * b.d, d * b.n);
  }
}

/// Exact rational arithmetic; round half up only once, to the currency unit.
int calculateMinor(String source, String currency) {
  final input = source
      .replaceAll('×', '*')
      .replaceAll('÷', '/')
      .replaceAll(' ', '');
  if (input.isEmpty || input.length > 120) {
    throw const FormatException('请输入金额或简易算式');
  }
  var pos = 0;
  _Fraction number() {
    var sign = BigInt.one;
    if (pos < input.length && input[pos] == '-') {
      sign = -sign;
      pos++;
    }
    final start = pos;
    while (pos < input.length && RegExp(r'[0-9.]').hasMatch(input[pos])) {
      pos++;
    }
    final text = input.substring(start, pos);
    if (!RegExp(r'^\d+(\.\d{1,8})?$').hasMatch(text)) {
      throw const FormatException('算式不完整或小数位过多');
    }
    final parts = text.split('.');
    final digits = parts.length == 2 ? parts[1].length : 0;
    return _Fraction(
      sign * BigInt.parse(text.replaceAll('.', '')),
      BigInt.from(10).pow(digits),
    );
  }

  _Fraction term() {
    var value = number();
    while (pos < input.length && '*/'.contains(input[pos])) {
      final op = input[pos++];
      final b = number();
      value = op == '*' ? value.multiply(b) : value.divide(b);
    }
    return value;
  }

  var value = term();
  while (pos < input.length && '+-'.contains(input[pos])) {
    final op = input[pos++];
    final b = term();
    value = value.add(op == '+' ? b : _Fraction(-b.n, b.d));
  }
  if (pos != input.length || value.d == BigInt.zero) {
    throw const FormatException('无效算式');
  }
  if (value.d.isNegative) value = _Fraction(-value.n, -value.d);
  if (value.n.isNegative) throw const FormatException('金额不能为负数');
  final scaled = value.n * BigInt.from(fractionDigits(currency) == 0 ? 1 : 100);
  final result = (scaled * BigInt.two + value.d) ~/ (value.d * BigInt.two);
  if (result > BigInt.from(999999999999)) throw const FormatException('金额过大');
  return result.toInt();
}
