import '../../../core/time/business_date.dart';

const itemCategories = ['数码产品', '日用品', '化妆品', '食物', '家具', '衣物', '其他'];
int usageDays(String purchasedOn, String? archivedOn, DateTime now) =>
    ownershipDays(
      purchasedOn,
      archivedOn == null ? now : parseDate(archivedOn),
    );
double? dailyCost(
  int? price,
  String? purchasedOn,
  String? archivedOn,
  DateTime now,
) => price == null || purchasedOn == null
    ? null
    : price / usageDays(purchasedOn, archivedOn, now);
