import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/providers.dart';
import '../../../app/widgets.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/appearance.dart';
import '../../../core/time/business_date.dart';
import '../../../data/database/app_database.dart';
import '../../../platform/files/file_delivery.dart';
import '../../statistics/data/csv_export.dart';
import 'categories_page.dart';
import 'item_categories_page.dart';
import 'local_data_page.dart';
import 'archived_accounts_page.dart';
import '../../importing/presentation/import_page.dart';
import '../../backup/presentation/backup_page.dart';
import '../../updates/presentation/update_page.dart';
import '../../goals/presentation/goals_page.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool busy = false;

  Future<void> preference(String key, String value) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await perform(context, () async {
        final db = ref.read(databaseProvider);
        await db
            .into(db.preferences)
            .insertOnConflictUpdate(
              PreferencesCompanion.insert(key: key, value: value),
            );
      });
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget tiles(List<Widget> children) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
      final count = scale > 1.3 ? 3 : 5;
      final width = (constraints.maxWidth - (count - 1) * 6) / count;
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final child in children)
            SizedBox(
              width: width,
              height: scale > 1.3 ? 108 * scale / 1.5 : 88,
              child: child,
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: DataView(
      builder: (data) {
        final preferences = ref.watch(preferencesProvider).value ?? [];
        String? value(String key) =>
            preferences.where((p) => p.key == key).firstOrNull?.value;
        final palette = AppPalette.parse(value('palette'));
        final mode = value('theme') ?? 'system';
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          children: [
            section('常用'),
            tiles([
              _SettingsTile(
                label: '归档账户',
                icon: Icons.archive_outlined,
                onTap: () => openForm(context, const ArchivedAccountsPage()),
              ),
              _SettingsTile(
                label: '心愿',
                icon: Icons.savings_outlined,
                onTap: () => openForm(context, const GoalsPage()),
              ),
              _SettingsTile(
                label: '收支分类',
                icon: Icons.category_outlined,
                onTap: () => openForm(context, const CategoriesPage()),
              ),
              _SettingsTile(
                label: '物品种类',
                icon: Icons.inventory_2_outlined,
                onTap: () => openForm(context, const ItemCategoriesPage()),
              ),
              _SettingsTile(
                label: '导入',
                tooltip: '导入交易明细 · Excel / CSV',
                icon: Icons.file_upload_outlined,
                onTap: () => openForm(context, const ImportPage()),
              ),
              _SettingsTile(
                label: '导出',
                icon: Icons.file_download_outlined,
                onTap: () => openForm(context, const ExportPage()),
              ),
              _SettingsTile(
                label: '备份恢复',
                tooltip: '完整备份与恢复 · 包括照片和全部关联',
                icon: Icons.backup_outlined,
                onTap: () => openForm(context, const BackupPage()),
              ),
              _SettingsTile(
                label: '更新',
                icon: Icons.system_update_outlined,
                onTap: () => openForm(context, const UpdatePage()),
              ),
            ]),
            section('颜色'),
            tiles([
              for (final value in AppPalette.values)
                _SettingsTile(
                  label: value.label,
                  compact: true,
                  selected: palette == value,
                  onTap: busy ? null : () => preference('palette', value.name),
                  preview: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final color in [
                        appTheme(
                          Brightness.light,
                          palette: value,
                        ).colorScheme.primary,
                        appTheme(
                          Brightness.light,
                          palette: value,
                        ).colorScheme.primaryContainer,
                        appTheme(
                          Brightness.light,
                          palette: value,
                        ).colorScheme.secondaryContainer,
                      ])
                        Container(
                          width: 8,
                          height: 18,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                    ],
                  ),
                ),
            ]),
            section('模式'),
            tiles([
              for (final (value, label, icon) in [
                ('system', '跟随系统', Icons.brightness_auto_outlined),
                ('light', '浅色', Icons.light_mode_outlined),
                ('dark', '深色', Icons.dark_mode_outlined),
              ])
                _SettingsTile(
                  label: label,
                  icon: icon,
                  selected: mode == value,
                  onTap: busy ? null : () => preference('theme', value),
                ),
            ]),
            section('数据管理'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('本地数据管理'),
              subtitle: const Text('清空业务数据或完全重置软件，需要确认'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () =>
                  Navigator.of(context, rootNavigator: true).push<void>(
                    MaterialPageRoute(builder: (_) => const LocalDataPage()),
                  ),
            ),
            const SizedBox(height: 24),
            const Text('素帐 · 本机存储'),
          ],
        );
      },
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.label,
    required this.onTap,
    this.icon,
    this.preview,
    this.tooltip,
    this.selected = false,
    this.compact = false,
  });
  final String label;
  final String? tooltip;
  final IconData? icon;
  final Widget? preview;
  final VoidCallback? onTap;
  final bool selected;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Tooltip(
        message: tooltip ?? label,
        child: Material(
          color: selected
              ? colors.primaryContainer
              : colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                if (selected)
                  Positioned(
                    top: 5,
                    right: 5,
                    child: Icon(
                      Icons.check_circle,
                      size: 14,
                      color: colors.primary,
                    ),
                  ),
                Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 4 : 5,
                      vertical: 4,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        preview ?? Icon(icon, size: 24, color: colors.primary),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: compact
                              ? Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(fontSize: 12, height: 1.25)
                              : Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ExportPage extends ConsumerStatefulWidget {
  const ExportPage({super.key});
  @override
  ConsumerState<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends ConsumerState<ExportPage> {
  bool busy = false, summary = false;
  ExportPeriod period = ExportPeriod.month;
  DateTime date = DateTime.now();
  Future<void> export(bool share) async {
    final box = context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero) & box.size;
    setState(() => busy = true);
    await perform(context, () async {
      final csv = await CsvExport(ref.read(databaseProvider))
          .create(period, date, summary: summary);
      final bytes = Uint8List.fromList(utf8.encode(csv));
      final name =
          'so-account-${summary ? 'summary' : 'transactions'}-${period.name}-${dateKey(date)}.csv';
      if (share) {
        await FileDelivery().share(name, bytes, origin);
      } else {
        await FileDelivery().save(name, bytes);
      }
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('导出 CSV')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('按币种分别统计，可保存或分享。'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('按分类汇总'),
          value: summary,
          onChanged: busy
              ? null
              : (v) => setState(() {
                  summary = v;
                  if (v && period == ExportPeriod.all) {
                    period = ExportPeriod.month;
                  }
                }),
        ),
        DropdownButtonFormField<ExportPeriod>(
          isExpanded: true,
          key: ValueKey('$summary-${period.name}'),
          initialValue: period,
          decoration: const InputDecoration(labelText: '导出范围'),
          items: [
            if (!summary)
              const DropdownMenuItem(
                value: ExportPeriod.all,
                child: Text('全部交易'),
              ),
            const DropdownMenuItem(
              value: ExportPeriod.month,
              child: Text('指定月份（默认本月）'),
            ),
            const DropdownMenuItem(
              value: ExportPeriod.year,
              child: Text('指定年份（默认本年）'),
            ),
          ],
          onChanged: busy ? null : (v) => setState(() => period = v!),
        ),
        if (period != ExportPeriod.all)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              period == ExportPeriod.month ? monthKey(date) : '${date.year} 年',
            ),
            subtitle: const Text('点击选择日期以定位月份 / 年份'),
            trailing: const Icon(Icons.calendar_today),
            onTap: busy
                ? null
                : () async {
                    final v = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                    );
                    if (v != null) setState(() => date = v);
                  },
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : () => export(false),
              icon: const Icon(Icons.download_outlined),
              label: const Text('保存 CSV'),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => export(true),
              icon: const Icon(Icons.share_outlined),
              label: const Text('分享 CSV'),
            ),
          ],
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          ),
        const Text('CSV 用于分析，不能代替完整备份。'),
      ],
    ),
  );
}
