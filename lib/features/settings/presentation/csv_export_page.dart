import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/time/business_date.dart';
import '../../statistics/data/csv_export.dart';

class CsvExportPage extends ConsumerStatefulWidget {
  const CsvExportPage({super.key});
  @override
  ConsumerState<CsvExportPage> createState() => _CsvExportPageState();
}

class _CsvExportPageState extends ConsumerState<CsvExportPage> {
  bool busy = false, summary = false;
  ExportPeriod period = ExportPeriod.month;
  DateTime date = DateTime.now();
  Future<void> export(bool share) async {
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => busy = true);
    await perform(context, () async {
      final csv = await CsvExport(ref.read(databaseProvider))
          .create(period, date, summary: summary);
      final bytes = Uint8List.fromList(utf8.encode(csv));
      final name =
          'so-account-${summary ? 'summary' : 'transactions'}-${period.name}-${dateKey(date)}.csv';
      if (share) {
        await ref.read(fileDeliveryProvider).share(name, bytes, origin);
      } else {
        await ref.read(fileDeliveryProvider).save(name, bytes);
      }
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('导出 CSV')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('按币种分别统计，可保存或分享。'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('按分类汇总'),
          value: summary,
          onChanged: busy
              ? null
              : (v) => setState(() {
                  summary = v;
                  if (v && period == ExportPeriod.all) {
                    period = ExportPeriod.month;
                  }
                }),
        ),
        DropdownButtonFormField<ExportPeriod>(
          isExpanded: true,
          key: ValueKey('$summary-${period.name}'),
          initialValue: period,
          decoration: const InputDecoration(labelText: '导出范围'),
          items: [
            if (!summary)
              const DropdownMenuItem(
                value: ExportPeriod.all,
                child: Text('全部交易'),
              ),
            const DropdownMenuItem(
              value: ExportPeriod.month,
              child: Text('指定月份（默认本月）'),
            ),
            const DropdownMenuItem(
              value: ExportPeriod.year,
              child: Text('指定年份（默认本年）'),
            ),
          ],
          onChanged: busy ? null : (v) => setState(() => period = v!),
        ),
        if (period != ExportPeriod.all)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              period == ExportPeriod.month ? monthKey(date) : '${date.year} 年',
            ),
            subtitle: const Text('点击选择日期以定位月份 / 年份'),
            trailing: const Icon(Icons.calendar_today),
            onTap: busy
                ? null
                : () async {
                    final v = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                    );
                    if (v != null) setState(() => date = v);
                  },
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : () => export(false),
              icon: const Icon(Icons.download_outlined),
              label: const Text('保存 CSV'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => export(true),
              icon: const Icon(Icons.share_outlined),
              label: const Text('分享 CSV'),
            ),
          ],
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        const Text('CSV 用于分析，不能代替完整备份。'),
      ],
    ),
  );
}
