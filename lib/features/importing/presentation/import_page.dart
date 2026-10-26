import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart';
import '../../ledger/domain/entry_kind.dart';
import 'import_balances_page.dart';
import '../../ledger/presentation/accounts_page.dart';
import '../../statistics/data/csv_export.dart';
import '../domain/import_table.dart';
import '../domain/import_plan.dart';
import '../domain/missing_accounts.dart';
import '../domain/import_template.dart';

class ImportPage extends ConsumerStatefulWidget {
  const ImportPage({super.key, this.initialTables});
  final List<ImportTable>? initialTables;
  @override
  ConsumerState<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends ConsumerState<ImportPage> {
  late List<ImportTable> tables = widget.initialTables ?? [];
  int sheet = 0;
  final mapping = IncomeExpenseImportMapping();
  final importedAccountIds = <String>{};
  List<ImportResult>? results;
  final selected = <int>{};
  bool busy = false;
  int? imported;
  String? fileError;
  int setupStep = 0;
  String previewFilter = 'all', previewSearch = '';
  bool showExtraColumns = false;
  final Map<String, Account> createdAccounts = {};

  AppSnapshot mergeAccounts(AppSnapshot data) {
    // Once the database stream has observed a new account, it is authoritative.
    createdAccounts.removeWhere(
      (id, _) => data.accounts.any((a) => a.id == id),
    );
    return AppSnapshot(
      {
        for (final a in data.activeAccounts) a.id: a,
        ...createdAccounts,
      }.values.toList(),
      data.categories,
      data.entries,
      data.budgets,
      data.items,
      data.links,
      data.preferences,
      data.adjustments,
      data.goals,
      data.contributions,
    );
  }

  void nextStep() {
    if (!mapping.columns.containsKey(ImportField.date) ||
        !mapping.columns.containsKey(ImportField.amount) ||
        mapping.columns.values.toSet().length != mapping.columns.length) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请关联日期和金额，每列只能关联一个字段')));
      return;
    }
    setState(() => setupStep = 1);
  }

  Future<void> commitSelection() async {
    if (busy || selected.isEmpty || results == null) return;
    setState(() => busy = true);
    await perform(context, () async {
      final chosen = results!
          .where((r) => selected.contains(r.row))
          .map((r) => r.entry!)
          .toList();
      final count = await commitIncomeExpenseImport(
        ref.read(databaseProvider),
        chosen,
      );
      if (mounted) {
        setState(() {
          imported = count;
          importedAccountIds.addAll(chosen.map((e) => e.accountId));
        });
      }
    });
    if (mounted) setState(() => busy = false);
  }

  Widget footer(AppSnapshot data) => KeyboardActionBar(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (results != null)
            Text(
              '已选择 ${selected.length} / ${results!.length} 条',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy || (results != null && selected.isEmpty)
                  ? null
                  : results != null
                  ? commitSelection
                  : setupStep == 0
                  ? nextStep
                  : () => preview(data),
              child: Text(
                busy
                    ? '处理中…'
                    : results != null
                    ? '确认导入 ${selected.length} 条'
                    : setupStep == 0
                    ? '下一步：账户与分类'
                    : '预览明细',
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget stepHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
    child: Row(
      children: [
        for (var i = 0; i < 3; i++)
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    color: i <= (results == null ? setupStep : 2)
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  ['列名关联', '账户与分类', '预览确认'][i],
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Future<bool> createAccount(MissingImportAccount source) async {
    if (source.currencies.length > 1) {
      throw const FormatException('同一来源账户包含多个币种，请先拆分账户列或按币种分批导入');
    }
    final savedId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => AccountForm(
          initialName: source.name,
          importContext:
              '来源账户：${source.name} · ${source.rows.length} 条明细\n用途：${source.roles.join('、')}${source.currencies.isEmpty ? '' : '\n文件币种 ${source.currencies.single}'}${source.firstDate == null ? '' : '\n最早交易：${source.firstDate}'}',
        ),
      ),
    );
    if (savedId == null || !mounted) return false;
    final db = ref.read(databaseProvider);
    final account = await (db.select(
      db.accounts,
    )..where((a) => a.id.equals(savedId))).getSingle();
    if (!mounted) return false;
    setState(() {
      createdAccounts[account.id] = account;
      mapping.accounts[source.name] = account.id;
    });
    return true;
  }

  Future<void> preview(AppSnapshot data) async {
    setState(() => busy = true);
    await perform(context, () async {
      if (!mapping.columns.containsKey(ImportField.date) ||
          !mapping.columns.containsKey(ImportField.amount)) {
        throw const FormatException('请先关联日期和金额列');
      }
      if (mapping.columns.values.toSet().length != mapping.columns.length) {
        throw const FormatException('每一列只能关联一个字段');
      }
      final missing = missingImportAccounts(
        tables[sheet],
        mapping,
        data.activeAccounts,
      );
      final accountDb = ref.read(databaseProvider);
      for (final source in missing) {
        if (!mounted) return;
        // A renamed account can also satisfy another queued source name.
        final currentAccounts = await accountDb
            .select(accountDb.accounts)
            .get();
        final stillMissing = missingImportAccounts(
          tables[sheet],
          mapping,
          currentAccounts,
        ).any((candidate) => candidate.name == source.name);
        if (!stillMissing) continue;
        if (!mounted || !await createAccount(source)) return;
      }
      if (!mounted) return;
      final db = ref.read(databaseProvider);
      // Refresh data after account forms; imported records may have changed in another route.
      final categories = await db.select(db.categories).get();
      final entries = await db.select(db.entries).get();
      if (!mounted) return;
      final plan = previewImport(
        tables[sheet],
        mapping,
        await db.select(db.accounts).get(),
        categories,
        entries,
      );
      setState(() {
        results = plan;
        previewFilter = 'all';
        previewSearch = '';
        selected.clear();
        selected.addAll(plan.where((r) => r.entry != null).map((r) => r.row));
      });
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> createMissingCategories(EntryKind kind) async {
    setState(() => busy = true);
    await perform(context, () async {
      final db = ref.read(databaseProvider);
      await db.transaction(() async {
        final categories = await db.select(db.categories).get();
        for (final name in mapping.categoryValuesFor(tables[sheet], kind)) {
          if (mapping.categories.containsKey('${kind.name}:$name') ||
              categories.any((c) => c.kind == kind.name && c.name == name)) {
            continue;
          }
          await ref.read(ledgerProvider).saveCategory(name, kind.name);
        }
      });
    }, success: '已按原名称创建缺失分类');
    if (mounted) setState(() => busy = false);
  }

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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          key: ValueKey('$label-$value-${options.keys.join(',')}'),
          initialValue: options.containsKey(value) ? value : '',
          isExpanded: true,
          decoration: const InputDecoration(),
          items: [
            for (final option in options.entries)
              DropdownMenuItem(
                value: option.key,
                child: Text(option.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: busy ? null : (value) => setState(() => onChanged(value!)),
        ),
      ],
    ),
  );

  Future<void> pick() async {
    setState(() {
      busy = true;
      fileError = null;
    });
    try {
      final file = await ref.read(fileDeliveryProvider).pickImport();
      if (file == null) return;
      final decoded = await readImportTablesInBackground(file.name, file.bytes);
      if (!mounted) return;
      setState(() {
        tables = decoded;
        sheet = 0;
        mapping.detect(decoded.first);
        results = null;
        imported = null;
        setupStep = 0;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => fileError = error is FormatException
              ? error.message.toString()
              : '文件解析失败（${error.runtimeType}），请用 Excel/WPS 重新保存后重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget templateButton() => TextButton.icon(
    onPressed: busy
        ? null
        : () => perform(context, () async {
            await ref
                .read(fileDeliveryProvider)
                .save(
                  'SoAccount-收支导入模板.csv',
                  Uint8List.fromList(
                    utf8.encode(csvDocument(importTemplateRows())),
                  ),
                );
          }),
    icon: const Icon(Icons.download_outlined),
    label: const Text('保存收支 CSV 模板'),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && (imported != null || (results == null && setupStep == 0)),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !busy) {
        setState(() {
          if (results != null) {
            results = null;
          } else {
            setupStep = 0;
          }
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('导入交易明细'),
        leading: imported == null && (results != null || setupStep > 0)
            ? IconButton(
                tooltip: '上一步',
                onPressed: busy
                    ? null
                    : () => setState(() {
                        if (results != null) {
                          results = null;
                        } else {
                          setupStep = 0;
                        }
                      }),
                icon: const Icon(Icons.arrow_back),
              )
            : null,
      ),
      bottomNavigationBar:
          tables.isNotEmpty &&
              imported == null &&
              ref.watch(snapshotProvider).value != null
          ? footer(mergeAccounts(ref.watch(snapshotProvider).value!))
          : null,
      body: Column(
        children: [
          if (fileError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  '$fileError${tables.isEmpty ? '' : '\n新文件未载入，仍保留原工作表及映射。'}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
          Expanded(
            child: DataView(
              builder: (snapshot) {
                final data = mergeAccounts(snapshot);
                if (imported != null) {
                  return ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        '已导入 $imported 条明细',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      const Icon(Icons.check_circle_outline, size: 48),
                      const SizedBox(height: 20),
                      const Text(
                        '导入后如何调整账户余额？',
                        style: TextStyle(fontSize: 20),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '导入的收支已经计入余额。可填写账户的实际余额直接校正；调整单独保留记录，不新增收入、支出或转账流水。',
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => openForm(
                          context,
                          ImportBalancesPage(accountIds: importedAccountIds),
                        ),
                        icon: const Icon(Icons.balance_outlined),
                        label: const Text('核对并调整余额'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('保持当前余额并完成'),
                      ),
                    ],
                  );
                }
                if (tables.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: ListView(
                      children: [
                        const Text('逐条追加交易记录，已有数据会保留。'),
                        const SizedBox(height: 12),
                        const Text(
                          '支持 UTF-8 CSV、Excel .xls / .xlsx。首行为列名，每行一条明细；最多 10 MB、10000 条。目前仅导入收入和支出。零金额、空账户和其他交易类型自动忽略。',
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: busy ? null : pick,
                          icon: const Icon(Icons.upload_file),
                          label: Text(busy ? '读取中…' : '选择文件'),
                        ),
                        templateButton(),
                      ],
                    ),
                  );
                }
                final table = tables[sheet];
                final plan = results;
                if (plan != null) {
                  final visible = plan
                      .where(
                        (r) =>
                            (switch (previewFilter) {
                              'ignored' => r.ignored,
                              'errors' => r.error != null,
                              'selected' => selected.contains(r.row),
                              _ => !r.ignored,
                            }) &&
                            (previewSearch.isEmpty ||
                                '${r.row} ${r.error ?? r.ignoredReason ?? ''} ${r.entry?.date ?? ''} ${r.entry?.note ?? ''}'
                                    .toLowerCase()
                                    .contains(previewSearch.toLowerCase())),
                      )
                      .toList();
                  final totals = <String, int>{};
                  for (final row in plan.where(
                    (r) => selected.contains(r.row),
                  )) {
                    final entry = row.entry!;
                    for (final record in entry.recordsToImport) {
                      final key = '${record.currency} · ${record.kind.label}';
                      totals[key] = (totals[key] ?? 0) + record.amount;
                    }
                  }
                  return Column(
                    children: [
                      stepHeader(),
                      Expanded(
                        child: ListView.builder(
                          key: const ValueKey('review'),
                          padding: const EdgeInsets.all(16),
                          itemCount: visible.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '预览与选择',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge,
                                  ),
                                  Text(
                                    '共 ${plan.length} 条 · 忽略 ${plan.where((r) => r.ignored).length} 条 · 错误 ${plan.where((r) => r.error != null).length} 条',
                                  ),
                                  const Text('有效记录默认全部勾选；相同记录逐条保留，再次导入会继续追加。'),
                                  const Text('零金额、空账户和非收支记录已自动忽略，不会创建账户或影响余额。'),
                                  const SizedBox(height: 12),
                                  ClearableSearch(
                                    value: previewSearch,
                                    hint: '搜索行号、日期或备注',
                                    onChanged: (v) =>
                                        setState(() => previewSearch = v),
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      for (final entry in {
                                        'all': '全部',
                                        'selected': '已选',
                                        'errors': '错误',
                                        'ignored': '已忽略',
                                      }.entries)
                                        ChoiceChip(
                                          label: Text(entry.value),
                                          selected: previewFilter == entry.key,
                                          onSelected: (_) => setState(
                                            () => previewFilter = entry.key,
                                          ),
                                        ),
                                    ],
                                  ),
                                  ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    title: const Text('选中金额汇总 · 币种分开'),
                                    children: [
                                      for (final entry in totals.entries)
                                        ListTile(
                                          dense: true,
                                          title: Text(entry.key),
                                          trailing: Text(
                                            decimalMoney(
                                              entry.value,
                                              entry.key.split(' · ').first,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  Wrap(
                                    spacing: 8,
                                    children: [
                                      TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => setState(
                                                () => results = null,
                                              ),
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
                                                        (r) => r.entry != null,
                                                      )
                                                      .map((r) => r.row),
                                                );
                                              }),
                                        child: const Text('选择全部有效记录'),
                                      ),
                                      TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => setState(selected.clear),
                                        child: const Text('清空选择'),
                                      ),
                                    ],
                                  ),
                                  if (visible.isEmpty)
                                    plan.every((r) => r.ignored)
                                        ? const EmptyState(
                                            '没有可导入的收支',
                                            '零金额、空账户和非收支记录已全部忽略。',
                                          )
                                        : const EmptyState(
                                            '没有匹配的明细',
                                            '可以清空搜索或切换筛选。',
                                          ),
                                  const SizedBox(height: 16),
                                ],
                              );
                            }
                            final result = visible[index - 1],
                                entry = result.entry;
                            String accountName(String id) =>
                                data.activeAccounts
                                    .where((a) => a.id == id)
                                    .firstOrNull
                                    ?.name ??
                                '账户已删除';
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
                                    ? '第 ${result.row} 行：${result.error ?? result.ignoredReason}'
                                    : '第 ${result.row} 行 · ${entry.date} · ${entry.kind.label} · ${money(entry.amount, entry.currency)}',
                              ),
                              subtitle: entry == null
                                  ? null
                                  : Text(
                                      '${accountName(entry.accountId)} · ${data.category(entry.categoryId)}${entry.note.isEmpty ? '' : ' · ${entry.note}'}',
                                    ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                }
                Set<String> values(ImportField field) => table.rows
                    .where((r) => mapping.ignoredReason(r) == null)
                    .map((r) => mapping.value(r, field))
                    .where((v) => v.isNotEmpty)
                    .toSet();
                final kindValues = values(ImportField.kind);
                final categoryValues = values(ImportField.category);
                final accountSources = importAccountSources(table, mapping);
                final accountValues = accountSources.map((a) => a.name).toSet();
                final activeKinds = table.rows
                    .where((r) => mapping.ignoredReason(r) == null)
                    .map(mapping.kindFor)
                    .whereType<EntryKind>()
                    .map((k) => k.name)
                    .toSet();
                return Column(
                  children: [
                    stepHeader(),
                    Expanded(
                      child: ListView(
                        key: ValueKey('setup-$setupStep'),
                        padding: const EdgeInsets.all(20),
                        children: [
                          if (setupStep == 0) ...[
                            const Text('关联列名', style: TextStyle(fontSize: 20)),
                            Text(
                              '${table.name} · ${table.rows.length} 条明细。识别结果仅为建议，请核对后继续。',
                            ),
                            const Text('请关联收入和支出使用的“收支账户”列。零金额、空账户和非收支记录直接忽略。'),
                            const SizedBox(height: 12),
                            select(
                              '工作表',
                              '$sheet',
                              {
                                for (var i = 0; i < tables.length; i++)
                                  '$i': tables[i].name,
                              },
                              (value) {
                                sheet = int.parse(value);
                                mapping.detect(tables[sheet]);
                              },
                            ),
                            for (final field
                                in IncomeExpenseImportMapping.fields.where(
                                  (f) =>
                                      showExtraColumns ||
                                      mapping.columns.containsKey(f) ||
                                      [
                                        ImportField.date,
                                        ImportField.amount,
                                      ].contains(f),
                                ))
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
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => setState(
                                      () =>
                                          showExtraColumns = !showExtraColumns,
                                    ),
                              child: Text(
                                showExtraColumns ? '收起未关联字段' : '关联其他字段',
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text('文件内容示例'),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: [
                                  for (final header in table.headers)
                                    DataColumn(label: Text(header)),
                                ],
                                rows: [
                                  for (final row in table.rows.take(3))
                                    DataRow(
                                      cells: [
                                        for (
                                          var i = 0;
                                          i < table.headers.length;
                                          i++
                                        )
                                          DataCell(
                                            Text(i < row.length ? row[i] : ''),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ],
                          if (setupStep == 1) ...[
                            const Text('账户与分类', style: TextStyle(fontSize: 20)),
                            if (missingImportAccounts(
                              table,
                              mapping,
                              data.activeAccounts,
                            ).isNotEmpty)
                              Card(
                                borderOnForeground: false,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    '有 ${missingImportAccounts(table, mapping, data.activeAccounts).length} 个来源账户待关联。可先关联已有账户，点击预览时将逐个创建缺失账户。',
                                  ),
                                ),
                              ),
                            const Text(
                              '账户和分类按名称匹配，也可手动关联。空账户、零金额自动忽略。负金额按绝对值记录，方向以收入或支出为准。',
                            ),
                            const SizedBox(height: 12),
                            if (table.rows
                                .where((r) => mapping.ignoredReason(r) == null)
                                .any(
                                  (row) => mapping
                                      .value(row, ImportField.kind)
                                      .isEmpty,
                                ))
                              select(
                                '默认交易类型',
                                mapping.defaultKind.name,
                                {
                                  for (final kind in EntryKind.values.where(
                                    (k) => k.needsCategory,
                                  ))
                                    kind.name: kind.label,
                                },
                                (value) => mapping.defaultKind = EntryKind
                                    .values
                                    .byName(value),
                              ),
                            for (final kind in [
                              'expense',
                              'income',
                            ].where(activeKinds.contains))
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
                                    mapping.expenseCategory = value.isEmpty
                                        ? null
                                        : value;
                                  } else {
                                    mapping.incomeCategory = value.isEmpty
                                        ? null
                                        : value;
                                  }
                                },
                              ),
                            for (final value in kindValues.take(100))
                              select(
                                '类型内容：$value',
                                mapping.kinds[value] ??
                                    detectedKind(value)?.name,
                                {'': '请关联', 'expense': '支出', 'income': '收入'},
                                (target) => mapping.kinds[value] = target,
                              ),
                            for (final value in accountValues.take(100))
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${accountSources.firstWhere((s) => s.name == value).roles.join('、')} · ${accountSources.firstWhere((s) => s.name == value).rows.length} 条明细',
                                  ),
                                  select(
                                    '账户内容：$value',
                                    mapping.accounts[value] ??
                                        data.activeAccounts
                                            .where((a) => a.name == value)
                                            .singleOrNull
                                            ?.id,
                                    {
                                      '': '请关联',
                                      for (final account in data.activeAccounts)
                                        account.id:
                                            '${account.name} · ${account.currency}',
                                    },
                                    (target) {
                                      if (target.isEmpty) {
                                        mapping.accounts.remove(value);
                                      } else {
                                        mapping.accounts[value] = target;
                                      }
                                    },
                                  ),
                                  if (!data.activeAccounts.any(
                                        (a) => a.name == value,
                                      ) &&
                                      !mapping.accounts.containsKey(value))
                                    TextButton.icon(
                                      onPressed: busy
                                          ? null
                                          : () => perform(context, () async {
                                              final source =
                                                  missingImportAccounts(
                                                        table,
                                                        mapping,
                                                        data.activeAccounts,
                                                      )
                                                      .where(
                                                        (m) => m.name == value,
                                                      )
                                                      .firstOrNull;
                                              if (source != null) {
                                                await createAccount(source);
                                              }
                                            }),
                                      icon: const Icon(Icons.add_card),
                                      label: Text('创建“$value”'),
                                    ),
                                ],
                              ),
                            for (final kind in [
                              'expense',
                              'income',
                            ].where(activeKinds.contains)) ...[
                              Text(
                                kind == 'expense' ? '支出分类关联' : '收入分类关联',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => createMissingCategories(
                                          EntryKind.values.byName(kind),
                                        ),
                                  icon: const Icon(Icons.add),
                                  label: Text(
                                    '按原名称创建缺失的${kind == 'expense' ? '支出' : '收入'}分类',
                                  ),
                                ),
                              ),
                              for (final value
                                  in mapping
                                      .categoryValuesFor(
                                        table,
                                        EntryKind.values.byName(kind),
                                      )
                                      .take(100))
                                select(
                                  '${kind == 'expense' ? '支出' : '收入'}分类内容：$value',
                                  mapping.categories['$kind:$value'] ??
                                      data.categories
                                          .where(
                                            (c) =>
                                                c.name == value &&
                                                c.kind == kind,
                                          )
                                          .firstOrNull
                                          ?.id,
                                  {
                                    '': '按名称匹配 / 暂不关联',
                                    for (final category
                                        in data.categories.where(
                                          (c) => c.kind == kind,
                                        ))
                                      category.id: category.name,
                                  },
                                  (target) {
                                    if (target.isEmpty) {
                                      mapping.categories.remove('$kind:$value');
                                    } else {
                                      mapping.categories['$kind:$value'] =
                                          target;
                                    }
                                  },
                                ),
                            ],
                            if ([
                              kindValues.length,
                              accountValues.length,
                              categoryValues.length,
                            ].any((n) => n > 100))
                              const Text(
                                '每组最多显示 100 个内容映射；其余按名称匹配，无法匹配的行将在预览中报错。',
                              ),
                          ],
                          TextButton(
                            onPressed: busy ? null : pick,
                            child: const Text('重新选择文件'),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
