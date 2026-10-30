import 'dart:convert';
import 'dart:io';

import 'package:so_account/features/importing/domain/import_template.dart';

void main() => stdout.write(jsonEncode(importTemplateRows()));
