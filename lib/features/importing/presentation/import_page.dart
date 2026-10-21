import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart';
import '../../ledger/domain/entry_kind.dart';
import '../../ledger/domain/debt_relationship.dart';
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
  final mapping = ImportMapping();
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
        for (final a in data.accounts) a.id: a,
        ...createdAccounts,
      }.values.toList(),
      data.categories,
      data.entries,
      data.budgets,
      data.items,
      data.links,
      data.preferences,
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
    if (tables[sheet].rows.any(
          (row) => mapping.kindFor(row) == EntryKind.transfer,
        ) &&
        !mapping.columns.containsKey(ImportField.target)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('转账需要目标账户列，请先关联“目标账户”')));
      return;
    }
    setState(() => setupStep = 1);
  }

  Future<void> commitSelection() async {
    if (busy || selected.isEmpty || results == null) return;
    setState(() => busy = true);
    await perform(context, () async {
      final count = await commitImport(
        ref.read(databaseProvider),
        results!
            .where((r) => selected.contains(r.row))
            .map((r) => r.entry!)
            .toList(),
      );
      if (mounted) setState(() => imported = count);
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

  Future<bool> createAccount(MissingImportAccount? source) async {
    if (source != null && source.currencies.length > 1) {
      throw const FormatException('同一来源账户包含多个币种，请先拆分账户列或按币种分批导入');
    }
    final savedId = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => AccountForm(
          initialName: source?.name,
          importContext: source == null
              ? '创建本批明细使用的默认账户。'
              : '来源账户：${source.name} · ${source.rows.length} 条明细\n用途：${source.roles.join('、')}${source.currencies.isEmpty ? '' : '\n文件币种 ${source.currencies.single}'}${source.firstDate == null ? '' : '\n最早交易：${source.firstDate}'}',
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
      if (source == null) {
        mapping.defaultAccount = account.id;
      } else {
        mapping.accounts[source.name] = account.id;
      }
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
      if (mapping.hasTransferAccounts &&
          tables[sheet].rows.any(
            (row) =>
                mapping.value(row, ImportField.kind) == '还款' &&
                mapping.kindFor(row) == null,
          )) {
        throw const FormatException(
          '请先确认“还款”的含义：信贷账户还款选择转账；人员还款选择偿还借入或收回借出，并关联原始借贷',
        );
      }
      final missing = missingImportAccounts(
        tables[sheet],
        mapping,
        data.accounts,
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
      final accounts = await db.select(db.accounts).get();
      // Refresh data after account forms; imported records may have changed in another route.
      final categories = await db.select(db.categories).get();
      final entries = await db.select(db.entries).get();
      if (!mounted) return;
      final plan = previewImport(
        tables[sheet],
        mapping,
        accounts,
        categories,
        entries,
      );
      setState(() {
        results = plan;
        previewFilter = 'all';
        previewSearch = '';
        selected.clear();
        selected.addAll(
          plan
              .where((r) => r.entry != null && !r.entry!.suspectedDuplicate)
              .map((r) => r.row),
        );
      });
    });
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

  Widget templateButton({bool transfer = false}) => TextButton.icon(
    onPressed: busy
        ? null
        : () => perform(context, () async {
            final template = csvDocument(
              transfer ? transferTemplateRows() : importTemplateRows(),
            );
            await ref
                .read(fileDeliveryProvider)
                .save(
                  'SoAccount-${transfer ? '转账' : '收支'}导入模板.csv',
                  Uint8List.fromList(utf8.encode(template)),
                );
          }),
    icon: const Icon(Icons.download_outlined),
    label: Text(transfer ? '保存转账 CSV 模板' : '保存收支 CSV 模板'),
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
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('已导入 $imported 条明细'),
                        const SizedBox(height: 12),
                        const Icon(Icons.check_circle_outline, size: 48),
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
                    child: ListView(
                      children: [
                        const Text('逐条追加交易记录，已有数据会保留。'),
                        const SizedBox(height: 12),
                        const Text(
                          '支持 UTF-8 CSV、Excel .xls / .xlsx。首行为列名，每行一条明细；最多 10 MB、10000 条。可导入收入、支出、转账、借入、借出。',
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: busy ? null : pick,
                          icon: const Icon(Icons.upload_file),
                          label: Text(busy ? '读取中…' : '选择文件'),
                        ),
                        templateButton(),
                        templateButton(transfer: true),
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
                              'errors' => r.error != null,
                              'duplicates' =>
                                r.entry?.suspectedDuplicate ?? false,
                              'selected' => selected.contains(r.row),
                              _ => true,
                            }) &&
                            (previewSearch.isEmpty ||
                                '${r.row} ${r.error ?? ''} ${r.entry?.date ?? ''} ${r.entry?.note ?? ''}'
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
                                    '共 ${plan.length} 条 · 错误 ${plan.where((r) => r.error != null).length} 条 · 疑似重复 ${plan.where((r) => r.entry?.suspectedDuplicate ?? false).length} 条',
                                  ),
                                  const Text('错误记录无法勾选；疑似重复默认不勾选，可核对后手动选择。'),
                                  if (plan.any((r) => r.entry?.fee != null))
                                    const Text(
                                      '一行转账连同手续费一起选择；手续费另记支出，从转出账户扣除。部分已导入的记录仅补齐缺失部分。',
                                    ),
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
                                        'duplicates': '重复',
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
                                                        (r) =>
                                                            r.entry != null &&
                                                            !r
                                                                .entry!
                                                                .suspectedDuplicate,
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
                                  if (visible.isEmpty)
                                    const EmptyState('没有匹配的明细', '可以清空搜索或切换筛选。'),
                                  const SizedBox(height: 16),
                                ],
                              );
                            }
                            final result = visible[index - 1],
                                entry = result.entry;
                            String accountName(String id) =>
                                data.accounts
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
                                    ? '第 ${result.row} 行：${result.error}'
                                    : '第 ${result.row} 行 · ${entry.date} · ${entry.kind.label} · ${money(entry.amount, entry.currency)}',
                              ),
                              subtitle: entry == null
                                  ? null
                                  : Text(
                                      '${accountName(entry.accountId)}${entry.targetId == null ? '' : ' → ${accountName(entry.targetId!)}'}${entry.counterparty.isEmpty ? '' : ' · 往来人 ${entry.counterparty}'}${entry.debtId == null ? '' : ' · 原借贷 ${data.entries.where((e) => e.id == entry.debtId).firstOrNull?.date ?? ''}'}${entry.kind.needsCategory ? ' · ${data.category(entry.categoryId)}' : ''}${entry.fee == null ? '' : ' · 手续费 ${money(entry.fee!.amount, entry.currency)}（${data.category(entry.fee!.categoryId)}）'}${entry.note.isEmpty ? '' : ' · ${entry.note}'}${entry.duplicate
                                          ? ' · 疑似重复'
                                          : entry.principalDuplicate
                                          ? ' · 转账已存在，仅补手续费'
                                          : entry.fee?.duplicate == true
                                          ? ' · 手续费已存在，仅补转账'
                                          : ''}',
                                    ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                }
                Set<String> values(ImportField field) => table.rows
                    .map((r) => mapping.value(r, field))
                    .where((v) => v.isNotEmpty)
                    .toSet();
                final kindValues = values(ImportField.kind);
                final categoryValues = values(ImportField.category);
                final accountSources = importAccountSources(table, mapping);
                final accountValues = accountSources.map((a) => a.name).toSet();
                final activeKinds = table.rows
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
                            const Text(
                              '收入/支出使用“收支账户”；转账使用“源账户 → 目标账户”。原来的“账户”列也可作为转账源账户。',
                            ),
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
                            if (mapping.hasTransferAccounts)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: Text(
                                  '已识别转账格式：转出账户 → 转入账户，一行一笔。手续费从转出账户另扣，单独计入支出。',
                                ),
                              ),
                            for (final field in ImportField.values.where(
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
                              data.accounts,
                            ).isNotEmpty)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    '有 ${missingImportAccounts(table, mapping, data.accounts).length} 个来源账户待关联。可先关联已有账户，点击预览时将逐个创建缺失账户。',
                                  ),
                                ),
                              ),
                            const Text(
                              '账户和分类按名称匹配，可手动关联。转账必须提供目标账户且与源账户不同、币种相同；源账户为空时使用明确选择的默认账户。负金额按绝对值记录，方向以交易类型为准。',
                            ),
                            const SizedBox(height: 12),
                            if (table.rows.any(
                              (row) =>
                                  mapping.value(row, ImportField.kind).isEmpty,
                            ))
                              select(
                                '默认交易类型',
                                mapping.defaultKind.name,
                                {
                                  for (final kind in EntryKind.values.where(
                                    (k) => !k.isSettlement,
                                  ))
                                    kind.name: kind.label,
                                },
                                (value) => mapping.defaultKind = EntryKind
                                    .values
                                    .byName(value),
                              ),
                            if (table.rows.any(
                              (row) => mapping
                                  .sourceAccountValue(row, mapping.kindFor(row))
                                  .isEmpty,
                            )) ...[
                              select(
                                '默认账户',
                                mapping.defaultAccount,
                                {
                                  '': '请选择',
                                  for (final account in data.accounts)
                                    account.id:
                                        '${account.name} · ${account.currency}',
                                },
                                (value) => mapping.defaultAccount =
                                    value.isEmpty ? null : value,
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: busy
                                      ? null
                                      : () => perform(context, () async {
                                          await createAccount(null);
                                        }),
                                  icon: const Icon(Icons.add),
                                  label: const Text('创建默认账户'),
                                ),
                              ),
                            ],
                            if (mapping.hasFees(table)) ...[
                              const Text('手续费：金额为转入金额，手续费额外从转出账户扣除；请选择支出分类。'),
                              select(
                                '手续费支出分类',
                                mapping.resolvedFeeCategory(data.categories),
                                {
                                  '': '请选择',
                                  for (final category in data.categories.where(
                                    (c) => c.kind == 'expense',
                                  ))
                                    category.id: category.name,
                                },
                                (value) => mapping.feeCategory = value.isEmpty
                                    ? null
                                    : value,
                              ),
                            ],
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
                              if (value == '还款' &&
                                  mapping.hasTransferAccounts) ...[
                                const Text(
                                  '“还款”含义确认：花呗、信用卡等还款选转账；人员还款选偿还借入或收回借出，并逐笔选择原始借贷。人员不创建为资金账户。',
                                ),
                                select('类型内容：还款', mapping.kinds[value], {
                                  '': '请确认还款含义',
                                  'transfer': '信贷账户还款（转账）',
                                  'repay': '向他人还款（偿还借入）',
                                  'collect': '他人向我还款（收回借出）',
                                }, (target) => mapping.kinds[value] = target),
                                ExpansionTile(
                                  title: const Text('逐行区分还款类型（混合情况）'),
                                  subtitle: const Text(
                                    '上方选择用于整组；个别记录可在这里单独修改。',
                                  ),
                                  children: [
                                    for (final (index, row)
                                        in table.rows.indexed
                                            .where(
                                              (r) =>
                                                  mapping.value(
                                                    r.$2,
                                                    ImportField.kind,
                                                  ) ==
                                                  '还款',
                                            )
                                            .take(100))
                                      select(
                                        '第 ${index + 2} 行还款类型 · ${mapping.value(row, ImportField.date)} · ${mapping.value(row, ImportField.source)} → ${mapping.value(row, ImportField.target)} · ${mapping.value(row, ImportField.amount)}',
                                        mapping.rowKinds[row]?.name ??
                                            mapping.kindFor(row)?.name,
                                        {
                                          '': '跟随整组选择',
                                          'transfer': '信贷账户还款（转账）',
                                          'repay': '向他人还款（偿还借入）',
                                          'collect': '他人向我还款（收回借出）',
                                        },
                                        (value) {
                                          if (value.isEmpty) {
                                            mapping.rowKinds.remove(row);
                                          } else {
                                            mapping.rowKinds[row] = EntryKind
                                                .values
                                                .byName(value);
                                          }
                                        },
                                      ),
                                    if (table.rows
                                            .where(
                                              (r) =>
                                                  mapping.value(
                                                    r,
                                                    ImportField.kind,
                                                  ) ==
                                                  '还款',
                                            )
                                            .length >
                                        100)
                                      const Text(
                                        '逐行区分最多显示 100 行；其余请分批导入，或在类型列直接填写“转账 / 偿还借入 / 收回借出”。',
                                      ),
                                  ],
                                ),
                              ] else
                                select(
                                  '类型内容：$value',
                                  mapping.kinds[value] ??
                                      detectedKind(value)?.name,
                                  {
                                    '': '请关联',
                                    for (final kind in EntryKind.values)
                                      kind.name: kind.label,
                                  },
                                  (target) {
                                    mapping.kinds[value] = target;
                                  },
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
                                        data.accounts
                                            .where((a) => a.name == value)
                                            .singleOrNull
                                            ?.id,
                                    {
                                      '': '请关联',
                                      for (final account in data.accounts)
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
                                  if (!data.accounts.any(
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
                                                        data.accounts,
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
                            for (final (index, row)
                                in table.rows.indexed
                                    .where(
                                      (r) =>
                                          mapping.kindFor(r.$2)?.isSettlement ==
                                              true &&
                                          mapping
                                              .value(r.$2, ImportField.debt)
                                              .isEmpty,
                                    )
                                    .take(100))
                              select(
                                '第 ${index + 2} 行原始借贷 · ${mapping.counterpartyValue(row, mapping.kindFor(row))}',
                                mapping.debts[index + 2],
                                {
                                  '': '请明确选择原始借贷',
                                  for (final debt in eligibleImportDebts(
                                    row,
                                    mapping,
                                    data.accounts,
                                    data.entries,
                                  ))
                                    debt.id:
                                        '${debt.counterparty.isEmpty ? '未注明往来人' : debt.counterparty} · ${debt.date} · 剩余 ${money(debtRemaining(debt, data.entries), data.account(debt.accountId).currency)}${debt.note.isEmpty ? '' : ' · ${debt.note}'}',
                                },
                                (value) => mapping.debts[index + 2] = value,
                              ),
                            if (table.rows
                                    .where(
                                      (row) =>
                                          mapping.kindFor(row)?.isSettlement ==
                                              true &&
                                          mapping
                                              .value(row, ImportField.debt)
                                              .isEmpty,
                                    )
                                    .length >
                                100)
                              const Text(
                                '逐行关联原始借贷最多显示 100 行；请分批导入，或提供“原始借贷ID”列。',
                              ),
                            for (final kind in [
                              'expense',
                              'income',
                            ].where(activeKinds.contains))
                              for (final value in categoryValues.take(100))
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
