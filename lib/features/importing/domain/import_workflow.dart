import '../../../data/database/app_database.dart';
import 'import_plan.dart';
import 'import_table.dart';

enum ImportStage { select, columns, accounts, preview, commit, completed }

/// Feature-local workflow; parsing remains in the background file reader.
class ImportWorkflow {
  ImportWorkflow([List<ImportTable> initial = const []]) {
    if (initial.isNotEmpty) load(initial);
  }
  List<ImportTable> tables = [];
  int sheet = 0, setupStep = 0;
  final mapping = IncomeExpenseImportMapping();
  List<ImportResult>? results;
  final selected = <int>{}, importedAccountIds = <String>{};
  int? imported;
  bool committing = false;

  ImportStage get stage => committing
      ? ImportStage.commit
      : imported != null
      ? ImportStage.completed
      : tables.isEmpty
      ? ImportStage.select
      : results != null
      ? ImportStage.preview
      : setupStep == 0
      ? ImportStage.columns
      : ImportStage.accounts;

  void load(List<ImportTable> value) {
    if (value.isEmpty) throw const FormatException('文件没有可导入的工作表');
    tables = value;
    sheet = setupStep = 0;
    mapping.detect(value.first);
    results = null;
    imported = null;
    selected.clear();
    importedAccountIds.clear();
  }

  void showPreview(List<ImportResult> value) {
    results = value;
    selected
      ..clear()
      ..addAll(value.where((r) => r.entry != null).map((r) => r.row));
  }

  void back() {
    if (committing) return;
    if (results != null) {
      results = null;
      selected.clear();
    } else {
      setupStep = 0;
    }
  }

  Future<void> commit(AppDatabase db) async {
    if (committing || imported != null || selected.isEmpty || results == null) {
      return;
    }
    final chosen = results!
        .where((r) => selected.contains(r.row) && r.entry != null)
        .map((r) => r.entry!)
        .toList();
    if (chosen.isEmpty) return;
    committing = true;
    try {
      final count = await commitIncomeExpenseImport(db, chosen);
      imported = count;
      importedAccountIds.addAll(chosen.map((e) => e.accountId));
    } finally {
      // A failure leaves the selection and preview available for retry.
      committing = false;
    }
  }
}
