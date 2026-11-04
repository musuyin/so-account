import 'package:flutter/material.dart';

import '../core/money/money.dart';

class CurrencyButton extends StatelessWidget {
  const CurrencyButton({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  Future<void> select(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('选择货币', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final code in currencies)
                    ChoiceChip(
                      label: Text(code),
                      selected: code == value,
                      onSelected: (_) => Navigator.pop(context, code),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (context.mounted && selected != null && selected != value) {
      onChanged(selected);
    }
  }

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: () => select(context),
    icon: const Icon(Icons.arrow_drop_down),
    iconAlignment: IconAlignment.end,
    label: Text(value),
  );
}
