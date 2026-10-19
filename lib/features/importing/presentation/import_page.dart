import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../platform/files/file_delivery.dart';
import '../../ledger/domain/entry_kind.dart';
import '../domain/import_table.dart';
import '../domain/import_plan.dart';

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key, this.initialTables});
  final List<ImportTable>? initialTables;
  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  late List<ImportTable> tables = widget.initialTables ?? [];
  int sheet = 0;
  final mapping = ImportMapping();
  List<ImportResult>? results;
  final selected = <int>{};
  bool busy = false;
  int? imported;
  @override
  void initState() {
    super.initState();
    if (tables.isNotEmpty) mapping.detect(tables.first);
  }

  Widget select(
    String label,
    String? value,
    Map<String, String> options,
    ValueChanged<String> onChanged,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label-$value-${options.keys.join(',')}'),
      initialValue: options.containsKey(value) ? value : '',
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final option in options.entries)
          DropdownMenuItem(
            value: option.key,
            child: Text(option.value, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: busy ? null : (value) => setState(() => onChanged(value!)),
    ),
  );

  Future<void> pick() async {
    setState(() => busy = true);
    await perform(context, () async {
      final file = await FileDelivery().pickImport();
      if (file == null) return;
      final decoded = await Isolate.run(
        () => readImportTables(file.name, file.bytes),
      );
      if (!mounted) return;
      setState(() {
        tables = decoded;
        sheet = 0;
        mapping.detect(decoded.first);
        results = null;
        imported = null;
      });
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('导入交易明细')),
    body: DataView(
      builder: (data) {
        if (imported != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('已导入 $imported 条明细'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ],
            ),
          );
        }
        if (tables.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('逐条追加交易记录，已有数据会保留。'),
                const SizedBox(height: 12),
                const Text(
                  '支持 UTF-8 CSV 和 Excel .xlsx。首行为列名，每行一条明细；最多 10 MB、10000 条。可导入收入、支出、转账、借入、借出。',
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: busy ? null : pick,
                  icon: const Icon(Icons.upload_file),
                  label: Text(busy ? '读取中…' : '选择文件'),
                ),
              ],
            ),
          );
        }
        final table = tables[sheet];
        final plan = results;
        if (plan != null) {
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: plan.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '预览与选择',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '共 ${plan.length} 条 · 错误 ${plan.where((r) => r.error != null).length} 条 · 疑似重复 ${plan.where((r) => r.entry?.duplicate ?? false).length} 条',
                    ),
                    const Text('错误记录无法勾选；疑似重复默认不勾选，可核对后手动选择。'),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => setState(() => results = null),
                          child: const Text('返回修改关联'),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => setState(() {
                                  selected.clear();
                                  selected.addAll(
                                    plan
                                        .where(
                                          (r) =>
                                              r.entry != null &&
                                              !r.entry!.duplicate,
                                        )
                                        .map((r) => r.row),
                                  );
                                }),
                          child: const Text('选择有效且不重复的记录'),
                        ),
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => setState(selected.clear),
                          child: const Text('清空选择'),
                        ),
                      ],
                    ),
                    FilledButton(
                      onPressed: busy || selected.isEmpty
                          ? null
                          : () async {
                              setState(() => busy = true);
                              await perform(context, () async {
                                final entries = plan
                                    .where((r) => selected.contains(r.row))
                                    .map((r) => r.entry!)
                                    .toList();
                                final count = await commitImport(
                                  ref.read(databaseProvider),
                                  entries,
                                );
                                if (mounted) setState(() => imported = count);
                              });
                              if (mounted) setState(() => busy = false);
                            },
                      child: Text(busy ? '导入中…' : '确认导入 ${selected.length} 条'),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              }
              final result = plan[index - 1], entry = result.entry;
              return CheckboxListTile(
                value: selected.contains(result.row),
                onChanged: busy || entry == null
                    ? null
                    : (value) => setState(() {
                        if (value!) {
                          selected.add(result.row);
                        } else {
                          selected.remove(result.row);
                        }
                      }),
                title: Text(
                  entry == null
                      ? '第 ${result.row} 行：${result.error}'
                      : '第 ${result.row} 行 · ${entry.date} · ${entry.kind.label} · ${money(entry.amount, data.account(entry.accountId).currency)}',
                ),
                subtitle: entry == null
                    ? null
                    : Text(
                        '${data.account(entry.accountId).name} · ${data.category(entry.categoryId)}${entry.note.isEmpty ? '' : ' · ${entry.note}'}${entry.duplicate ? ' · 疑似重复' : ''}',
                      ),
              );
            },
          );
        }
        Set<String> values(ImportField field) => table.rows
            .map((r) => mapping.value(r, field))
            .where((v) => v.isNotEmpty)
            .toSet();
        final kindValues = values(ImportField.kind);
        final categoryValues = values(ImportField.category);
        final accountValues = {
          ...values(ImportField.account),
          ...values(ImportField.target),
        };
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('1. 关联列名', style: TextStyle(fontSize: 20)),
            Text('${table.name} · ${table.rows.length} 条明细。识别结果仅为建议，请核对后继续。'),
            const SizedBox(height: 12),
            select(
              '工作表',
              '$sheet',
              {for (var i = 0; i < tables.length; i++) '$i': tables[i].name},
              (value) {
                sheet = int.parse(value);
                mapping.detect(tables[sheet]);
              },
            ),
            for (final field in ImportField.values)
              select(
                '${field.label}${[ImportField.date, ImportField.amount].contains(field) ? ' · 必选列' : ''}',
                mapping.columns[field]?.toString(),
                {
                  '': '不关联此列',
                  for (var i = 0; i < table.headers.length; i++)
                    '$i': '${i + 1}. ${table.headers[i]}',
                },
                (value) {
                  if (value.isEmpty) {
                    mapping.columns.remove(field);
                  } else {
                    mapping.columns[field] = int.parse(value);
                  }
                },
              ),
            const Text('2. 默认值与内容关联', style: TextStyle(fontSize: 20)),
            const Text('账户和分类按名称匹配；名称不同时可手动指定。空白单元格使用默认值。负金额按绝对值记录，收支以交易类型为准。'),
            const SizedBox(height: 12),
            select('默认交易类型', mapping.defaultKind.name, {
              for (final kind in EntryKind.values.where((k) => !k.isSettlement))
                kind.name: kind.label,
            }, (value) => mapping.defaultKind = EntryKind.values.byName(value)),
            select(
              '默认账户',
              mapping.defaultAccount,
              {
                '': '请选择',
                for (final account in data.accounts)
                  account.id: '${account.name} · ${account.currency}',
              },
              (value) => mapping.defaultAccount = value.isEmpty ? null : value,
            ),
            for (final kind in ['expense', 'income'])
              select(
                '默认${kind == 'expense' ? '支出' : '收入'}分类',
                kind == 'expense'
                    ? mapping.expenseCategory
                    : mapping.incomeCategory,
                {
                  '': '请选择',
                  for (final category in data.categories.where(
                    (c) => c.kind == kind,
                  ))
                    category.id: category.name,
                },
                (value) {
                  if (kind == 'expense') {
                    mapping.expenseCategory = value.isEmpty ? null : value;
                  } else {
                    mapping.incomeCategory = value.isEmpty ? null : value;
                  }
                },
              ),
            for (final value in kindValues.take(100))
              select(
                '类型内容：$value',
                mapping.kinds[value] ?? detectedKind(value)?.name,
                {
                  '': '请关联',
                  for (final kind in EntryKind.values.where(
                    (k) => !k.isSettlement,
                  ))
                    kind.name: kind.label,
                },
                (target) {
                  mapping.kinds[value] = target;
                },
              ),
            for (final value in accountValues.take(100))
              select(
                '账户内容：$value',
                mapping.accounts[value] ??
                    data.accounts
                        .where((a) => a.name == value)
                        .singleOrNull
                        ?.id,
                {
                  '': '请关联',
                  for (final account in data.accounts)
                    account.id: '${account.name} · ${account.currency}',
                },
                (target) {
                  if (target.isEmpty) {
                    mapping.accounts.remove(value);
                  } else {
                    mapping.accounts[value] = target;
                  }
                },
              ),
            for (final kind in ['expense', 'income'])
              for (final value in categoryValues.take(100))
                select(
                  '${kind == 'expense' ? '支出' : '收入'}分类内容：$value',
                  mapping.categories['$kind:$value'] ??
                      data.categories
                          .where((c) => c.name == value && c.kind == kind)
                          .firstOrNull
                          ?.id,
                  {
                    '': '按名称匹配 / 暂不关联',
                    for (final category in data.categories.where(
                      (c) => c.kind == kind,
                    ))
                      category.id: category.name,
                  },
                  (target) {
                    if (target.isEmpty) {
                      mapping.categories.remove('$kind:$value');
                    } else {
                      mapping.categories['$kind:$value'] = target;
                    }
                  },
                ),
            if ([
              kindValues.length,
              accountValues.length,
              categoryValues.length,
            ].any((n) => n > 100))
              const Text('每组最多显示 100 个内容映射；其余按名称匹配，无法匹配的行将在预览中报错。'),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      await perform(context, () async {
                        final preview = previewImport(
                          table,
                          mapping,
                          data.accounts,
                          data.categories,
                          data.entries,
                        );
                        setState(() {
                          results = preview;
                          selected.clear();
                          selected.addAll(
                            preview
                                .where(
                                  (r) => r.entry != null && !r.entry!.duplicate,
                                )
                                .map((r) => r.row),
                          );
                        });
                      });
                    },
              child: const Text('预览明细'),
            ),
            TextButton(
              onPressed: busy ? null : pick,
              child: const Text('重新选择文件'),
            ),
          ],
        );
      },
    ),
  );
}
