import 'dart:convert';

import '../core/models/models.dart';
import '../core/storage/app_storage.dart';
import '../core/storage/sync_metadata.dart';
import 'auto_deduplication_service.dart';

/// Result of 2-way entity data merge.
class DataMergeResult {
  final Map<String, dynamic> mergedData;
  final bool hasRemoteNewerData;
  final bool hasLocalNewerData;
  final Set<String> mergedDeletedIds;

  const DataMergeResult({
    required this.mergedData,
    required this.hasRemoteNewerData,
    required this.hasLocalNewerData,
    required this.mergedDeletedIds,
  });
}

/// Service that performs intelligent 2-way Last-Write-Wins (LWW) entity reconciliation
/// between local storage data and remote Google Drive backup snapshots.
/// Prevents cross-device data overwrite without requiring manual restore.
class DataMergeService {
  DataMergeService._();

  static const List<String> _listEntityKeys = [
    StorageKeys.properties,
    StorageKeys.tenants,
    StorageKeys.payments,
    StorageKeys.expenses,
    StorageKeys.workOrders,
    StorageKeys.banks,
    StorageKeys.bankDeposits,
    StorageKeys.documents,
    StorageKeys.documentGroups,
    StorageKeys.zakat,
    StorageKeys.monthlyNotes,
    StorageKeys.expenseCategories,
    StorageKeys.documentCategories,
    StorageKeys.zakatCategories,
    StorageKeys.recentlyDeletedDocs,
  ];

  /// Merges local application data and incoming remote data map.
  ///
  /// [remoteSnapshotTime] is the backup file's modified time. It is used to
  /// date legacy (timestamp-less) tombstones in older backups.
  static DataMergeResult merge({
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
    Set<String>? localDeletedIds,
    DateTime? remoteSnapshotTime,
  }) {
    bool hasRemoteNewer = false;
    bool hasLocalNewer = false;
    final merged = <String, dynamic>{};

    // 1. Reconcile deletion tombstones from local and remote. The newest
    // deletion timestamp wins; records edited afterwards are resurrected.
    final tombstones = <String, DateTime>{...AppStorage.getDeletedTombstones()};
    if (localDeletedIds != null) {
      for (final id in localDeletedIds) {
        tombstones.putIfAbsent(
          id,
          () => DateTime.fromMillisecondsSinceEpoch(0),
        );
      }
    }
    final remoteTombstones = parseTombstones(
      remote[StorageKeys.deletedRecordIds],
      legacyTime: remoteSnapshotTime,
    );
    final localTombstoneKeys = tombstones.keys.toSet();
    for (final entry in remoteTombstones.entries) {
      final existing = tombstones[entry.key];
      if (existing == null) {
        tombstones[entry.key] = entry.value;
        hasRemoteNewer = true;
      } else if (entry.value.isAfter(existing)) {
        tombstones[entry.key] = entry.value;
        hasRemoteNewer = true;
      }
    }
    if (localTombstoneKeys
        .difference(remoteTombstones.keys.toSet())
        .isNotEmpty) {
      hasLocalNewer = true;
    }

    // 2. Merge entity lists by ID + timestamp
    for (final key in _listEntityKeys) {
      final res = _mergeEntityList(local[key], remote[key], tombstones);
      merged[key] = res.list;
      if (res.hasRemoteNewer) hasRemoteNewer = true;
      if (res.hasLocalNewer) hasLocalNewer = true;
    }

    // 2.1 Auto-deduplicate merged payments and expenses silently
    final mergedPaymentsRaw = merged[StorageKeys.payments];
    final mergedExpensesRaw = merged[StorageKeys.expenses];
    final mergedTenantsRaw = merged[StorageKeys.tenants];

    final mergedDocumentsRaw = merged[StorageKeys.documents];
    if (mergedPaymentsRaw is List ||
        mergedExpensesRaw is List ||
        mergedDocumentsRaw is List) {
      final tenantList = _toListOfMaps(mergedTenantsRaw)
          .map((m) => Tenant.fromJson(m))
          .toList();
      final tenantById = {for (final t in tenantList) t.id: t};
      final paymentsList = _toListOfMaps(mergedPaymentsRaw)
          .map((m) => Payment.fromJson(m))
          .toList();
      final expensesList = _toListOfMaps(mergedExpensesRaw)
          .map((m) => Expense.fromJson(m))
          .toList();
      final documentsList = _toListOfMaps(mergedDocumentsRaw)
          .map((m) => RentDoc.fromJson(m))
          .toList();

      final payReconciled = AutoDeduplicationService.reconcilePayments(
        paymentsList,
        tenantById: tenantById,
      );
      final expReconciled = AutoDeduplicationService.reconcileExpenses(
        expensesList,
      );
      final docReconciled = AutoDeduplicationService.reconcileDocuments(
        documentsList,
      );

      if (payReconciled.retiredIds.isNotEmpty ||
          expReconciled.retiredIds.isNotEmpty ||
          docReconciled.retiredIds.isNotEmpty) {
        final retiredAt = DateTime.now();
        for (final id in [
          ...payReconciled.retiredIds,
          ...expReconciled.retiredIds,
          ...docReconciled.retiredIds,
        ]) {
          tombstones[id] = retiredAt;
        }
        merged[StorageKeys.payments] = payReconciled.cleaned
            .map((p) => p.toJson())
            .toList();
        merged[StorageKeys.expenses] = expReconciled.cleaned
            .map((e) => e.toJson())
            .toList();
        merged[StorageKeys.documents] = docReconciled.cleaned
            .map((d) => d.toJson())
            .toList();
        hasLocalNewer = true;
      }
    }

    // 3. Property Manager (Single Object)
    final localPm = _toMap(local[StorageKeys.propertyManager]);
    final remotePm = _toMap(remote[StorageKeys.propertyManager]);
    if (localPm != null && remotePm == null) {
      merged[StorageKeys.propertyManager] = localPm;
      hasLocalNewer = true;
    } else if (remotePm != null && localPm == null) {
      merged[StorageKeys.propertyManager] = remotePm;
      hasRemoteNewer = true;
    } else if (localPm != null && remotePm != null) {
      final localTime = _extractTimestamp(localPm);
      final remoteTime = _extractTimestamp(remotePm);
      if (remoteTime != null &&
          (localTime == null || remoteTime.isAfter(localTime))) {
        merged[StorageKeys.propertyManager] = remotePm;
        hasRemoteNewer = true;
      } else if (localTime != null &&
          (remoteTime == null || localTime.isAfter(remoteTime))) {
        merged[StorageKeys.propertyManager] = localPm;
        hasLocalNewer = true;
      } else {
        merged[StorageKeys.propertyManager] = remotePm;
      }
    }

    // 4. Currency
    final localCurr = local[StorageKeys.selectedCurrency]?.toString();
    final remoteCurr = remote[StorageKeys.selectedCurrency]?.toString();
    if (remoteCurr != null &&
        remoteCurr.isNotEmpty &&
        (localCurr == null || localCurr == '\$')) {
      merged[StorageKeys.selectedCurrency] = remoteCurr;
      if (localCurr != remoteCurr) hasRemoteNewer = true;
    } else {
      merged[StorageKeys.selectedCurrency] = localCurr ?? remoteCurr ?? '\$';
    }

    // 5. Predefined Descriptions (Union of string lists)
    final localDescs = _toStringList(local[StorageKeys.predefinedDescriptions]);
    final remoteDescs = _toStringList(
      remote[StorageKeys.predefinedDescriptions],
    );
    final combinedDescs = {...localDescs, ...remoteDescs}.toList();
    merged[StorageKeys.predefinedDescriptions] = combinedDescs;
    if (remoteDescs.toSet().difference(localDescs.toSet()).isNotEmpty) {
      hasRemoteNewer = true;
    }
    if (localDescs.toSet().difference(remoteDescs.toSet()).isNotEmpty) {
      hasLocalNewer = true;
    }

    // 6. Onboarding state
    final localOnboard =
        local[StorageKeys.onboardingCompleted]?.toString() == 'true';
    final remoteOnboard =
        remote[StorageKeys.onboardingCompleted]?.toString() == 'true';
    merged[StorageKeys.onboardingCompleted] = (localOnboard || remoteOnboard)
        ? 'true'
        : 'false';

    // 7. Preferences (keep device-specific, merge cloud-friendly fields)
    final localPrefs =
        _toMap(local[StorageKeys.preferences]) ?? <String, dynamic>{};
    final remotePrefs =
        _toMap(remote[StorageKeys.preferences]) ?? <String, dynamic>{};
    final mergedPrefs = Map<String, dynamic>.from(localPrefs);

    if (remotePrefs.containsKey('showZakat') &&
        !localPrefs.containsKey('showZakat')) {
      mergedPrefs['showZakat'] = remotePrefs['showZakat'];
    }
    mergedPrefs['driveAutoSync'] =
        true; // Google account connected -> auto-sync active
    merged[StorageKeys.preferences] = mergedPrefs;

    // 7.1 Selected Property ID
    final localPropId = local[StorageKeys.selectedPropertyId]?.toString();
    final remotePropId = remote[StorageKeys.selectedPropertyId]?.toString();
    merged[StorageKeys.selectedPropertyId] =
        localPropId ?? remotePropId ?? 'all';

    // 8. Retain existing local SharedPreferences unless remote provides uninitialized keys
    if (local.containsKey('__prefs__')) {
      merged['__prefs__'] = local['__prefs__'];
    } else if (remote.containsKey('__prefs__')) {
      merged['__prefs__'] = remote['__prefs__'];
    }

    // 9. Carry forward unpacked media references
    if (remote.containsKey('__media__')) {
      merged['__media__'] = remote['__media__'];
    }

    pruneTombstones(tombstones);
    merged[StorageKeys.deletedRecordIds] = encodeTombstones(tombstones);

    return DataMergeResult(
      mergedData: merged,
      hasRemoteNewerData: hasRemoteNewer,
      hasLocalNewerData: hasLocalNewer,
      mergedDeletedIds: tombstones.keys.toSet(),
    );
  }

  static ({
    List<Map<String, dynamic>> list,
    bool hasRemoteNewer,
    bool hasLocalNewer,
  })
  _mergeEntityList(
    dynamic localRaw,
    dynamic remoteRaw,
    Map<String, DateTime> tombstones,
  ) {
    final localList = _toListOfMaps(localRaw);
    final remoteList = _toListOfMaps(remoteRaw);

    final localMap = <String, Map<String, dynamic>>{};
    for (final item in localList) {
      final id = '${item['id'] ?? ''}'.trim();
      if (id.isNotEmpty) localMap[id] = item;
    }

    final remoteMap = <String, Map<String, dynamic>>{};
    for (final item in remoteList) {
      final id = '${item['id'] ?? ''}'.trim();
      if (id.isNotEmpty) remoteMap[id] = item;
    }

    bool hasRemoteNewer = false;
    bool hasLocalNewer = false;
    final mergedList = <Map<String, dynamic>>[];

    final allIds = {...localMap.keys, ...remoteMap.keys};
    for (final id in allIds) {
      final localItem = localMap[id];
      final remoteItem = remoteMap[id];
      final localTime = localItem == null ? null : _extractTimestamp(localItem);
      final remoteTime = remoteItem == null
          ? null
          : _extractTimestamp(remoteItem);
      final deletedAt = tombstones[id];

      if (deletedAt != null) {
        final localRevives = localTime != null && localTime.isAfter(deletedAt);
        final remoteRevives =
            remoteTime != null && remoteTime.isAfter(deletedAt);
        if (!localRevives && !remoteRevives) continue;

        // A newer edit intentionally resurrects the record.
        tombstones.remove(id);
        if (localRevives && !remoteRevives) {
          mergedList.add(localItem!);
          hasLocalNewer = true;
          continue;
        }
        if (remoteRevives && !localRevives) {
          mergedList.add(remoteItem!);
          hasRemoteNewer = true;
          continue;
        }
      }

      if (localItem != null && remoteItem == null) {
        mergedList.add(localItem);
        hasLocalNewer = true;
      } else if (remoteItem != null && localItem == null) {
        mergedList.add(remoteItem);
        hasRemoteNewer = true;
      } else if (localItem != null && remoteItem != null) {
        if (remoteTime != null &&
            (localTime == null || remoteTime.isAfter(localTime))) {
          mergedList.add(remoteItem);
          hasRemoteNewer = true;
        } else if (localTime != null &&
            (remoteTime == null || localTime.isAfter(remoteTime))) {
          mergedList.add(localItem);
          hasLocalNewer = true;
        } else {
          if (!_mapsEqual(localItem, remoteItem)) {
            final localStatus = '${localItem['status'] ?? ''}'
                .toLowerCase()
                .trim();
            final remoteStatus = '${remoteItem['status'] ?? ''}'
                .toLowerCase()
                .trim();
            // If one is confirmed or paid and the other is pending, the completed status takes precedence
            if ((localStatus == 'confirmed' || localStatus == 'paid') &&
                (remoteStatus == 'pending' || remoteStatus.isEmpty)) {
              mergedList.add(localItem);
              hasLocalNewer = true;
            } else if ((remoteStatus == 'confirmed' ||
                    remoteStatus == 'paid') &&
                (localStatus == 'pending' || localStatus.isEmpty)) {
              mergedList.add(remoteItem);
              hasRemoteNewer = true;
            } else {
              // Prefer local modification so active user's edits are retained
              mergedList.add(localItem);
              hasLocalNewer = true;
            }
          } else {
            mergedList.add(localItem);
          }
        }
      }
    }

    return (
      list: mergedList,
      hasRemoteNewer: hasRemoteNewer,
      hasLocalNewer: hasLocalNewer,
    );
  }

  static DateTime? _extractTimestamp(Map<String, dynamic> item) =>
      recordUpdatedAt(item);

  static bool _mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if ('${a[key]}' != '${b[key]}') return false;
    }
    return true;
  }

  static List<Map<String, dynamic>> _toListOfMaps(dynamic raw) {
    if (raw == null) return [];
    try {
      final list = raw is List ? raw : (jsonDecode(raw as String) as List);
      return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic>? _toMap(dynamic raw) {
    if (raw == null) return null;
    try {
      if (raw is Map) return Map<String, dynamic>.from(raw);
      if (raw is String) {
        return Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (_) {}
    return null;
  }

  static List<String> _toStringList(dynamic raw) {
    if (raw == null) return [];
    try {
      if (raw is List) return raw.map((e) => e.toString()).toList();
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return [];
  }
}
