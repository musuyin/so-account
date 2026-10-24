/// A single new item explicitly added while saving an expense.
class NewPurchaseItem {
  const NewPurchaseItem({
    required this.name,
    required this.category,
    this.useType = 'durable',
    this.price,
    this.quantity,
    this.unit,
  });

  final String name, category, useType;
  final int? price;
  final String? quantity, unit;
}
