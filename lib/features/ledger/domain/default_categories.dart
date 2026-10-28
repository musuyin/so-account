/// Each list is both the initial content and initial display order.
/// IDs are explicit: moving a row never changes its identity. Existing ledgers
/// retain their own categories and saved order when these defaults change.
class DefaultCategory {
  const DefaultCategory(this.id, this.name);
  final String id, name;
}

const expenseDefaults = <DefaultCategory>[
  DefaultCategory('expense-0', '居住'),
  DefaultCategory('expense-1', '水电话费'),
  DefaultCategory('expense-2', '交通'),
  DefaultCategory('expense-food', '餐饮'),
  DefaultCategory('expense-education', '教育'),
  DefaultCategory('expense-20', '水果零食'),
  DefaultCategory('expense-21', '咖啡茶饮'),
  DefaultCategory('expense-22', '日用品'),
  DefaultCategory('expense-23', '服饰鞋包'),
  DefaultCategory('expense-24', '数码电器'),
  DefaultCategory('expense-25', '旅行'),
  DefaultCategory('expense-26', '宠物'),
  DefaultCategory('expense-27', '美容护理'),
  DefaultCategory('expense-28', '会员订阅'),
  DefaultCategory('expense-31', '育儿'),
  DefaultCategory('expense-8', '娱乐'),
  DefaultCategory('expense-9', '游戏'),
  DefaultCategory('expense-10', '健身'),
  DefaultCategory('expense-12', '保险'),
  DefaultCategory('expense-13', '医疗'),
  DefaultCategory('expense-14', '赡养'),
  DefaultCategory('expense-15', '人情'),
  DefaultCategory('expense-16', '理财亏损'),
  DefaultCategory('expense-ai', 'AI Token'),
  DefaultCategory('expense-32', '手续费'),
  DefaultCategory('expense-17', '其他损耗'),
];

const incomeDefaults = <DefaultCategory>[
  DefaultCategory('income-0', '工资'),
  DefaultCategory('income-1', '补贴'),
  DefaultCategory('income-2', '副业'),
  DefaultCategory('income-3', '投资'),
  DefaultCategory('income-4', '奖金'),
  DefaultCategory('income-5', '中奖'),
  DefaultCategory('income-6', '闲置'),
  DefaultCategory('income-7', '人情'),
  DefaultCategory('income-8', '报销'),
  DefaultCategory('income-9', '利息'),
  DefaultCategory('income-10', '分红'),
  DefaultCategory('income-11', '租金'),
  DefaultCategory('income-14', '其他收入'),
];
