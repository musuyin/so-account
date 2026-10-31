import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../settings/presentation/csv_export_page.dart';
import '../data/finance_export.dart';
import '../data/finance_xlsx.dart';

final financeExportProvider = StreamProvider.autoDispose
    .family<FinanceExportData, (String, String, String)>(
      (ref, key) =>
          FinanceExportRepository(ref.watch(databaseProvider))
              .watch(key.$1, parseDate(key.$2), parseDate(key.$3)),
    );

enum _Format { markdown, excel }

enum _Scope { month, year, all }

class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({
    super.key,
    this.initialMonth,
    this.initialCurrency = 'CNY',
  });
  final DateTime? initialMonth;
  final String initialCurrency;
  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  _Format format = _Format.markdown;
  _Scope scope = _Scope.year;
  late DateTime date;
  late String currency;
  bool busy = false;
  final notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMonth ?? DateTime.now();
    date = DateTime(initial.year, initial.month);
    currency = widget.initialCurrency;
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<void> selectDate() async {
    final result = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
    if (result != null && mounted) {
      setState(() => date = DateTime(result.year, result.month));
    }
  }

  Future<void> copy(FinanceExportData data) async {
    if (busy) return;
    final text = monthlyMarkdown(
      data,
      notes: notes.text,
      hideAssets: ref.read(assetAmountsHiddenProvider),
    );
    setState(() => busy = true);
    await perform(
      context,
      () => Clipboard.setData(ClipboardData(text: text)),
      success: '已复制月度总结',
    );
    if (mounted) setState(() => busy = false);
  }

  Future<void> excel(bool share) async {
    if (busy || ref.read(assetAmountsHiddenProvider)) return;
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    final db = ref.read(databaseProvider);
    final delivery = ref.read(fileDeliveryProvider);
    final selected = date, selectedCurrency = currency, selectedScope = scope;
    setState(() => busy = true);
    await perform(context, () async {
      final start = switch (selectedScope) {
        _Scope.month => selected,
        _Scope.year => DateTime(selected.year),
        _Scope.all => null,
      };
      final end = selectedScope == _Scope.year
          ? DateTime(selected.year + 1)
          : DateTime(selected.year, selected.month + 1);
      final repository = FinanceExportRepository(db);
      final data = selectedScope == _Scope.all
          ? await repository.loadAll(selectedCurrency, DateTime.now())
          : await repository.load(selectedCurrency, start, end);
      final bytes = await compute(financeXlsx, data);
      if (!mounted || ref.read(assetAmountsHiddenProvider)) return;
      final label = selectedScope == _Scope.all
          ? 'all'
          : selectedScope == _Scope.year
          ? '${selected.year}'
          : monthKey(selected);
      final name = 'so-account-finance-$label-$selectedCurrency.xlsx';
      if (share) {
        await delivery.share(name, bytes, origin);
      } else {
        final saved = await delivery.save(name, bytes);
        if (saved && mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(const SnackBar(content: Text('已保存 Excel 汇总')));
        }
      }
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final hidden = ref.watch(assetAmountsHiddenProvider);
    final current = DateTime(date.year, date.month);
    final yearScope = format == _Format.excel && scope == _Scope.year;
    final atFirst = yearScope
        ? date.year <= 1900
        : !date.isAfter(DateTime(1900));
    final atLast = yearScope
        ? date.year >= 2100
        : !date.isBefore(DateTime(2100, 12));
    final key = (
      currency,
      dateKey(DateTime(date.year, date.month - 1)),
      dateKey(DateTime(date.year, date.month + 1)),
    );
    final report = format == _Format.markdown
        ? ref.watch(financeExportProvider(key))
        : null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('导出'),
        actions: [
          IconButton(
            tooltip: hidden ? '显示资产金额' : '隐藏资产金额',
            onPressed: busy
                ? null
                : () => ref.read(assetAmountsHiddenProvider.notifier).toggle(),
            icon: Icon(
              hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final entry in {
                _Format.markdown: '月度总结',
                _Format.excel: 'Excel 汇总',
              }.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: format == entry.key,
                  onSelected: busy
                      ? null
                      : (_) => setState(() => format = entry.key),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('币种'),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final value in currencies)
                ChoiceChip(
                  label: Text(value),
                  selected: currency == value,
                  onSelected: busy
                      ? null
                      : (_) => setState(() => currency = value),
                ),
            ],
          ),
          if (format == _Format.excel) ...[
            const SizedBox(height: 12),
            const Text('汇总范围'),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final entry in {
                  _Scope.month: '指定月份',
                  _Scope.year: '指定年份',
                  _Scope.all: '全部历史',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: scope == entry.key,
                    onSelected: busy
                        ? null
                        : (_) => setState(() => scope = entry.key),
                  ),
              ],
            ),
          ],
          if (format == _Format.markdown || scope != _Scope.all)
            Row(
              children: [
                IconButton(
                  tooltip: '上一期',
                  onPressed: busy || atFirst
                      ? null
                      : () => setState(() {
                          date = format == _Format.excel && scope == _Scope.year
                              ? DateTime(date.year - 1, date.month)
                              : DateTime(date.year, date.month - 1);
                        }),
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: busy ? null : selectDate,
                    child: Text(
                      format == _Format.excel && scope == _Scope.year
                          ? '${date.year} 年'
                          : monthKey(current),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下一期',
                  onPressed: busy || atLast
                      ? null
                      : () => setState(() {
                          date = format == _Format.excel && scope == _Scope.year
                              ? DateTime(date.year + 1, date.month)
                              : DateTime(date.year, date.month + 1);
                        }),
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          const SizedBox(height: 12),
          if (format == _Format.markdown) ...[
            Text(
              '对比 ${monthKey(current)} 与 ${monthKey(DateTime(date.year, date.month - 1))}，包含总体概况与收支、资产、负债明细。',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              enabled: !busy,
              minLines: 3,
              maxLines: 6,
              maxLength: 10000,
              decoration: const InputDecoration(
                counterText: '',
                labelText: '特殊说明（可选）',
                hintText: '追加到总结底部的「说明」',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (hidden) const Text('资产金额已隐藏，预览与复制会同步隐藏资产数值、占比和增长率。'),
            report!.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => TextButton(
                onPressed: () => ref.invalidate(financeExportProvider(key)),
                child: const Text('读取失败，点击重试'),
              ),
              data: (data) => Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: busy ? null : () => copy(data),
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('复制 Markdown'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => openForm(
                            context,
                            _MarkdownPreview(reportKey: key, notes: notes.text),
                          ),
                    icon: const Icon(Icons.article_outlined),
                    label: const Text('预览总结'),
                  ),
                ],
              ),
            ),
          ] else ...[
            const Text(
              'Income / Expense / Asset / Debt 四张表，每月一行，分类与账户按当前账本动态展开，包含归档账户。不同币种单独导出。',
            ),
            const SizedBox(height: 12),
            if (hidden) const Text('资产金额已隐藏，点击右上角显示金额后可导出 Excel。'),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy || hidden ? null : () => excel(false),
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('保存 Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: busy || hidden ? null : () => excel(true),
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('分享 Excel'),
                ),
              ],
            ),
          ],
          if (busy)
            const Padding(
              padding: EdgeInsets.all(16),
              child: LinearProgressIndicator(),
            ),
          const SizedBox(height: 20),
          const Text('统计口径'),
          const SizedBox(height: 6),
          Text(
            financeExportBasis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy
                  ? null
                  : () => openForm(context, const CsvExportPage()),
              icon: const Icon(Icons.table_rows_outlined),
              label: const Text('CSV 明细与分类汇总'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkdownPreview extends ConsumerWidget {
  const _MarkdownPreview({required this.reportKey, required this.notes});
  final (String, String, String) reportKey;
  final String notes;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(financeExportProvider(reportKey));
    final hidden = ref.watch(assetAmountsHiddenProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('月度总结预览'),
        actions: [
          IconButton(
            tooltip: hidden ? '显示资产金额' : '隐藏资产金额',
            onPressed: () =>
                ref.read(assetAmountsHiddenProvider.notifier).toggle(),
            icon: Icon(
              hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ],
      ),
      body: report.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(financeExportProvider(reportKey)),
            child: const Text('读取失败，点击重试'),
          ),
        ),
        data: (data) => SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            monthlyMarkdown(data, notes: notes, hideAssets: hidden),
          ),
        ),
      ),
    );
  }
}
