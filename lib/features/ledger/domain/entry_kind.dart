enum EntryKind {
  expense('支出', -1),
  income('收入', 1),
  transfer('转账', -1),
  borrow('借入', 1),
  lend('借出', -1),
  repay('偿还借入', -1),
  collect('收回借出', 1);

  const EntryKind(this.label, this.direction);
  final String label;
  final int direction;
  bool get needsCategory => this == expense || this == income;
  bool get isSettlement => this == repay || this == collect;
}

const accountKinds = ['资金账户', '充值账户', '信贷账户', '理财账户'];
const accountChannels = ['银行卡', '微信支付', '支付宝', '花呗', '现金', '其他'];
