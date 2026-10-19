import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_media_backup.dart';
import 'sync_metadata.dart';

/// Port of `STORAGE_KEYS` in `src/utils/dataManager.ts`.
class StorageKeys {
  static const propertyManager = 'propertyManager';
  static const tenants = 'tenants';
  static const payments = 'payments';
  static const expenses = 'expenses';
  static const workOrders = 'workOrders';
  static const banks = 'banks';
  static const zakat = 'zakat';
  static const documents = 'documents';
  static const documentGroups = 'documentGroups';
  static const reports = 'reports';
  static const preferences = 'preferences';
  static const selectedCurrency = 'selectedCurrency';
  static const selectedYear = 'selectedYear';
  static const monthlyNotes = 'monthlyNotes';
  static const bankDeposits = 'bankDeposits';
  static const expenseCategories = 'expenseCategories';
  static const documentCategories = 'documentCategories';
  static const predefinedDescriptions = 'predefinedDescriptions';
  static const recentlyDeletedDocs = 'recentlyDeletedDocs';
  static const zakatCategories = 'zakatCategories';
  static const onboardingCompleted = 'onboardingCompleted';
  static const appVersion = 'appVersion';
  static const deletedRecordIds = 'deletedRecordIds';
  static const properties = 'properties';
  static const selectedPropertyId = 'selectedPropertyId';

  static const all = [
    properties,
    selectedPropertyId,
    propertyManager,
    tenants,
    payments,
    expenses,
    workOrders,
    banks,
    zakat,
    documents,
    documentGroups,
    reports,
    preferences,
    selectedCurrency,
    selectedYear,
    monthlyNotes,
    bankDeposits,
    expenseCategories,
    documentCategories,
    predefinedDescriptions,
    recentlyDeletedDocs,
    zakatCategories,
    onboardingCompleted,
    appVersion,
    deletedRecordIds,
  ];
}

class AppStorage {
  static late Box _box;
  static bool _ready = false;

  static bool get isReady => _ready;

  static Future<void> init() async {
    await Hive.initFlutter();
    if (Hive.isBoxOpen('rentmanager')) {
      _box = Hive.box('rentmanager');
      _ready = true;
      return;
    }
    try {
      _box = await Hive.openBox('rentmanager', crashRecovery: true);
    } catch (e) {
      debugPrint(
        'AppStorage: Initial openBox failed ($e), retrying after short backoff...',
      );
      await Future.delayed(const Duration(milliseconds: 300));
      if (Hive.isBoxOpen('rentmanager')) {
        _box = Hive.box('rentmanager');
      } else {
        try {
          _box = await Hive.openBox('rentmanager', crashRecovery: true);
        } catch (err) {
          debugPrint(
            'AppStorage: Retry failed ($err), clearing lock if available.',
          );
          rethrow;
        }
      }
    }
    _ready = true;
  }

  /// Test/dev entry point that avoids path_provider (unavailable in unit tests).
  static Future<void> initWithPath(String path) async {
    Hive.init(path);
    if (Hive.isBoxOpen('rentmanager')) {
      _box = Hive.box('rentmanager');
    } else {
      _box = await Hive.openBox('rentmanager', crashRecovery: true);
    }
    _ready = true;
  }

  static Future<void> close() async {
    await Hive.close();
    _ready = false;
  }

  static T? readJson<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    if (!_ready) return null;
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      final map = raw is Map
          ? Map<String, dynamic>.from(raw)
          : Map<String, dynamic>.from(jsonDecode(raw as String));
      return fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static List<T> readList<T>(
    String key,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (!_ready) return [];
    final raw = _box.get(key);
    if (raw == null) return [];
    try {
      final list = raw is List ? raw : (jsonDecode(raw as String) as List);
      // duplicate-ID guard (mirrors dataManager duplicate guard)
      final seen = <String>{};
      final out = <T>[];
      for (final e in list) {
        try {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          final id = m['id']?.toString().trim() ?? '';
          // Per-element isolation: one corrupt record is skipped instead of
          // dropping the entire collection (which the following persist pass
          // would then write back over the good data).
          if (id.isEmpty) {
            // Legacy records without ids must all be preserved rather than
            // collapsing into a single "null" key.
            out.add(fromJson(m));
            continue;
          }
          if (!seen.contains(id)) {
            final parsed = fromJson(m);
            seen.add(id);
            out.add(parsed);
          }
        } catch (_) {
          debugPrint('AppStorage: skipped corrupt element in "$key"');
        }
      }
      return out;
    } catch (e) {
      debugPrint('AppStorage: failed to read "$key": $e');
      return [];
    }
  }

  static Future<void> writeJson(String key, Map<String, dynamic> value) =>
      _box.put(key, jsonEncode(value));

  static Future<void> writeList(String key, List<Map<String, dynamic>> value) =>
      _box.put(key, jsonEncode(value));

  static Future<void> writeString(String key, String value) =>
      _box.put(key, value);
  static String? readString(String key) => _box.get(key) as String?;

  static Future<void> delete(String key) => _box.delete(key);
  static Future<void> clearAll() => _box.clear();

  /// Retrieves deletion tombstones with the time each record was deleted.
  /// Legacy list-shaped tombstones are assigned [legacyTime] (or now).
  static Map<String, DateTime> getDeletedTombstones({DateTime? legacyTime}) {
    if (!_ready) return <String, DateTime>{};
    final raw = _box.get(StorageKeys.deletedRecordIds);
    return parseTombstones(raw, legacyTime: legacyTime);
  }

  /// Retrieves the set of IDs of deleted entities.
  static Set<String> getDeletedIds({DateTime? legacyTime}) =>
      getDeletedTombstones(legacyTime: legacyTime).keys.toSet();

  /// Records a record ID as deleted so cross-device sync removes it everywhere.
  static Future<void> trackDeletedId(String id) => trackDeletedIds([id]);

  /// Records multiple record IDs as deleted.
  static Future<void> trackDeletedIds(Iterable<String> ids) async {
    if (!_ready) return;
    final valid = ids.where((e) => e.isNotEmpty).toList();
    if (valid.isEmpty) return;
    final tombstones = getDeletedTombstones();
    final now = DateTime.now();
    for (final id in valid) {
      tombstones[id] = now;
    }
    pruneTombstones(tombstones, now: now);
    await _box.put(
      StorageKeys.deletedRecordIds,
      jsonEncode(encodeTombstones(tombstones)),
    );
  }

  /// Removes explicit restore overrides from the deleted-record tombstones so
  /// records the user restored on purpose stop being filtered by future merges.
  static Future<void> clearDeletedIds(Iterable<String> ids) async {
    if (!_ready) return;
    final valid = ids.where((e) => e.isNotEmpty).toList();
    if (valid.isEmpty) return;
    final tombstones = getDeletedTombstones()
      ..removeWhere((id, _) => valid.contains(id));
    await _box.put(
      StorageKeys.deletedRecordIds,
      jsonEncode(encodeTombstones(tombstones)),
    );
  }

  /// Exports all application data into a clean, structured JSON-serializable Map.
  /// If [includeMedia] is true (default), all local media files (avatars, receipts, documents)
  /// are bundled into a portable base64 media dictionary.
  static Future<Map<String, dynamic>> exportAll({
    bool includeMedia = true,
  }) async {
    final map = <String, dynamic>{};
    for (final k in StorageKeys.all) {
      final raw = _box.get(k);
      if (raw == null) continue;
      if (raw is String) {
        try {
          map[k] = jsonDecode(raw);
        } catch (_) {
          map[k] = raw;
        }
      } else {
        map[k] = raw;
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      map['__prefs__'] = {for (final k in prefs.getKeys()) k: prefs.get(k)};
    } catch (_) {}

    map['__exportedAt'] = DateTime.now().toUtc().toIso8601String();

    if (includeMedia) {
      try {
        return await AppMediaBackup.packMedia(map);
      } catch (e) {
        // Fall back gracefully to plain data map if media pack has any issue
        return map;
      }
    }

    return map;
  }

  /// Imports and persists a backup Map, handling type-safe preference restoration,
  /// automatic media file extraction and remapping, and supporting both parsed objects
  /// and serialized strings.
  static Future<void> importAll(Map<String, dynamic> rawMap) async {
    Map<String, dynamic> map = rawMap;
    try {
      // Unpack all embedded media files into persistent local storage and rewrite paths
      map = await AppMediaBackup.unpackMedia(rawMap);
    } catch (_) {}

    if (map['__prefs__'] != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final rawPrefs = map['__prefs__'];
        if (rawPrefs is Map) {
          for (final entry in rawPrefs.entries) {
            final k = entry.key.toString();
            final v = entry.value;
            if (v is bool) {
              await prefs.setBool(k, v);
            } else if (v is int) {
              await prefs.setInt(k, v);
            } else if (v is double) {
              await prefs.setDouble(k, v);
            } else if (v is List) {
              await prefs.setStringList(k, v.map((e) => e.toString()).toList());
            } else if (v != null) {
              await prefs.setString(k, v.toString());
            }
          }
        }
      } catch (_) {}
    }

    // Tombstone handling: deletions must never be undone by an import, but a
    // record edited after its deletion time is an intentional resurrection.
    final tombstones = getDeletedTombstones();
    final incomingTombstones = parseTombstones(
      map[StorageKeys.deletedRecordIds],
    );
    for (final entry in incomingTombstones.entries) {
      final existing = tombstones[entry.key];
      if (existing == null || entry.value.isAfter(existing)) {
        tombstones[entry.key] = entry.value;
      }
    }
    pruneTombstones(tombstones);

    dynamic decodeRecord(dynamic value) {
      if (value is Map) return value;
      if (value is String) {
        try {
          return jsonDecode(value);
        } catch (_) {
          return value;
        }
      }
      return value;
    }

    /// Returns true when the record must stay deleted. A record whose own
    /// timestamp is newer than its tombstone resurrects the id.
    bool isStillDeleted(dynamic value) {
      final record = decodeRecord(value);
      final id = record is Map ? '${record['id']}'.trim() : '';
      if (id.isEmpty) return false;
      final deletedAt = tombstones[id];
      if (deletedAt == null) return false;
      final updatedAt = recordUpdatedAt(record);
      if (updatedAt != null && updatedAt.isAfter(deletedAt)) {
        tombstones.remove(id);
        return false;
      }
      return true;
    }

    // A restore replaces the dataset. Remove local entity collections that the
    // backup does not contain so stale records cannot survive the restore.
    const replaceKeys = <String>[
      StorageKeys.properties,
      StorageKeys.propertyManager,
      StorageKeys.tenants,
      StorageKeys.payments,
      StorageKeys.expenses,
      StorageKeys.workOrders,
      StorageKeys.banks,
      StorageKeys.zakat,
      StorageKeys.documents,
      StorageKeys.documentGroups,
      StorageKeys.monthlyNotes,
      StorageKeys.bankDeposits,
      StorageKeys.expenseCategories,
      StorageKeys.documentCategories,
      StorageKeys.zakatCategories,
      StorageKeys.recentlyDeletedDocs,
      StorageKeys.predefinedDescriptions,
    ];
    for (final k in replaceKeys) {
      if (!map.containsKey(k)) await _box.delete(k);
    }

    for (final k in StorageKeys.all) {
      if (k == StorageKeys.deletedRecordIds) continue;
      final v = map[k];
      if (v == null) continue;
      if (v is List) {
        var listOut = v;
        if (tombstones.isNotEmpty) {
          try {
            listOut = v.where((e) => !isStillDeleted(e)).toList();
          } catch (_) {
            listOut = v;
          }
        }
        await _box.put(k, jsonEncode(listOut));
      } else if (v is String) {
        // String-stored list data also filters by tombstones when parseable.
        if (tombstones.isNotEmpty && !k.contains('__')) {
          try {
            final decoded = jsonDecode(v);
            if (decoded is List) {
              final filtered = decoded
                  .where((e) => !isStillDeleted(e))
                  .toList();
              if (filtered.length != decoded.length) {
                await _box.put(k, jsonEncode(filtered));
                continue;
              }
            }
          } catch (_) {}
        }
        await _box.put(k, v);
      } else {
        await _box.put(k, jsonEncode(v));
      }
    }

    // Persist the union of local and imported tombstones (minus resurrections).
    await _box.put(
      StorageKeys.deletedRecordIds,
      jsonEncode(encodeTombstones(tombstones)),
    );
  }
}
