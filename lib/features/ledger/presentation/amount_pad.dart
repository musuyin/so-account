import 'package:flutter/material.dart';

import '../../../core/money/calculator.dart';
import '../../../core/money/money.dart';

class AmountPad extends StatelessWidget {
  const AmountPad({
    super.key,
    required this.controller,
    required this.currency,
    this.onSave,
    this.onSaveAnother,
    this.saving = false,
    this.leading,
    this.toolbar,
  });
  final TextEditingController controller;
  final String currency;
  final VoidCallback? onSave, onSaveAnother;
  final bool saving;
  final Widget? leading, toolbar;
  void keyPress(BuildContext context, String key) {
    var text = controller.text;
    if (key == 'C') {
      text = '';
    } else if (key == '⌫') {
      if (text.isNotEmpty) text = text.substring(0, text.length - 1);
    } else if (key == '=') {
      try {
        text = decimalMoney(calculateMinor(text, currency), currency);
      } on FormatException catch (e) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
    } else if (text.length < 120) {
      if (key == '.' &&
          (text.isEmpty || '+-×÷'.contains(text[text.length - 1]))) {
        text += '0.';
      } else if ('+-×÷'.contains(key) &&
          text.isNotEmpty &&
          '+-×÷'.contains(text[text.length - 1])) {
        text = text.substring(0, text.length - 1) + key;
      } else {
        text += key;
      }
    }
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Widget button(
    BuildContext context,
    String key, {
    VoidCallback? action,
    bool primary = false,
  }) => Expanded(
    child: Padding(
      padding: const EdgeInsets.all(2),
      child: TextButton(
        onPressed: saving || ((key == '保存' || key == '再记') && action == null)
            ? null
            : action ?? () => keyPress(context, key),
        onLongPress: !saving && key == '⌫'
            ? () => keyPress(context, 'C')
            : null,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 0),
          minimumSize: const Size(0, 48),
          foregroundColor: primary
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurface,
          backgroundColor: primary
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: key == '⌫'
            ? const Tooltip(
                message: '退格（长按清空）',
                triggerMode: TooltipTriggerMode.manual,
                child: Icon(Icons.backspace_outlined),
              )
            : Text(
                key,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: primary
                      ? Theme.of(context).colorScheme.onPrimary
                      : null,
                ),
              ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          if (leading != null) Expanded(flex: 2, child: leading!),
          Expanded(
            flex: 3,
            child: Semantics(
              label: '金额',
              child: TextField(
                key: const ValueKey('entry-amount'),
                controller: controller,
                readOnly: true,
                showCursor: true,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.headlineSmall,
                decoration: InputDecoration(
                  hintText: '0.00',
                  suffixIcon: IconButton(
                    tooltip: '计算结果',
                    onPressed: saving ? null : () => keyPress(context, '='),
                    icon: const Text('='),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ?toolbar,
      for (final row in [
        ['1', '2', '3', '⌫'],
        ['4', '5', '6', '+-'],
        ['7', '8', '9', '×÷'],
        ['再记', '0', '.', '保存'],
      ])
        Row(
          children: [
            for (final key in row)
              if (key == '+-' || key == '×÷')
                Expanded(
                  child: Row(
                    children: [
                      for (final operator in key.split(''))
                        button(context, operator),
                    ],
                  ),
                )
              else
                button(
                  context,
                  key,
                  primary: key == '保存',
                  action: key == '保存'
                      ? onSave
                      : key == '再记'
                      ? onSaveAnother
                      : null,
                ),
          ],
        ),
    ],
  );
}
