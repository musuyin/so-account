String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String monthKey(DateTime date) => dateKey(date).substring(0, 7);

DateTime parseDate(String value) {
  final date = DateTime.tryParse(value);
  if (date == null || dateKey(date) != value) {
    throw const FormatException('无效日期');
  }
  return DateTime(date.year, date.month, date.day);
}

int ownershipDays(String purchasedOn, DateTime now) {
  final date = parseDate(purchasedOn);
  final today = DateTime.utc(now.year, now.month, now.day);
  final purchased = DateTime.utc(date.year, date.month, date.day);
  if (purchased.isAfter(today)) throw const FormatException('购入日期不能在未来');
  return today.difference(purchased).inDays + 1;
}
