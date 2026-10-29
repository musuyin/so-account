import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../data/database/app_database.dart';
import '../../ledger/presentation/home_page.dart';

typedef ReportRecordsQuery = ({
  String start,
  String end,
  String currency,
  String? category,
  String? kind,
  int limit,
});
final reportRecordsProvider = StreamProvider.autoDispose
    .family<HomeLedgerView, ReportRecordsQuery>(
      (ref, q) => LedgerReadRepository(ref.watch(databaseProvider)).watchRange(
        (
          month: q.start.substring(0, 7),
          currency: q.currency,
          day: null,
          kind: q.kind,
          category: q.category,
          search: '',
          limit: q.limit,
        ),
        q.start,
        q.end,
      ),
    );

class ReportRecordsPage extends ConsumerStatefulWidget {
  const ReportRecordsPage({
    super.key,
    required this.start,
    required this.end,
    required this.currency,
    this.category,
    this.kind,
  });
  final String start, end, currency;
  final String? category, kind;
  @override
  ConsumerState<ReportRecordsPage> createState() => _ReportRecordsPageState();
}

class _ReportRecordsPageState extends ConsumerState<ReportRecordsPage> {
  int limit = 100;
  @override
  Widget build(BuildContext context) {
    final q = (
      start: widget.start,
      end: widget.end,
      currency: widget.currency,
      category: widget.category,
      kind: widget.kind,
      limit: limit,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('统计明细')),
      body: QueryView<HomeLedgerView>(
        value: ref.watch(reportRecordsProvider(q)),
        retry: () => ref.invalidate(reportRecordsProvider(q)),
        builder: (view) {
          final groups = <String, List<Entry>>{};
          for (final entry in view.data.entries) {
            (groups[entry.date] ??= []).add(entry);
          }
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              ParameterText(
                '${widget.start} 至 ${widget.end}（不含结束日） · ${widget.currency}',
              ),
              ParameterText('共 ${view.count} 笔 · 仅收入与支出'),
              if (groups.isEmpty)
                const EmptyState('没有匹配的账目', '可返回统计选择其他日期或分类。'),
              for (final group in groups.entries)
                EntryDayCard(
                  date: group.key,
                  entries: group.value,
                  data: view.data,
                  totals: view.filteredDaily[group.key] ?? {},
                  currency: widget.currency,
                  filtered: true,
                ),
              if (view.count > view.data.entries.length)
                TextButton(
                  onPressed: () => setState(() => limit += 100),
                  child: const Text('显示更多记录'),
                ),
            ],
          );
        },
      ),
    );
  }
}
