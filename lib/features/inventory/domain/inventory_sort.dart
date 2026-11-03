const inventorySortKey = 'inventory_sort';
const inventorySortOptions = {
  'recent': '最近添加',
  'name': '按名称',
  'price': '价格从高到低',
};

String parseInventorySort(String? value) =>
    inventorySortOptions.containsKey(value) ? value! : 'recent';
