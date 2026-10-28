import 'dart:convert';

// Fallback for ledgers and backups predating persisted item configuration.
// Current first-use defaults are seeded once by AppDatabase.
const legacyItemCategoryDefaults = [
  '数码产品',
  '日用品',
  '食物',
  '周边',
  '家具',
  '衣物',
  '其他',
];

List<String> itemTags(String value) {
  if (value.startsWith('[')) {
    try {
      return (jsonDecode(value) as List).cast<String>();
    } catch (_) {}
  }
  return value.isEmpty ? [] : [value];
}

String encodeItemTags(Iterable<String> values) =>
    jsonEncode(values.toSet().toList());

List<String> configuredItemCategories(String? value) => value == null
    ? [...legacyItemCategoryDefaults]
    : validateItemCategories(value);

List<String> validateItemCategories(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! List ||
      decoded.length > 10000 ||
      decoded.any(
        (v) => v is! String || v.trim() != v || v.isEmpty || v.length > 80,
      )) {
    throw const FormatException('物品种类配置无效，名称最多 80 字，最多 10000 种');
  }
  return decoded.cast<String>().toSet().toList();
}

const itemStatuses = {'unused': '未使用', 'active': '使用中', 'completed': '使用完'};
