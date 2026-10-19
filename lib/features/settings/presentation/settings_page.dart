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

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
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
    appBar: AppBar(title: const Text('偏好与数据')),
    body: DataView(
      builder: (data) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('配色主题', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final palette in AppPalette.values)
            Card(
              child: ListTile(
                selected:
                    AppPalette.parse(data.preference('palette', 'classic')) ==
                    palette,
                title: Text(palette.label),
                subtitle: Wrap(
                  spacing: 6,
                  children: [
                    for (final color in [
                      appTheme(
                        Brightness.light,
                        palette: palette,
                      ).colorScheme.surface,
                      appTheme(
                        Brightness.light,
                        palette: palette,
                      ).colorScheme.primaryContainer,
                      appTheme(
                        Brightness.light,
                        palette: palette,
                      ).colorScheme.secondaryContainer,
                    ])
                      Container(
                        width: 22,
                        height: 14,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                  ],
                ),
                trailing: Icon(
                  AppPalette.parse(data.preference('palette', 'classic')) ==
                          palette
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: Theme.of(context).colorScheme.primary,
                ),
                onTap: busy
                    ? null
                    : () => perform(context, () async {
                        final db = ref.read(databaseProvider);
                        await db
                            .into(db.preferences)
                            .insertOnConflictUpdate(
                              PreferencesCompanion.insert(
                                key: 'palette',
                                value: palette.name,
                              ),
                            );
                      }),
              ),
            ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(data.preference('theme', 'system')),
            initialValue: data.preference('theme', 'system'),
            decoration: const InputDecoration(labelText: '外观'),
            items: const [
              DropdownMenuItem(value: 'system', child: Text('跟随系统')),
              DropdownMenuItem(value: 'light', child: Text('日间模式')),
              DropdownMenuItem(value: 'dark', child: Text('深色模式')),
            ],
            onChanged: busy
                ? null
                : (value) => perform(context, () async {
                    final db = ref.read(databaseProvider);
                    await db
                        .into(db.preferences)
                        .insertOnConflictUpdate(
                          PreferencesCompanion.insert(
                            key: 'theme',
                            value: value!,
                          ),
                        );
                  }),
          ),
          const SizedBox(height: 16),
          Text('分类管理', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.category_outlined),
              title: const Text('自定义收支分类'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openForm(context, const CategoriesPage()),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('自定义物品种类'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openForm(context, const ItemCategoriesPage()),
            ),
          ),
          const SizedBox(height: 24),
          Text('数据与备份', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('完整备份与恢复'),
              subtitle: const Text('包括照片、账户和全部关联'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openForm(context, const BackupPage()),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('导入交易明细'),
              subtitle: const Text('Excel / CSV · 关联列名并逐条选择'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => openForm(context, const ImportPage()),
            ),
          ),
          const SizedBox(height: 24),
          Text('导出 CSV', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('明细或分类汇总，币种分别统计，可保存或分享给其他应用。'),
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
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
          const SizedBox(height: 32),
          const Text(
            '素帐 · SoAccount 0.4.0\n离线存储于本机 · 无登录、无云同步\nCSV 用于分析，不能代替完整备份。',
          ),
        ],
      ),
    ),
  );
}
