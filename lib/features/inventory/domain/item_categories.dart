import 'dart:convert';

import 'item_cost.dart';

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

List<String> configuredItemCategories(String? value) =>
    value == null ? [...itemCategories] : validateItemCategories(value);

List<String> validateItemCategories(String value) {
  final decoded = jsonDecode(value);
  if (decoded is! List ||
      decoded.length > 100 ||
      decoded.any(
        (v) => v is! String || v.trim() != v || v.isEmpty || v.length > 40,
      ) ||
      decoded.toSet().length != decoded.length) {
    throw const FormatException('物品种类须为不重复的 1–40 字名称，最多 100 种');
  }
  return decoded.cast<String>();
}

const itemStatuses = {'unused': '未使用', 'active': '使用中', 'completed': '使用完'};
