import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../core/time/business_date.dart';
import '../../../platform/files/file_delivery.dart';
import '../data/backup_service.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});
  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool busy = false;
  String status = '';
  Future<void> backup(bool share) async {
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() {
      busy = true;
      status = '正在制作完整备份…';
    });
    await perform(context, () async {
      final service = BackupService(
        ref.read(databaseProvider),
        await ref.read(mediaProvider.future),
      );
      final bytes = await service.export();
      final name =
          'so-account-backup-${dateKey(DateTime.now())}-${DateTime.now().millisecondsSinceEpoch}.zip';
      if (share) {
        await FileDelivery().share(name, bytes, origin);
      } else {
        await FileDelivery().save(name, bytes);
      }
    });
    if (mounted) {
      setState(() {
        busy = false;
        status = '';
      });
    }
  }

  Future<void> restore() async {
    setState(() => busy = true);
    await perform(context, () async {
      final bytes = await FileDelivery().pickBackup();
      if (bytes == null || !mounted) return;
      final approved = await confirm(
        context,
        '恢复并替换全部数据？',
        '当前账户、账目、物品、照片关联和设置将被备份内容替换。建议先保存一份当前备份。只有校验全部通过才会写入。',
      );
      if (!approved || !mounted) return;
      setState(() => status = '正在校验并恢复…');
      await BackupService(
        ref.read(databaseProvider),
        await ref.read(mediaProvider.future),
      ).restore(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('完整备份已恢复')));
      }
    });
    if (mounted) {
      setState(() {
        busy = false;
        status = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('完整备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.savings_outlined, size: 60),
          const SizedBox(height: 20),
          Text('把记录，妥善带走。', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text(
            '完整备份包含账户、分类、账目、预算、物品、照片和关联。文件不加密，请保存在自己的安全位置。\n\n单包限制：压缩后 50 MB、展开后 100 MB、最多 1000 张照片。恢复会替换全部数据。',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: busy ? null : () => backup(false),
            icon: const Icon(Icons.download_outlined),
            label: const Text('保存完整备份'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : () => backup(true),
            icon: const Icon(Icons.share_outlined),
            label: const Text('分享完整备份'),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: busy ? null : restore,
            icon: const Icon(Icons.restore),
            label: const Text('从备份恢复'),
          ),
          if (busy) ...[
            const SizedBox(height: 24),
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(status),
          ],
        ],
      ),
    ),
  );
}
