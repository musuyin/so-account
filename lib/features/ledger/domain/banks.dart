/// Stable bank IDs. Add official assets by ID when logos are available.
const bankLabels = <String, String>{
  '': '未指定银行',
  'icbc': '中国工商银行',
  'abc': '中国农业银行',
  'boc': '中国银行',
  'ccb': '中国建设银行',
  'bocom': '交通银行',
  'psbc': '中国邮政储蓄银行',
  'cmb': '招商银行',
  'citic': '中信银行',
  'ceb': '中国光大银行',
  'cmbc': '中国民生银行',
  'cib': '兴业银行',
  'spdb': '浦发银行',
  'pab': '平安银行',
  'cgb': '广发银行',
  'hxb': '华夏银行',
  'other': '其他银行',
};

bool isBankChannel(String? channel) => channel == '银行卡' || channel == '信用卡';
