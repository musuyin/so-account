import 'package:flutter/material.dart';

import 'category_icons.dart';

class CategoryIconField extends StatelessWidget {
  const CategoryIconField({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final option = categoryIconCatalog.where((o) => o.id == value).firstOrNull;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(categoryIcon('', iconId: value)),
      title: Text('图标：${option?.name ?? '通用分类'}'),
      trailing: const Text('更换'),
      onTap: () async {
        final result = await showDialog<String>(
          context: context,
          builder: (_) => CategoryIconPicker(value: value),
        );
        if (result != null) onChanged(result);
      },
    );
  }
}

class CategoryIconPicker extends StatefulWidget {
  const CategoryIconPicker({super.key, required this.value});
  final String value;
  @override
  State<CategoryIconPicker> createState() => _CategoryIconPickerState();
}

class _CategoryIconPickerState extends State<CategoryIconPicker> {
  String search = '';
  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.all(12),
    title: const Text('选择图标'),
    content: SizedBox(
      width: 520,
      height: MediaQuery.sizeOf(context).height * .65,
      child: Column(
        children: [
          Row(
            children: [
              Icon(categoryIcon('', iconId: widget.value), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '当前：${categoryIconCatalog.where((o) => o.id == widget.value).firstOrNull?.name ?? '通用分类'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(
              labelText: '搜索图标',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) =>
                setState(() => search = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                if (!categoryIconCatalog.any(
                  (o) => '${o.name} ${o.group} ${o.id}'.toLowerCase().contains(
                    search,
                  ),
                ))
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('没有匹配的图标'),
                  ),
                for (final group in const [
                  '餐饮',
                  '居家',
                  '出行',
                  '购物',
                  '数码',
                  '文娱',
                  '健康',
                  '工作收入',
                ])
                  if (categoryIconCatalog.any(
                    (o) =>
                        o.group == group &&
                        '${o.name} ${o.group} ${o.id}'.toLowerCase().contains(
                          search,
                        ),
                  )) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Text(group),
                    ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final option in categoryIconCatalog.where(
                          (o) =>
                              o.group == group &&
                              '${o.name} ${o.group} ${o.id}'
                                  .toLowerCase()
                                  .contains(search),
                        ))
                          ChoiceChip(
                            avatar: Icon(option.icon, size: 20),
                            label: Text(option.name),
                            selected: widget.value == option.id,
                            onSelected: (_) =>
                                Navigator.pop(context, option.id),
                          ),
                      ],
                    ),
                  ],
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    ],
  );
}
