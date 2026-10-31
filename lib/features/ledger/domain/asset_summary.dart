import '../../../data/database/app_database.dart';
import 'entry_kind.dart';

class AssetSummary {
  const AssetSummary(this.assets, this.liabilities);
  final int assets, liabilities;
  int get net => assets - liabilities;
  factory AssetSummary.calculate(
    Iterable<Account> accounts,
    Map<String, int> balances,
  ) {
    var assets = 0, liabilities = 0;
    for (final account in accounts) {
      final amount = financeAccountAmount(
        account.kind,
        balances[account.id] ?? account.openingBalance,
      );
      switch (financeAccountSide(account.kind, account.channel)) {
        case FinanceAccountSide.asset:
          assets += amount;
        case FinanceAccountSide.liability:
          liabilities += amount;
        case FinanceAccountSide.excluded:
          break;
      }
    }
    return AssetSummary(assets, liabilities);
  }
}
