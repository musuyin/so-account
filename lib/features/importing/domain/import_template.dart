// Keep the original statement columns in order; append explicit transfer roles.
const importTemplateHeaders = [
  '日期',
  '收支类型',
  '金额',
  '类别',
  '二级分类',
  '账户',
  '账本',
  '退款',
  '优惠',
  '备注',
  '标签',
  '报销账户',
  '报销金额',
  '报销明细',
  '多币种',
  '地址',
  '创建用户',
  '其他',
  '附件1',
  '附件2',
  '附件3',
  '附件4',
  '附件5',
  '源账户',
  '目标账户',
];

List<List<String>> importTemplateRows() => [
  importTemplateHeaders,
  for (final values in [
    {
      '日期': '2026-01-01',
      '收支类型': '支出',
      '金额': '-12.50',
      '类别': '普通餐饮',
      '账户': '我的现金账户',
      '备注': '示例支出：请替换后导入',
    },
    {
      '日期': '2026-01-02',
      '收支类型': '收入',
      '金额': '20.00',
      '类别': '工资',
      '账户': '我的银行卡',
      '备注': '示例收入：请替换后导入',
    },
    {
      '日期': '2026-01-03',
      '收支类型': '转账',
      '金额': '100.00',
      '源账户': '我的银行卡',
      '目标账户': '我的现金账户',
      '备注': '示例转账：一行同时包含源账户和目标账户',
    },
  ])
    [for (final header in importTemplateHeaders) values[header] ?? ''],
];
