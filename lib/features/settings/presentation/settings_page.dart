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
  bool busy = false, summary = false;
  ExportPeriod period = ExportPeriod.month;
  DateTime date = DateTime.now();

  Future<void> preference(String key, String value) async {
    await perform(context, () async {
      final db = ref.read(databaseProvider);
      await db
          .into(db.preferences)
          .insertOnConflictUpdate(
            PreferencesCompanion.insert(key: key, value: value),
          );
    });
  }

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

  Widget section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(title, style: Theme.of(context).textTheme.titleMedium),
  );

  Widget tiles(List<Widget> children, {int columns = 3}) => LayoutBuilder(
    builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 17.5;
      final count = largeText
          ? 2
          : columns == 4
          ? 4
          : columns.clamp(
              1,
              ((constraints.maxWidth + 10) / 90).floor().clamp(1, columns),
            );
      final size = ((constraints.maxWidth - (count - 1) * 10) / count).clamp(
        0.0,
        largeText
            ? 180.0
            : columns == 4
            ? 88.0
            : 112.0,
      );
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final child in children)
            SizedBox(width: size, height: size, child: child),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('偏好与数据')),
    body: DataView(
      builder: (data) {
        final palette = AppPalette.parse(
          data.preference('palette', 'cucumber'),
        );
        final mode = data.preference('theme', 'system');
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            section('常用功能'),
            tiles([
              _SettingsTile(
                label: '心愿与攒钱',
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
                label: '导入明细',
                tooltip: '导入交易明细 · Excel / CSV',
                icon: Icons.file_upload_outlined,
                onTap: () => openForm(context, const ImportPage()),
              ),
              _SettingsTile(
                label: '备份与恢复',
                tooltip: '完整备份与恢复 · 包括照片和全部关联',
                icon: Icons.backup_outlined,
                onTap: () => openForm(context, const BackupPage()),
              ),
              _SettingsTile(
                label: '应用更新',
                icon: Icons.system_update_outlined,
                onTap: () => openForm(context, const UpdatePage()),
              ),
            ]),
            section('配色主题'),
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
                          width: 11,
                          height: 18,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                    ],
                  ),
                ),
            ], columns: 4),
            section('外观'),
            tiles([
              for (final (value, label, icon) in [
                ('system', '跟随系统', Icons.brightness_auto_outlined),
                ('light', '日间模式', Icons.light_mode_outlined),
                ('dark', '深色模式', Icons.dark_mode_outlined),
              ])
                _SettingsTile(
                  label: label,
                  icon: icon,
                  selected: mode == value,
                  onTap: busy ? null : () => preference('theme', value),
                ),
            ]),
            section('导出 CSV'),
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
                  child: Text('指定月份 · 默认本月'),
                ),
                const DropdownMenuItem(
                  value: ExportPeriod.year,
                  child: Text('指定年份 · 默认本年'),
                ),
              ],
              onChanged: busy ? null : (v) => setState(() => period = v!),
            ),
            if (period != ExportPeriod.all)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  period == ExportPeriod.month
                      ? monthKey(date)
                      : '${date.year} 年',
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
            const SizedBox(height: 24),
            const Text(
              '素帐 · SoAccount\n账本存储于本机 · 检查更新会连接 GitHub\nCSV 用于分析，不能代替完整备份。',
            ),
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
                      vertical: compact ? 4 : 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        preview ?? Icon(icon, size: 24, color: colors.primary),
                        SizedBox(height: compact ? 4 : 7),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: compact
                              ? Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(fontSize: 10, height: 1.25)
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
