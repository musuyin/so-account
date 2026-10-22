import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/money/money.dart';
import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';

const goalKinds = {'wish': '心愿', 'saving': '攒钱'};
const goalStatuses = {'active': '进行中', 'completed': '已完成', 'archived': '已归档'};
const goalPriorities = {2: '优先', 1: '普通', 0: '随心'};
const maximumGoalAmount = 999999999999;

int goalSaved(String id, Iterable<GoalContribution> rows) =>
    rows.where((r) => r.goalId == id).fold(0, (sum, row) => sum + row.amount);

int goalDaysLeft(String deadline, DateTime now) {
  final day = parseDate(deadline);
  return DateTime.utc(
    day.year,
    day.month,
    day.day,
  ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
}

// Rounded up in minor units: the displayed daily plan never understates a goal.
int goalDailyAmount(WishGoal goal, int saved, DateTime now) {
  if (goal.deadline == null || saved >= goal.target) return 0;
  final days = goalDaysLeft(goal.deadline!, now) + 1;
  if (days <= 0) return 0;
  return (goal.target - saved + days - 1) ~/ days;
}

class GoalsRepository {
  GoalsRepository(this.db);
  final AppDatabase db;

  static void validateGoal(WishGoal goal) {
    if (goal.name.trim().isEmpty ||
        goal.name.length > 100 ||
        !goalKinds.containsKey(goal.kind) ||
        !currencies.contains(goal.currency) ||
        goal.target <= 0 ||
        goal.target > maximumGoalAmount ||
        !goalPriorities.containsKey(goal.priority) ||
        !goalStatuses.containsKey(goal.status) ||
        goal.note.length > 2000 ||
        goal.createdAt < 0 ||
        goal.updatedAt < goal.createdAt) {
      throw const FormatException('心愿或攒钱目标数据无效');
    }
    if (goal.deadline != null) parseDate(goal.deadline!);
  }

  static void validateHistory(
    WishGoal goal,
    Iterable<GoalContribution> records,
  ) {
    validateGoal(goal);
    var saved = 0;
    final ordered = records.where((r) => r.goalId == goal.id).toList()
      ..sort((a, b) {
        final day = a.date.compareTo(b.date);
        if (day != 0) return day;
        final time = a.createdAt.compareTo(b.createdAt);
        return time != 0 ? time : a.id.compareTo(b.id);
      });
    for (final row in ordered) {
      parseDate(row.date);
      if (row.amount == 0 ||
          row.amount.abs() > maximumGoalAmount ||
          row.note.length > 500 ||
          row.createdAt < 0) {
        throw const FormatException('攒钱记录无效');
      }
      saved += row.amount;
      if (saved < 0 || saved > maximumGoalAmount) {
        throw const FormatException('取出金额超过已攒金额，或累计金额超出上限');
      }
    }
    if (goal.kind == 'saving' &&
        goal.status == 'completed' &&
        saved < goal.target) {
      throw const FormatException('攒钱目标尚未达成，请先恢复为进行中');
    }
  }

  Future<WishGoal> _goal(String id) async {
    final goal = await (db.select(
      db.wishGoals,
    )..where((g) => g.id.equals(id))).getSingleOrNull();
    if (goal == null) throw const FormatException('目标已不存在');
    return goal;
  }

  Future<List<GoalContribution>> _records(String id) => (db.select(
    db.goalContributions,
  )..where((r) => r.goalId.equals(id))).get();

  Future<String> save({
    String? id,
    required String name,
    required String kind,
    required String currency,
    required int target,
    String? deadline,
    int priority = 1,
    String note = '',
    int initialSaved = 0,
  }) => db.transaction(() async {
    final old = id == null ? null : await _goal(id);
    final records = id == null ? <GoalContribution>[] : await _records(id);
    if (old != null && records.isNotEmpty && old.currency != currency) {
      throw const FormatException('已有攒钱记录，不能更改币种');
    }
    if (initialSaved < 0 ||
        initialSaved > maximumGoalAmount ||
        old != null && initialSaved != 0) {
      throw const FormatException('初始进度无效；已有目标请使用存入或取出');
    }
    final now = DateTime.now();
    final stamp = now.toUtc().millisecondsSinceEpoch;
    final goal = WishGoal(
      id: id ?? const Uuid().v4(),
      name: name.trim(),
      kind: kind,
      currency: currency,
      target: target,
      deadline: deadline,
      priority: priority,
      status: old?.status ?? 'active',
      note: note.trim(),
      createdAt: old?.createdAt ?? stamp,
      updatedAt: stamp,
    );
    validateHistory(goal, records);
    await db.into(db.wishGoals).insertOnConflictUpdate(goal);
    if (initialSaved > 0) {
      await db
          .into(db.goalContributions)
          .insert(
            GoalContribution(
              id: const Uuid().v4(),
              goalId: goal.id,
              amount: initialSaved,
              date: dateKey(now),
              note: '初始进度',
              createdAt: stamp,
            ),
          );
    }
    return goal.id;
  });

  Future<void> contribute({
    required String goalId,
    required int amount,
    required String date,
    String note = '',
    String? expectedCurrency,
  }) => db.transaction(() async {
    final goal = await _goal(goalId);
    if (expectedCurrency != null && goal.currency != expectedCurrency) {
      throw const FormatException('目标币种已变化，请重新打开进度记录');
    }
    if (goal.status != 'active') throw const FormatException('请先将目标恢复为进行中');
    final records = await _records(goalId);
    // Stable same-day ordering, including multiple saves in one millisecond.
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final lastStamp = records.fold(
      0,
      (int value, r) => value > r.createdAt ? value : r.createdAt,
    );
    final row = GoalContribution(
      id: const Uuid().v4(),
      goalId: goalId,
      amount: amount,
      date: date,
      note: note.trim(),
      createdAt: stamp > lastStamp ? stamp : lastStamp + 1,
    );
    validateHistory(goal, [...records, row]);
    if (date.compareTo(dateKey(DateTime.now())) > 0) {
      throw const FormatException('攒钱日期不能在未来');
    }
    await db.into(db.goalContributions).insert(row);
    await (db.update(db.wishGoals)..where((g) => g.id.equals(goalId))).write(
      WishGoalsCompanion(updatedAt: Value(row.createdAt)),
    );
  });

  Future<void> setStatus(String id, String status) => db.transaction(() async {
    final goal = await _goal(id);
    final next = goal.copyWith(
      status: status,
      updatedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
    );
    validateHistory(next, await _records(id));
    await db.into(db.wishGoals).insertOnConflictUpdate(next);
  });

  Future<void> deleteContribution(String id) => db.transaction(() async {
    final row = await (db.select(
      db.goalContributions,
    )..where((r) => r.id.equals(id))).getSingleOrNull();
    if (row == null) throw const FormatException('记录已不存在');
    final goal = await _goal(row.goalId);
    if (goal.status != 'active') throw const FormatException('请先将目标恢复为进行中');
    validateHistory(goal, (await _records(goal.id)).where((r) => r.id != id));
    await (db.delete(db.goalContributions)..where((r) => r.id.equals(id))).go();
  });

  Future<void> delete(String id) => db.transaction(() async {
    await _goal(id);
    await (db.delete(db.wishGoals)..where((g) => g.id.equals(id))).go();
  });
}
