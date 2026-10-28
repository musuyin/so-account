import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../updates/presentation/update_controller.dart';
import '../data/local_data_service.dart';

String _title(LocalDataAction action) =>
    action == LocalDataAction.clearData ? '清空本地数据' : '重置软件';
String _phrase(LocalDataAction action) =>
    action == LocalDataAction.clearData ? '清空数据' : '重置软件';

class LocalDataPage extends ConsumerStatefulWidget {
  const LocalDataPage({super.key});
  @override
  ConsumerState<LocalDataPage> createState() => _LocalDataPageState();
}

class _LocalDataPageState extends ConsumerState<LocalDataPage> {
  bool busy = false, pending = false, confirming = false;
  String? error;
  LocalDataAction? action;

  Future<void> run(LocalDataAction value, {bool retry = false}) async {
    if (busy || confirming) return;
    if (!retry) {
      setState(() => confirming = true);
      final approved = await showDialog<bool>(
        context: context,
        builder: (_) => _ConfirmLocalDataAction(action: value),
      );
      if (!mounted) return;
      setState(() => confirming = false);
      if (approved != true) return;
    }
    final updates = ref.read(updateControllerProvider);
    final service = ref.read(localDataServiceProvider);
    setState(() {
      busy = true;
      error = null;
      action = value;
    });
    try {
      await updates.pauseForDataMaintenance();
      if (retry) {
        await service.resumeCleanup();
      } else {
        await service.execute(value);
      }
      updates.finishDataMaintenance(
        resetSettings: value == LocalDataAction.resetApp,
      );
      if (!mounted) return;
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
      ref.invalidate(mediaProvider);
      setState(() {
        busy = false;
        pending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value == LocalDataAction.resetApp
                ? '已重置软件，已使用当前版本默认分类'
                : '本地业务数据已清空，分类和软件设置已保留',
          ),
        ),
      );
      ref.read(appSessionProvider.notifier).restart();
    } on LocalCleanupException {
      if (mounted) {
        setState(() {
          busy = false;
          pending = true;
          error = '账本已清空，但部分本地文件清理未完成。请重试清理；重开应用也会继续清理。';
        });
      }
    } catch (e) {
      updates.finishDataMaintenance(resetSettings: false, cleared: false);
      if (mounted) {
        setState(() {
          busy = false;
          error = e is FormatException ? e.message : '操作未完成，原有账本和照片已保留，请重试';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !pending,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('本地数据管理'),
        automaticallyImplyLeading: !busy && !pending,
      ),
      body: AbsorbPointer(
        absorbing: busy,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('请先将需要的完整备份保存到应用外。操作不可撤销。'),
            const SizedBox(height: 8),
            const Text('两项操作都会删除全部账户、流水、借贷、预算、心愿、物品、应用内照片和缓存。'),
            const SizedBox(height: 12),
            for (final value in LocalDataAction.values)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title(value),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        value == LocalDataAction.clearData
                            ? '保留：收支分类、物品种类、分类顺序与图标、配色和自动更新设置。'
                            : '同时删除全部自定义分类和软件设置，重新使用当前版本默认分类与设置。',
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: pending || confirming
                            ? null
                            : () => run(value),
                        icon: Icon(
                          value == LocalDataAction.clearData
                              ? Icons.delete_sweep_outlined
                              : Icons.restart_alt,
                        ),
                        label: Text(_title(value)),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              '已保存到下载目录、其他应用或外部存储的备份不在删除范围内。系统云备份也不会由此删除；恢复旧备份会再次带回旧分类。',
            ),
            if (busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              Semantics(
                liveRegion: true,
                child: Text('${_title(action!)}中，请稍候…'),
              ),
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
            if (pending)
              FilledButton(
                onPressed: busy ? null : () => run(action!, retry: true),
                child: const Text('重试清理'),
              ),
          ],
        ),
      ),
    ),
  );
}

class _ConfirmLocalDataAction extends StatefulWidget {
  const _ConfirmLocalDataAction({required this.action});
  final LocalDataAction action;
  @override
  State<_ConfirmLocalDataAction> createState() =>
      _ConfirmLocalDataActionState();
}

class _ConfirmLocalDataActionState extends State<_ConfirmLocalDataAction> {
  String input = '';
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${_phrase(widget.action)}？'),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('全部账本、物品及应用内照片将永久删除，无法撤销。请先保存需要的备份。'),
        const SizedBox(height: 12),
        Text(
          widget.action == LocalDataAction.clearData
              ? '分类及软件设置会保留。'
              : '分类及软件设置也会删除，重新使用当前版本默认值。',
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('local-data-confirmation'),
          decoration: InputDecoration(
            labelText: '输入“${_phrase(widget.action)}”确认',
            floatingLabelBehavior: FloatingLabelBehavior.always,
          ),
          onChanged: (value) => setState(() => input = value),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('取消'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
          foregroundColor: Theme.of(context).colorScheme.onError,
        ),
        onPressed: input == _phrase(widget.action)
            ? () => Navigator.pop(context, true)
            : null,
        child: Text(
          widget.action == LocalDataAction.clearData ? '确认清空' : '确认重置',
        ),
      ),
    ],
  );
}
