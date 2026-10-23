import 'package:flutter/material.dart';

import '../../../data/database/app_database.dart';
import '../domain/banks.dart';

const avatarLabels = {
  '': '首字头像',
  'wechat': '微信',
  'alipay': '支付宝',
  'bank': '银行',
  'huabei': '花呗',
};

class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.account});
  final Account account;
  @override
  Widget build(BuildContext context) {
    if (isBankChannel(account.channel) &&
        account.bank.isNotEmpty &&
        (account.avatar.isEmpty || account.avatar == 'bank')) {
      final label = bankLabels[account.bank] ?? '银行';
      return Tooltip(
        message: label,
        child: Semantics(
          label: label,
          child: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: const Icon(Icons.account_balance),
          ),
        ),
      );
    }
    final (Color color, Widget child) = switch (account.avatar) {
      'wechat' => (
        const Color(0xFF168C45),
        const Icon(Icons.forum_rounded, color: Colors.white),
      ),
      'alipay' => (
        const Color(0xFF1565C0),
        const Text(
          '支',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      'bank' => (
        const Color(0xFFB33D42),
        const Icon(Icons.account_balance, color: Colors.white),
      ),
      'huabei' => (
        const Color(0xFF387AB3),
        const Icon(Icons.local_florist, color: Colors.white),
      ),
      _ => (
        Theme.of(context).colorScheme.primaryContainer,
        Text(account.name.characters.first),
      ),
    };
    return Semantics(
      label: avatarLabels[account.avatar] ?? '账户头像',
      child: CircleAvatar(backgroundColor: color, child: child),
    );
  }
}
