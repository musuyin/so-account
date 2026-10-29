enum EntryKind {
  expense('支出', -1),
  income('收入', 1),
  transfer('转账', -1),
  borrow('借入', 1),
  lend('借出', -1),
  repay('偿还借入', -1),
  collect('收回借出', 1),
  reimburse('报销垫付', -1),
  reimbursement('报销回款', 1),
  invest('投资投入', -1),
  redeem('投资收回', 1);

  const EntryKind(this.label, this.direction);
  final String label;
  final int direction;
  bool get needsCategory => this == expense || this == income;
  bool get isSettlement =>
      this == repay || this == collect || this == reimbursement;
  bool get isReimbursement => this == reimburse || this == reimbursement;
  bool get isInvestment => this == invest || this == redeem;
  bool get isPrincipal => this == borrow || this == lend || this == reimburse;
  bool get isDebt => isPrincipal || isSettlement;
}

const accountTypes = <String, List<String>>{
  '资金账户': ['现金', '支付宝', '微信', '银行卡', 'QQ钱包', '自定义'],
  '信贷账户': ['信用卡', '花呗', '京东白条', '自定义'],
  '充值账户': ['会员卡', '公交卡', '饭卡', '押金', '自定义'],
  '投资理财': ['基金', '股票', '保险', '虚拟货币', '自定义'],
  '债务': ['应付款', '应收款', '报销'],
};
const accountKinds = ['资金账户', '信贷账户', '充值账户', '投资理财', '债务'];
const accountChannels = [
  '现金',
  '支付宝',
  '微信',
  '银行卡',
  'QQ钱包',
  '信用卡',
  '花呗',
  '京东白条',
  '会员卡',
  '公交卡',
  '饭卡',
  '押金',
  '基金',
  '股票',
  '保险',
  '虚拟货币',
  '自定义',
  '应付款',
  '应收款',
  '报销',
];

({String kind, String channel, String custom}) normalizeAccountType(
  String kind,
  String channel, [
  String custom = '',
]) {
  kind = kind == '理财账户' ? '投资理财' : kind;
  channel = channel == '微信支付' ? '微信' : channel;
  if (!accountTypes.containsKey(kind)) throw const FormatException('无效账户类型');
  if (channel == '其他' ||
      (!accountTypes[kind]!.contains(channel) &&
          ['现金', '银行卡', '支付宝', '微信', '花呗'].contains(channel))) {
    custom = custom.isEmpty ? channel : custom;
    channel = '自定义';
  }
  if (!accountTypes[kind]!.contains(channel)) {
    throw const FormatException('账户类别与类型不匹配');
  }
  if (custom.length > 40) throw const FormatException('自定义类别最多 40 字');
  return (kind: kind, channel: channel, custom: channel == '自定义' ? custom : '');
}

String? validateUnitPrice(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final text = value.trim();
  if (!RegExp(r'^\d{1,10}(\.\d{1,8})?$').hasMatch(text) ||
      BigInt.parse(text.replaceAll('.', '')) == BigInt.zero) {
    throw const FormatException('单价须大于零，最多 10 位整数和 8 位小数');
  }
  return text;
}

int assetBalance(String channel, int balance) =>
    channel == '应付款' ? -balance : balance;
