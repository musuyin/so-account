import 'database/app_database.dart';

class AppSnapshot {
  const AppSnapshot(
    this.accounts,
    this.categories,
    this.entries,
    this.budgets,
    this.items,
    this.links,
    this.preferences, [
    this.adjustments = const [],
    this.goals = const [],
    this.contributions = const [],
  ]);
  final List<Account> accounts;
  final List<Category> categories;
  final List<Entry> entries;
  final List<Budget> budgets;
  final List<Item> items;
  final List<PurchaseLink> links;
  final List<Preference> preferences;
  final List<BalanceAdjustment> adjustments;
  final List<WishGoal> goals;
  final List<GoalContribution> contributions;
  List<Account> get activeAccounts =>
      accounts.where((a) => !a.isArchived).toList();
  bool hasArchivedAccount(Entry entry) => accounts.any(
    (a) =>
        a.isArchived &&
        [
          entry.accountId,
          entry.targetAccountId,
          entry.debtAccountId,
        ].contains(a.id),
  );
  Account account(String id) => accounts.firstWhere((a) => a.id == id);
  String category(String? id) =>
      categories.where((c) => c.id == id).firstOrNull?.name ?? '往来';
  String preference(String key, String fallback) =>
      preferences.where((p) => p.key == key).firstOrNull?.value ?? fallback;
}
