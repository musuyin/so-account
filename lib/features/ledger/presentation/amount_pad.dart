import 'package:flutter/material.dart';

import '../../../core/money/calculator.dart';
import '../../../core/money/money.dart';

class AmountPad extends StatelessWidget {
  const AmountPad({
    super.key,
    required this.controller,
    required this.currency,
  });
  final TextEditingController controller;
  final String currency;
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
      text += key;
    }
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextField(
        controller: controller,
        readOnly: true,
        showCursor: true,
        style: Theme.of(context).textTheme.headlineSmall,
        decoration: InputDecoration(
          labelText: '金额 · $currency',
          hintText: '0.00',
          suffixIcon: IconButton(
            tooltip: '退格',
            onPressed: () => keyPress(context, '⌫'),
            icon: const Icon(Icons.backspace_outlined),
          ),
        ),
      ),
      const SizedBox(height: 8),
      for (final row in [
        ['7', '8', '9', '÷'],
        ['4', '5', '6', '×'],
        ['1', '2', '3', '-'],
        ['C', '0', '.', '+'],
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              for (final key in row)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () => keyPress(context, key),
                      child: Text(key),
                    ),
                  ),
                ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => keyPress(context, '='),
          child: const Text('= 计算结果'),
        ),
      ),
    ],
  );
}
