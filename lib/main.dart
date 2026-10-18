import 'package:flutter/material.dart';

import 'app/theme/app_theme.dart';

void main() => runApp(
  MaterialApp(
    title: '拾账',
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    home: const Scaffold(body: Center(child: Text('拾账'))),
  ),
);
