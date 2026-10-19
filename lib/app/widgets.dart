import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/providers.dart';

class DataView extends ConsumerWidget {
  const DataView({super.key, required this.builder});
  final Widget Function(AppSnapshot) builder;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(snapshotProvider)
      .when(
        data: builder,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('数据读取失败，请重试'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref.invalidate(snapshotProvider),
                child: const Text('重新加载'),
              ),
            ],
          ),
        ),
      );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    ) ??
    false;

Future<bool> perform(
  BuildContext context,
  Future<void> Function() action, {
  String? success,
}) async {
  try {
    await action();
    if (context.mounted && success != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException ? e.message.toString() : '操作失败，请重试',
            ),
          ),
        );
    }
    return false;
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.title, this.subtitle, {super.key});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      children: [
        Icon(
          Icons.spa_outlined,
          size: 44,
          color: Theme.of(context).colorScheme.secondary,
        ),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(subtitle, textAlign: TextAlign.center),
      ],
    ),
  );
}

class FormFrame extends StatelessWidget {
  const FormFrame({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.saving = false,
  });
  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final bool saving;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ...children.expand((w) => [w, const SizedBox(height: 16)]),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: KeyboardActionBar(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: saving ? null : onSave,
                  icon: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(saving ? '保存中…' : '保存'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> openForm(BuildContext context, Widget page) =>
    Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => page));

class KeyboardActionBar extends StatelessWidget {
  const KeyboardActionBar({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(top: false, child: child),
  );
}

class ClearableSearch extends StatefulWidget {
  const ClearableSearch({
    super.key,
    required this.value,
    required this.onChanged,
    required this.hint,
  });
  final String value, hint;
  final ValueChanged<String> onChanged;
  @override
  State<ClearableSearch> createState() => _ClearableSearchState();
}

class _ClearableSearchState extends State<ClearableSearch> {
  late final controller = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(covariant ClearableSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (controller.text != widget.value) {
      controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    onChanged: widget.onChanged,
    decoration: InputDecoration(
      hintText: widget.hint,
      prefixIcon: const Icon(Icons.search),
      suffixIcon: widget.value.isEmpty
          ? null
          : IconButton(
              tooltip: '清除搜索',
              onPressed: () => widget.onChanged(''),
              icon: const Icon(Icons.close),
            ),
    ),
  );
}
