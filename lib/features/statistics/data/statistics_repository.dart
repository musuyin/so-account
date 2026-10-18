import 'package:drift/drift.dart';

import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';

class StatisticsRepository {
  StatisticsRepository(this.db);
  final AppDatabase db;
  Stream<List<Breakdown>> watchBreakdown(DateTime month, String currency) => db
      .customSelect(
        '''
    SELECT c.name, e.kind, SUM(e.amount) AS total FROM entries e
    JOIN accounts a ON a.id = e.account_id JOIN categories c ON c.id = e.category_id
    WHERE e.date >= ? AND e.date < ? AND a.currency = ?
    GROUP BY c.id, c.name, e.kind ORDER BY total DESC
  ''',
        variables: [
          Variable('${monthKey(month)}-01'),
          Variable(dateKey(DateTime(month.year, month.month + 1))),
          Variable(currency),
        ],
        readsFrom: {db.entries, db.accounts, db.categories},
      )
      .watch()
      .map(
        (rows) => rows
            .map(
              (r) => Breakdown(
                r.read<String>('name'),
                r.read<String>('kind'),
                r.read<int>('total'),
              ),
            )
            .toList(),
      );

  Stream<List<Trend>> watchTrend(DateTime month, String currency) => db
      .customSelect(
        '''
    SELECT substr(e.date,1,7) AS month, e.kind, SUM(e.amount) AS total
    FROM entries e JOIN accounts a ON a.id = e.account_id
    WHERE e.date >= ? AND e.date < ? AND a.currency = ? AND e.kind IN ('income','expense')
    GROUP BY month, e.kind ORDER BY month
  ''',
        variables: [
          Variable(dateKey(DateTime(month.year, month.month - 5))),
          Variable(dateKey(DateTime(month.year, month.month + 1))),
          Variable(currency),
        ],
        readsFrom: {db.entries, db.accounts},
      )
      .watch()
      .map(
        (rows) => rows
            .map(
              (r) => Trend(
                r.read<String>('month'),
                r.read<String>('kind'),
                r.read<int>('total'),
              ),
            )
            .toList(),
      );
}

class Breakdown {
  const Breakdown(this.name, this.kind, this.amount);
  final String name, kind;
  final int amount;
}

class Trend {
  const Trend(this.month, this.kind, this.amount);
  final String month, kind;
  final int amount;
}
