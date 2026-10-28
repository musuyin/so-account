// Preserve each source export separately instead of mixing account roles.
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
];

const transferTemplateHeaders = [
  '日期',
  '类型',
  '转出账户',
  '转入账户',
  '金额',
  '手续费',
  '备注',
  '附件1',
  '附件2',
  '附件3',
  '附件4',
  '附件5',
];

List<List<String>> importTemplateRows() => [
  importTemplateHeaders,
  for (final values in [
    {
      '日期': '2026-01-01',
      '收支类型': '支出',
      '金额': '12.50',
      '类别': '餐饮',
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
  ])
    [for (final header in importTemplateHeaders) values[header] ?? ''],
];

List<List<String>> transferTemplateRows() => [
  transferTemplateHeaders,
  [
    '2026-01-03',
    '转账',
    '我的银行卡',
    '我的现金账户',
    '100.00',
    '1.00',
    '示例：转出 101，转入 100，手续费支出 1；请替换后导入',
    '',
    '',
    '',
    '',
    '',
  ],
];
