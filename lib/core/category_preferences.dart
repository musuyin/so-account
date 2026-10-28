import 'dart:convert';

const expenseOrderKey = 'category_order_expense';
const incomeOrderKey = 'category_order_income';
const categoryIconsKey = 'category_icons';
const itemCategoryIconsKey = 'item_category_icons';
const itemCategoriesKey = 'item_categories';

/// Missing, repeated and retired keys never hide live categories. New values
/// retain their source order and are appended after the saved prefix.
List<String> resolveCategoryOrder(
  Iterable<String> live,
  Iterable<String> saved,
) {
  final remaining = live.toSet();
  return [
    for (final id in saved)
      if (remaining.remove(id)) id,
    ...remaining,
  ];
}

List<String> decodeCategoryOrder(String? value) {
  if (value == null) return [];
  final decoded = jsonDecode(value);
  if (decoded is! List ||
      decoded.length > 10000 ||
      decoded.any((id) => id is! String || id.length > 100)) {
    throw const FormatException('分类排序无效');
  }
  return decoded.cast<String>();
}

Map<String, String> decodeCategoryIcons(String? value) {
  if (value == null) return {};
  final decoded = jsonDecode(value);
  if (decoded is! Map ||
      decoded.length > 10000 ||
      decoded.entries.any(
        (e) =>
            e.key is! String ||
            (e.key as String).length > 100 ||
            e.value is! String ||
            (e.value as String).length > 100,
      )) {
    throw const FormatException('分类图标配置无效');
  }
  return decoded.cast<String, String>();
}

bool validateCategoryPreference(String key, String value) {
  if ([expenseOrderKey, incomeOrderKey].contains(key)) {
    decodeCategoryOrder(value);
    return true;
  }
  if ([categoryIconsKey, itemCategoryIconsKey].contains(key)) {
    decodeCategoryIcons(value);
    return true;
  }
  return false;
}
