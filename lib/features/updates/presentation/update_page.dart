import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_controller.dart';

class UpdatePage extends ConsumerStatefulWidget {
  const UpdatePage({super.key});
  @override
  ConsumerState<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends ConsumerState<UpdatePage> {
  @override
  void initState() {
    super.initState();
    ref.read(updateControllerProvider).initialize();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(updateControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final update = controller.update;
        return Scaffold(
          appBar: AppBar(title: const Text('应用更新')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.system_update_outlined, size: 48),
              const SizedBox(height: 16),
              Text(
                '素帐 · SoAccount',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                controller.currentVersion.isEmpty
                    ? '正在读取版本…'
                    : '当前版本 ${controller.currentVersion} (${controller.currentBuild})',
              ),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动检查更新'),
                subtitle: const Text('启动或返回应用时检查，每天最多一次；连接 GitHub，不会自动下载'),
                value: controller.automatic,
                onChanged: controller.supported && !controller.busy
                    ? controller.setAutomatic
                    : null,
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: controller.supported && !controller.busy
                    ? () => controller.check(manual: true)
                    : null,
                icon: const Icon(Icons.refresh),
                label: const Text('检查更新'),
              ),
              if (controller.checking) const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Semantics(liveRegion: true, child: Text(controller.message)),
              if (update != null) ...[
                const SizedBox(height: 20),
                Card(
                  borderOnForeground: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '新版本 ${update.version}',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          'Android · ${update.abi} · 完整包 ${(update.apk.size / 1024 / 1024).toStringAsFixed(1)} MB',
                        ),
                        const Text('优先匹配差分补丁；旧包不匹配或合成失败时自动下载完整包。'),
                        const SizedBox(height: 12),
                        SelectableText(
                          update.notes.isEmpty ? '此版本未填写更新说明。' : update.notes,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (controller.android) ...[
                  if (controller.downloading) ...[
                    LinearProgressIndicator(
                      value: controller.total == 0
                          ? null
                          : controller.received / controller.total,
                    ),
                    Text(
                      '${(controller.received / 1024 / 1024).toStringAsFixed(1)} / '
                      '${(controller.total / 1024 / 1024).toStringAsFixed(1)} MB',
                    ),
                    TextButton(
                      onPressed: controller.cancel,
                      child: const Text('取消下载'),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed: controller.busy
                          ? null
                          : controller.downloaded == null
                          ? controller.download
                          : controller.install,
                      icon: Icon(
                        controller.downloaded == null
                            ? Icons.download
                            : Icons.install_mobile,
                      ),
                      label: Text(
                        controller.downloaded == null ? '下载更新包' : '安装更新',
                      ),
                    ),
                  if (controller.downloaded != null && !controller.busy)
                    TextButton(
                      onPressed: controller.download,
                      child: const Text('重新下载'),
                    ),
                  const Text(
                    '下载后校验 SHA-256；安装前校验应用标识、版本和签名。需要系统确认安装，不会清除账本数据。',
                  ),
                ] else
                  const Text('iOS 无法安装 APK。此处可查看更新说明，安装新版本需使用对应的 iOS 分发渠道。'),
              ],
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: controller.supported ? controller.openRelease : null,
                icon: const Icon(Icons.open_in_new),
                label: const Text('前往 GitHub Release'),
              ),
              const SizedBox(height: 12),
              const Text(
                '网络中断可重新下载。离开更新页面仍会继续下载；应用被系统关闭后需重新下载。建议更新前在“完整备份与恢复”中保存备份。',
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A persistent, dismissible notice avoids interrupting bookkeeping with a dialog.
class UpdateNotice extends ConsumerStatefulWidget {
  const UpdateNotice({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<UpdateNotice> createState() => _UpdateNoticeState();
}

class _UpdateNoticeState extends ConsumerState<UpdateNotice>
    with WidgetsBindingObserver {
  int? dismissedBuild;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(updateControllerProvider).check();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(updateControllerProvider).check();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(updateControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        children: [
          if (controller.update != null &&
              controller.update!.build != dismissedBuild)
            MaterialBanner(
              content: Text('素帐 ${controller.update!.version} 已发布'),
              actions: [
                TextButton(
                  onPressed: () =>
                      setState(() => dismissedBuild = controller.update!.build),
                  child: const Text('稍后'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const UpdatePage()),
                  ),
                  child: const Text('查看更新'),
                ),
              ],
            ),
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}
