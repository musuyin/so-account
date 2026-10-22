import 'package:drift/drift.dart';

import '../../../core/money/money.dart';
import '../../../data/database/app_database.dart';
import '../../statistics/data/csv_export.dart';
import 'goals_repository.dart';

class GoalsExport {
  GoalsExport(this.db);
  final AppDatabase db;
  Future<String> create({bool details = false}) => db.transaction(() async {
    final goals =
        await (db.select(db.wishGoals)..orderBy([
              (g) => OrderingTerm.asc(g.createdAt),
              (g) => OrderingTerm.asc(g.id),
            ]))
            .get();
    final records =
        await (db.select(db.goalContributions)..orderBy([
              (r) => OrderingTerm.asc(r.date),
              (r) => OrderingTerm.asc(r.createdAt),
            ]))
            .get();
    final byId = {for (final goal in goals) goal.id: goal};
    if (details) {
      return csvDocument([
        ['记录ID', '目标ID', '目标名称', '类型', '币种', '日期', '方向', '金额', '备注'],
        for (final row in records)
          [
            row.id,
            row.goalId,
            byId[row.goalId]!.name,
            goalKinds[byId[row.goalId]!.kind],
            byId[row.goalId]!.currency,
            row.date,
            row.amount > 0 ? '存入' : '取出',
            decimalMoney(row.amount.abs(), byId[row.goalId]!.currency),
            row.note,
          ],
      ]);
    }
    final totals = <String, int>{};
    for (final row in records) {
      totals.update(
        row.goalId,
        (v) => v + row.amount,
        ifAbsent: () => row.amount,
      );
    }
    return csvDocument([
      [
        '目标ID',
        '目标名称',
        '类型',
        '币种',
        '目标金额',
        '已记录进度',
        '还差金额',
        '截止日期',
        '优先级',
        '状态',
        '备注',
      ],
      for (final goal in goals)
        [
          goal.id,
          goal.name,
          goalKinds[goal.kind],
          goal.currency,
          decimalMoney(goal.target, goal.currency),
          decimalMoney(totals[goal.id] ?? 0, goal.currency),
          decimalMoney(
            (goal.target - (totals[goal.id] ?? 0)).clamp(0, maximumGoalAmount),
            goal.currency,
          ),
          goal.deadline,
          goalPriorities[goal.priority],
          goalStatuses[goal.status],
          goal.note,
        ],
    ]);
  });
}
