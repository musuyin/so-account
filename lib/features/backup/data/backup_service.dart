import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

import '../../../data/database/app_database.dart';
import '../../../core/appearance.dart';
import '../../../platform/media/media_store.dart';
import '../../inventory/data/inventory_repository.dart';
import '../../inventory/domain/item_categories.dart';
import '../../ledger/data/ledger_repository.dart';
import '../../ledger/domain/entry_kind.dart';
import '../domain/backup_codec.dart';

// Isolate closures are created outside the service so their captured context
// never contains the live SQLite connection.
Future<Uint8List> _encode(Map<String, Uint8List> files) =>
    Isolate.run(() => encodeBackup(files));
Future<Map<String, Uint8List>> _decode(Uint8List bytes) =>
    Isolate.run(() => decodeBackup(bytes));

class BackupService {
  BackupService(this.db, this.media);
  final AppDatabase db;
  final MediaStore media;

  Future<Uint8List> export() async {
    final files = await db.transaction(() async {
      final snapshot = await _Snapshot.read(db);
      final result = <String, Uint8List>{
        'data.json': Uint8List.fromList(
          utf8.encode(jsonEncode(snapshot.toJson())),
        ),
      };
      var total = result['data.json']!.length;
      for (final photo
          in snapshot.items.map((i) => i.photo).whereType<String>().toSet()) {
        final file = media.resolve(photo);
        if (!await file.exists()) {
          throw const FormatException('有物品照片缺失，请处理后再备份');
        }
        total += await file.length();
        if (total > maxExpandedBytes) {
          throw const FormatException('备份超过 100 MB 上限');
        }
        result[photo] = await file.readAsBytes();
      }
      return result;
    });
    return _encode(files);
  }

  Future<void> restore(Uint8List bytes, {void Function()? beforeCommit}) async {
    final files = await _decode(bytes);
    late _Snapshot snapshot;
    final stage = AppDatabase(NativeDatabase.memory());
    try {
      snapshot = _Snapshot.fromJson(
        jsonDecode(utf8.decode(files['data.json']!)) as Map<String, dynamic>,
      );
      await _replace(stage, snapshot);
      final ledger = LedgerRepository(stage);
      for (final a in snapshot.accounts) {
        if (a.openingBalance.abs() > 999999999999) {
          throw const FormatException('账户余额超出上限');
        }
        await ledger.saveAccount(
          id: a.id,
          name: a.name,
          kind: a.kind,
          channel: a.channel,
          currency: a.currency,
          openingBalance: a.openingBalance,
          avatar: a.avatar,
        );
      }
      for (final c in snapshot.categories) {
        await ledger.saveCategory(c.name, c.kind, id: c.id);
      }
      for (final e in snapshot.entries) {
        await ledger.saveEntry(
          id: e.id,
          kind: EntryKind.values.byName(e.kind),
          amount: e.amount,
          accountId: e.accountId,
          targetAccountId: e.targetAccountId,
          categoryId: e.categoryId,
          debtId: e.debtId,
          counterparty: e.counterparty,
          date: e.date,
          note: e.note,
        );
      }
      for (final b in snapshot.budgets) {
        await ledger.setBudget(b.month, b.currency, b.amount);
      }
      final inventory = InventoryRepository(stage);
      for (final item in snapshot.items) {
        if (item.photo != null && !files.containsKey(item.photo)) {
          throw const FormatException('备份缺少物品图片');
        }
        await inventory.save(
          id: item.id,
          name: item.name,
          category: item.category,
          currency: item.currency,
          price: item.price,
          purchasedOn: item.purchasedOn,
          note: item.note,
          photo: item.photo,
          useType: item.useType,
          status: item.status,
          archivedOn: item.archivedOn,
          quantity: item.quantity,
          unit: item.unit,
          entryIds: snapshot.links
              .where((l) => l.itemId == item.id)
              .map((l) => l.entryId)
              .toList(),
        );
      }
      for (final pref in snapshot.preferences) {
        if (pref.key == 'item_categories') {
          validateItemCategories(pref.value);
          continue;
        }
        if (!validAppearancePreference(pref.key, pref.value)) {
          throw const FormatException('不支持的偏好设置');
        }
      }
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('备份数据不符合业务规则');
    } finally {
      await stage.close();
    }

    // Publish immutable photos before the SQLite transaction. A crash can only
    // leave unreferenced files; it cannot leave committed rows pointing at missing files.
    final published = <File>[];
    try {
      final remap = <String, String>{};
      for (final photo
          in snapshot.items.map((i) => i.photo).whereType<String>().toSet()) {
        final ext = photo.split('.').last;
        final next = 'media/${const Uuid().v4()}.$ext';
        final target = media.resolve(next);
        await target.parent.create(recursive: true);
        published.add(target);
        await target.writeAsBytes(files[photo]!, flush: true);
        remap[photo] = next;
      }
      snapshot = snapshot.withPhotos(remap);
      await db.transaction(() async {
        await _replace(db, snapshot);
        beforeCommit?.call();
      });
    } catch (_) {
      for (final file in published) {
        try {
          await file.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  static Future<void> _replace(AppDatabase db, _Snapshot data) =>
      db.transaction(() async {
        await db.delete(db.purchaseLinks).go();
        await db.delete(db.items).go();
        await db.delete(db.entries).go();
        await db.delete(db.accounts).go();
        await db.delete(db.categories).go();
        await db.delete(db.budgets).go();
        await db.delete(db.preferences).go();
        for (final row in data.accounts) {
          await db.into(db.accounts).insert(row);
        }
        for (final row in data.categories) {
          await db.into(db.categories).insert(row);
        }
        for (final row in data.entries.where((e) => e.debtId == null)) {
          await db.into(db.entries).insert(row);
        }
        for (final row in data.entries.where((e) => e.debtId != null)) {
          await db.into(db.entries).insert(row);
        }
        for (final row in data.budgets) {
          await db.into(db.budgets).insert(row);
        }
        for (final row in data.items) {
          await db.into(db.items).insert(row);
        }
        for (final row in data.links) {
          await db.into(db.purchaseLinks).insert(row);
        }
        for (final row in data.preferences) {
          await db.into(db.preferences).insert(row);
        }
      });
}

class _Snapshot {
  _Snapshot(
    this.accounts,
    this.categories,
    this.entries,
    this.budgets,
    this.items,
    this.links,
    this.preferences,
  );
  final List<Account> accounts;
  final List<Category> categories;
  final List<Entry> entries;
  final List<Budget> budgets;
  final List<Item> items;
  final List<PurchaseLink> links;
  final List<Preference> preferences;
  static Future<_Snapshot> read(AppDatabase db) async => _Snapshot(
    await db.select(db.accounts).get(),
    await db.select(db.categories).get(),
    await db.select(db.entries).get(),
    await db.select(db.budgets).get(),
    await db.select(db.items).get(),
    await db.select(db.purchaseLinks).get(),
    await db.select(db.preferences).get(),
  );
  Map<String, Object?> toJson() => {
    'accounts': accounts.map((r) => r.toJson()).toList(),
    'categories': categories.map((r) => r.toJson()).toList(),
    'entries': entries.map((r) => r.toJson()).toList(),
    'budgets': budgets.map((r) => r.toJson()).toList(),
    'items': items.map((r) => r.toJson()).toList(),
    'links': links.map((r) => r.toJson()).toList(),
    'preferences': preferences.map((r) => r.toJson()).toList(),
  };
  factory _Snapshot.fromJson(Map<String, dynamic> json) {
    List<T> rows<T>(String key, T Function(Map<String, dynamic>) decode) {
      final list = json[key] as List;
      if (list.length > 100000) throw const FormatException('记录数量超过限制');
      return list.map((r) => decode(r as Map<String, dynamic>)).toList();
    }

    return _Snapshot(
      rows('accounts', (r) => Account.fromJson({'avatar': '', ...r})),
      rows('categories', Category.fromJson),
      rows('entries', (r) => Entry.fromJson({'counterparty': '', ...r})),
      rows('budgets', Budget.fromJson),
      rows(
        'items',
        (r) => Item.fromJson({
          'useType': 'durable',
          'archivedOn': null,
          'quantity': null,
          'unit': null,
          ...r,
          'status': ['retired', 'depleted'].contains(r['status'])
              ? 'completed'
              : (r['status'] ?? 'active'),
        }),
      ),
      rows('links', PurchaseLink.fromJson),
      rows('preferences', Preference.fromJson),
    );
  }
  _Snapshot withPhotos(Map<String, String> remap) => _Snapshot(
    accounts,
    categories,
    entries,
    budgets,
    items
        .map(
          (i) =>
              i.copyWith(photo: Value(i.photo == null ? null : remap[i.photo])),
        )
        .toList(),
    links,
    preferences,
  );
}
