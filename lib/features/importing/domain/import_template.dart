// Same flat column layout as the reference ledger workbook. Auxiliary columns
// are retained for familiarity; only ordinary income/expense fields are read.
const importTemplateHeaders = [
  '日期',
  '收支类型',
  '金额',
  '类别',
  '账户',
  '账本',
  '退款',
  '退款明细',
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
];

const importTemplateAsset = 'assets/templates/income_expense_template.xlsx';

List<List<String>> importTemplateRows() => [
  importTemplateHeaders,
  for (final values in [
    {
      '日期': '2026-01-01 12:30',
      '收支类型': '支出',
      '金额': '12.50',
      '类别': '餐饮',
      '账户': '我的现金账户',
      '账本': '示例账本',
      '备注': '示例支出：请替换后导入',
    },
    {
      '日期': '2026-01-02 09:00',
      '收支类型': '收入',
      '金额': '20.00',
      '类别': '工资',
      '账户': '我的银行卡',
      '账本': '示例账本',
      '备注': '示例收入：请替换后导入',
    },
  ])
    [for (final header in importTemplateHeaders) values[header] ?? ''],
];
