class AssetSummary {
  const AssetSummary(this.assets, this.liabilities);
  final int assets, liabilities;
  int get net => assets - liabilities;
  factory AssetSummary.calculate(
    Iterable<int> balances, {
    int receivable = 0,
    int payable = 0,
  }) {
    var assets = receivable, liabilities = payable;
    for (final balance in balances) {
      if (balance >= 0) {
        assets += balance;
      } else {
        liabilities -= balance;
      }
    }
    return AssetSummary(assets, liabilities);
  }
}
