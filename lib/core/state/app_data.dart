import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/auto_deduplication_service.dart';
import '../../services/drive_backup_service.dart';
import '../../services/notification_service.dart';
import '../models/models.dart';
import '../storage/app_media_backup.dart';
import '../storage/app_storage.dart';

/// Keeps the auto-created/default property in sync with the manager profile.
///
/// The setup wizard stores the property name/address on [PropertyManager]
/// before any explicit [Property] exists. This helper creates the default
/// property from that profile, or renames an existing auto-created one, so
/// desktop/mobile headers show the real property name instead of
/// "Primary Property".
List<Property> _syncPropertiesWithManager(
  List<Property> properties,
  PropertyManager? pm,
  List<Tenant> tenants,
) {
  if (pm == null) return properties;
  final name = (pm.propertyName ?? '').trim();
  final address = pm.address.trim();

  if (properties.isEmpty) {
    if (name.isEmpty && address.isEmpty) return properties;
    final managerName = pm.name.trim();
    return [
      Property(
        id: 'prop-default',
        name: name.isNotEmpty
            ? name
            : (managerName.isNotEmpty
                  ? '$managerName Property'
                  : 'Primary Property'),
        address: address,
        totalUnits: tenants.isNotEmpty ? tenants.length : 12,
        createdAt: DateTime.now(),
      ),
    ];
  }

  if (properties.length == 1) {
    final p = properties.first;
    final isAutoCreated =
        p.id == 'prop-default' ||
        p.name.trim().isEmpty ||
        p.name.trim() == 'Primary Property';
    if (isAutoCreated && (name.isNotEmpty || address.isNotEmpty)) {
      return [
        p.copyWith(
          name: name.isNotEmpty ? name : p.name,
          address: address.isNotEmpty ? address : p.address,
        ),
      ];
    }
  }
  return properties;
}

/// Port of `useOptimizedAppData` — critical-first load, debounced saves.
class AppDataState {
  final List<Property> properties;
  final String selectedPropertyId;
  final PropertyManager? propertyManager;
  final List<Tenant> tenants;
  final List<Payment> payments;
  final List<Expense> expenses;
  final List<WorkOrder> workOrders;
  final List<BankInfo> banks;
  final List<ZakatTransaction> zakat;
  final List<RentDoc> documents;
  final List<DocumentGroup> documentGroups;
  final List<ExpenseCategory> expenseCategories;
  final List<DocumentCategory> documentCategories;
  final List<ZakatCategory> zakatCategories;
  final List<MonthlyNote> monthlyNotes;
  final List<BankDeposit> bankDeposits;
  final List<String> predefinedDescriptions;
  final List<RentDoc> recentlyDeletedDocs;
  final AppPreferences preferences;
  final String selectedCurrency;
  final int selectedYear;
  final bool isLoading;
  final bool showSplash;
  final bool showOnboarding;

  const AppDataState({
    this.properties = const [],
    this.selectedPropertyId = 'all',
    this.propertyManager,
    this.tenants = const [],
    this.payments = const [],
    this.expenses = const [],
    this.workOrders = const [],
    this.banks = const [],
    this.zakat = const [],
    this.documents = const [],
    this.documentGroups = const [],
    this.expenseCategories = const [],
    this.documentCategories = const [],
    this.zakatCategories = const [],
    this.monthlyNotes = const [],
    this.bankDeposits = const [],
    this.predefinedDescriptions = const [],
    this.recentlyDeletedDocs = const [],
    required this.preferences,
    this.selectedCurrency = '\$',
    required this.selectedYear,
    this.isLoading = true,
    this.showSplash = true,
    this.showOnboarding = false,
  });

  bool get isAllProperties => false;

  String get effectivePropertyId {
    if (properties.isNotEmpty) {
      if (selectedPropertyId.isNotEmpty &&
          selectedPropertyId != 'all' &&
          properties.any((p) => p.id == selectedPropertyId)) {
        return selectedPropertyId;
      }
      return properties.first.id;
    }
    return (selectedPropertyId.isEmpty || selectedPropertyId == 'all')
        ? 'prop-default'
        : selectedPropertyId;
  }

  Property? get activeProperty {
    if (properties.isEmpty) return null;
    return properties.firstWhere(
      (p) => p.id == effectivePropertyId,
      orElse: () => properties.first,
    );
  }

  bool _matchesProperty(String? itemPropId) {
    if (properties.isEmpty) return true;
    final effId = effectivePropertyId;
    final normId =
        (itemPropId == null ||
            itemPropId.isEmpty ||
            itemPropId == 'prop-default')
        ? properties.first.id
        : itemPropId;
    return normId == effId;
  }

  /// tenant.id → normalized property id (legacy ''/'prop-default' → first property).
  Map<String, String> get _tenantPropertyMap {
    final firstId = properties.isNotEmpty
        ? properties.first.id
        : 'prop-default';
    return {
      for (final t in tenants)
        t.id: (t.propertyId.isEmpty || t.propertyId == 'prop-default')
            ? firstId
            : t.propertyId,
    };
  }

  String? _scopedOwnProperty(String? own, {String? tenantDerived}) {
    // Prefer the record's own explicit property assignment. A tenant may have
    // moved properties since an old payment/work order was created; falling
    // back to the tenant's current property would re-attribute history.
    if (own != null && own.isNotEmpty && own != 'prop-default') return own;
    if (tenantDerived != null) return tenantDerived;
    if (properties.isEmpty) return null;
    return properties.first.id;
  }

  List<Tenant> get scopedTenants =>
      tenants.where((t) => _matchesProperty(t.propertyId)).toList();

  List<Payment> get scopedPayments {
    final tenantProps = _tenantPropertyMap;
    return payments.where((p) {
      if (properties.isEmpty) return true;
      final own = _scopedOwnProperty(
        p.propertyId,
        tenantDerived: tenantProps[p.tenantId],
      );
      return own == effectivePropertyId;
    }).toList();
  }

  List<Expense> get scopedExpenses =>
      expenses.where((e) => _matchesProperty(e.propertyId)).toList();

  List<WorkOrder> get scopedWorkOrders {
    final tenantProps = _tenantPropertyMap;
    return workOrders.where((w) {
      if (properties.isEmpty) return true;
      final own = _scopedOwnProperty(
        w.propertyId,
        tenantDerived: w.tenantId == null ? null : tenantProps[w.tenantId!],
      );
      return own == effectivePropertyId;
    }).toList();
  }

  List<RentDoc> get scopedDocuments =>
      documents.where((d) => _matchesProperty(d.propertyId)).toList();

  List<BankDeposit> get scopedBankDeposits =>
      bankDeposits.where((d) => _matchesProperty(d.propertyId)).toList();

  List<MonthlyNote> get scopedMonthlyNotes =>
      monthlyNotes.where((n) => _matchesProperty(n.propertyId)).toList();

  List<ZakatTransaction> get scopedZakat =>
      zakat.where((z) => _matchesProperty(z.propertyId)).toList();

  AppDataState copyWith({
    List<Property>? properties,
    String? selectedPropertyId,
    PropertyManager? propertyManager,
    List<Tenant>? tenants,
    List<Payment>? payments,
    List<Expense>? expenses,
    List<WorkOrder>? workOrders,
    List<BankInfo>? banks,
    List<ZakatTransaction>? zakat,
    List<RentDoc>? documents,
    List<DocumentGroup>? documentGroups,
    List<ExpenseCategory>? expenseCategories,
    List<DocumentCategory>? documentCategories,
    List<ZakatCategory>? zakatCategories,
    List<MonthlyNote>? monthlyNotes,
    List<BankDeposit>? bankDeposits,
    List<String>? predefinedDescriptions,
    List<RentDoc>? recentlyDeletedDocs,
    AppPreferences? preferences,
    String? selectedCurrency,
    int? selectedYear,
    bool? isLoading,
    bool? showSplash,
    bool? showOnboarding,
    bool clearManager = false,
  }) => AppDataState(
    properties: properties ?? this.properties,
    selectedPropertyId: selectedPropertyId ?? this.selectedPropertyId,
    preferences: preferences ?? this.preferences,
    selectedYear: selectedYear ?? this.selectedYear,
    propertyManager: clearManager
        ? null
        : (propertyManager ?? this.propertyManager),
    tenants: tenants ?? this.tenants,
    payments: payments ?? this.payments,
    expenses: expenses ?? this.expenses,
    workOrders: workOrders ?? this.workOrders,
    banks: banks ?? this.banks,
    zakat: zakat ?? this.zakat,
    documents: documents ?? this.documents,
    documentGroups: documentGroups ?? this.documentGroups,
    expenseCategories: expenseCategories ?? this.expenseCategories,
    documentCategories: documentCategories ?? this.documentCategories,
    zakatCategories: zakatCategories ?? this.zakatCategories,
    monthlyNotes: monthlyNotes ?? this.monthlyNotes,
    bankDeposits: bankDeposits ?? this.bankDeposits,
    predefinedDescriptions:
        predefinedDescriptions ?? this.predefinedDescriptions,
    recentlyDeletedDocs: recentlyDeletedDocs ?? this.recentlyDeletedDocs,
    selectedCurrency: selectedCurrency ?? this.selectedCurrency,
    isLoading: isLoading ?? this.isLoading,
    showSplash: showSplash ?? this.showSplash,
    showOnboarding: showOnboarding ?? this.showOnboarding,
  );
}

class AppDataNotifier extends StateNotifier<AppDataState> {
  Timer? _saveTimer;
  final List<TenantSyncStatus> tenantSyncStatuses = [];
  AppDataNotifier()
    : super(
        AppDataState(
          preferences: AppPreferences(showZakat: true),
          selectedYear: DateTime.now().year,
        ),
      ) {
    loadTenantSyncStatuses();
  }

  /// Two-phase boot: critical (manager/tenants/prefs) then secondary in background.
  Future<void> loadAll() async {
    final pm = AppStorage.readJson(
      StorageKeys.propertyManager,
      PropertyManager.fromJson,
    );
    final tenants = AppStorage.readList(StorageKeys.tenants, Tenant.fromJson);
    final prefs = AppStorage.readJson(
      StorageKeys.preferences,
      AppPreferences.fromJson,
    );
    final currency = AppStorage.readString(StorageKeys.selectedCurrency);
    final savedYear = int.tryParse(
      AppStorage.readString(StorageKeys.selectedYear) ?? '',
    );
    final onboarded =
        AppStorage.readString(StorageKeys.onboardingCompleted) == 'true';
    final properties = AppStorage.readList(
      StorageKeys.properties,
      Property.fromJson,
    );
    final rawSelectedPropertyId = AppStorage.readString(
      StorageKeys.selectedPropertyId,
    );

    final effectiveProperties = _syncPropertiesWithManager(
      properties,
      pm,
      tenants,
    );

    final selectedPropertyId =
        (rawSelectedPropertyId != null &&
            rawSelectedPropertyId != 'all' &&
            effectiveProperties.any((p) => p.id == rawSelectedPropertyId))
        ? rawSelectedPropertyId
        : effectiveProperties.isEmpty
        ? 'all'
        : effectiveProperties.first.id;

    state = state.copyWith(
      properties: effectiveProperties,
      selectedPropertyId: selectedPropertyId,
      propertyManager: pm,
      tenants: tenants,
      preferences: prefs ?? AppPreferences(showZakat: true),
      selectedCurrency: currency ?? '\$',
      isLoading: false,
      selectedYear: savedYear ?? state.selectedYear,
      showOnboarding: !onboarded,
    );
    // Secondary phase. Await it so callers (onboarding restore, settings) see a
    // fully hydrated state and background reads cannot overwrite newer edits.
    await Future(() async {
      final expCats = AppStorage.readList(
        StorageKeys.expenseCategories,
        ExpenseCategory.fromJson,
      );
      final docCats = AppStorage.readList(
        StorageKeys.documentCategories,
        DocumentCategory.fromJson,
      );
      final zakCats = AppStorage.readList(
        StorageKeys.zakatCategories,
        ZakatCategory.fromJson,
      );
      List<String> descs;
      final rawDescs = AppStorage.readString(
        StorageKeys.predefinedDescriptions,
      );
      if (rawDescs != null && rawDescs.isNotEmpty) {
        try {
          descs = List<String>.from(jsonDecode(rawDescs) as List);
        } catch (_) {
          descs = DefaultData.predefinedDescriptions;
        }
      } else {
        descs = DefaultData.predefinedDescriptions;
      }
      final rawPayments = AppStorage.readList(
        StorageKeys.payments,
        Payment.fromJson,
      );
      final rawExpenses = AppStorage.readList(
        StorageKeys.expenses,
        Expense.fromJson,
      );
      final rawDocs = AppStorage.readList(
        StorageKeys.documents,
        RentDoc.fromJson,
      );
      final reconciled = await AutoDeduplicationService.reconcileAndPersist(
        payments: rawPayments,
        expenses: rawExpenses,
        documents: rawDocs,
        expenseCategories: expCats,
        tenantById: {for (final t in state.tenants) t.id: t},
      );
      state = state.copyWith(
        payments: reconciled.payments,
        expenses: reconciled.expenses,
        documents: reconciled.documents,
        workOrders: AppStorage.readList(
          StorageKeys.workOrders,
          WorkOrder.fromJson,
        ),
        banks: AppStorage.readList(StorageKeys.banks, BankInfo.fromJson),
        zakat: AppStorage.readList(
          StorageKeys.zakat,
          ZakatTransaction.fromJson,
        ),
        documentGroups: AppStorage.readList(
          StorageKeys.documentGroups,
          DocumentGroup.fromJson,
        ),
        expenseCategories: reconciled.expenseCategories.isEmpty
            ? DefaultData.expenseCategories()
            : reconciled.expenseCategories,
        documentCategories: DefaultData.normalizedDocumentCategories(docCats),
        zakatCategories: DefaultData.normalizedZakatCategories(zakCats),
        monthlyNotes: AppStorage.readList(
          StorageKeys.monthlyNotes,
          MonthlyNote.fromJson,
        ),
        bankDeposits: AppStorage.readList(
          StorageKeys.bankDeposits,
          BankDeposit.fromJson,
        ),
        recentlyDeletedDocs: AppStorage.readList(
          StorageKeys.recentlyDeletedDocs,
          RentDoc.fromJson,
        ),
        predefinedDescriptions: descs,
      );
    });
  }

  /// Immediately reloads all application state from persistent Hive storage.
  /// Used by background cloud sync to update the UI when new data arrives from
  /// Google Drive.
  Future<void> reloadFromStorage() async {
    final pm = AppStorage.readJson(
      StorageKeys.propertyManager,
      PropertyManager.fromJson,
    );
    final tenants = AppStorage.readList(StorageKeys.tenants, Tenant.fromJson);
    final prefs = AppStorage.readJson(
      StorageKeys.preferences,
      AppPreferences.fromJson,
    );
    final currency = AppStorage.readString(StorageKeys.selectedCurrency);
    final savedYearReload = int.tryParse(
      AppStorage.readString(StorageKeys.selectedYear) ?? '',
    );
    final onboarded =
        AppStorage.readString(StorageKeys.onboardingCompleted) == 'true';
    final properties = AppStorage.readList(
      StorageKeys.properties,
      Property.fromJson,
    );
    final rawSelectedPropertyId = AppStorage.readString(
      StorageKeys.selectedPropertyId,
    );

    final effectiveProperties = _syncPropertiesWithManager(
      properties,
      pm,
      tenants,
    );

    final selectedPropertyId =
        (rawSelectedPropertyId != null &&
            rawSelectedPropertyId != 'all' &&
            effectiveProperties.any((p) => p.id == rawSelectedPropertyId))
        ? rawSelectedPropertyId
        : effectiveProperties.isEmpty
        ? 'all'
        : effectiveProperties.first.id;

    final rawPayments = AppStorage.readList(
      StorageKeys.payments,
      Payment.fromJson,
    );
    final rawExpenses = AppStorage.readList(
      StorageKeys.expenses,
      Expense.fromJson,
    );
    final rawDocs = AppStorage.readList(
      StorageKeys.documents,
      RentDoc.fromJson,
    );
    final rawExpCats = AppStorage.readList(
      StorageKeys.expenseCategories,
      ExpenseCategory.fromJson,
    );
    final reconciled = await AutoDeduplicationService.reconcileAndPersist(
      payments: rawPayments,
      expenses: rawExpenses,
      documents: rawDocs,
      expenseCategories: rawExpCats,
      tenantById: {for (final t in tenants) t.id: t},
    );
    final payments = reconciled.payments;
    final expenses = reconciled.expenses;
    final documents = reconciled.documents;
    final expenseCategories = reconciled.expenseCategories.isEmpty
        ? DefaultData.expenseCategories()
        : reconciled.expenseCategories;
    final workOrders = AppStorage.readList(
      StorageKeys.workOrders,
      WorkOrder.fromJson,
    );
    final banks = AppStorage.readList(StorageKeys.banks, BankInfo.fromJson);
    final zakat = AppStorage.readList(
      StorageKeys.zakat,
      ZakatTransaction.fromJson,
    );
    final documentGroups = AppStorage.readList(
      StorageKeys.documentGroups,
      DocumentGroup.fromJson,
    );
    final docCats = AppStorage.readList(
      StorageKeys.documentCategories,
      DocumentCategory.fromJson,
    );
    final zakCats = AppStorage.readList(
      StorageKeys.zakatCategories,
      ZakatCategory.fromJson,
    );
    final monthlyNotes = AppStorage.readList(
      StorageKeys.monthlyNotes,
      MonthlyNote.fromJson,
    );
    final bankDeposits = AppStorage.readList(
      StorageKeys.bankDeposits,
      BankDeposit.fromJson,
    );
    final recentlyDeletedDocs = AppStorage.readList(
      StorageKeys.recentlyDeletedDocs,
      RentDoc.fromJson,
    );

    List<String> descs;
    final rawDescs = AppStorage.readString(StorageKeys.predefinedDescriptions);
    if (rawDescs != null && rawDescs.isNotEmpty) {
      try {
        descs = List<String>.from(jsonDecode(rawDescs) as List);
      } catch (_) {
        descs = DefaultData.predefinedDescriptions;
      }
    } else {
      descs = DefaultData.predefinedDescriptions;
    }

    state = state.copyWith(
      properties: effectiveProperties,
      selectedPropertyId: selectedPropertyId,
      propertyManager: pm,
      tenants: tenants,
      payments: payments,
      expenses: expenses,
      workOrders: workOrders,
      banks: banks,
      zakat: zakat,
      documents: documents,
      documentGroups: documentGroups,
      expenseCategories: expenseCategories,
      documentCategories: DefaultData.normalizedDocumentCategories(docCats),
      zakatCategories: DefaultData.normalizedZakatCategories(zakCats),
      monthlyNotes: monthlyNotes,
      bankDeposits: bankDeposits,
      recentlyDeletedDocs: recentlyDeletedDocs,
      predefinedDescriptions: descs,
      preferences: prefs ?? state.preferences,
      selectedCurrency: currency ?? state.selectedCurrency,
      selectedYear: savedYearReload ?? state.selectedYear,
      showOnboarding: !onboarded,
    );
  }

  void selectProperty(String propertyId) {
    String resolvedId = propertyId;
    if (resolvedId == 'all' ||
        !state.properties.any((p) => p.id == resolvedId)) {
      resolvedId = state.properties.isNotEmpty
          ? state.properties.first.id
          : 'prop-default';
    }
    state = state.copyWith(selectedPropertyId: resolvedId);
    _scheduleSave();
  }

  void addProperty(Property property) {
    final stamped = property.copyWith(
      updatedAt: DateTime.now().toIso8601String(),
    );
    final updated = [...state.properties, stamped];
    state = state.copyWith(properties: updated, selectedPropertyId: stamped.id);
    _scheduleSave();
  }

  void updateProperty(Property property) {
    final stamped = property.copyWith(
      updatedAt: DateTime.now().toIso8601String(),
    );
    final updated = state.properties
        .map((p) => p.id == stamped.id ? stamped : p)
        .toList();
    state = state.copyWith(properties: updated);
    _scheduleSave();
  }

  void deleteProperty(String propertyId) {
    if (state.properties.length <= 1) return;
    AppStorage.trackDeletedId(propertyId);
    final updated = state.properties.where((p) => p.id != propertyId).toList();
    final fallbackId = updated.first.id;
    final newSelected = state.selectedPropertyId == propertyId
        ? fallbackId
        : state.selectedPropertyId;
    final stampedAt = DateTime.now().toIso8601String();
    // The confirmation dialog promises dependent records are reassigned to the
    // default property. Orphaned records would otherwise disappear from every
    // property view because their propertyId no longer exists.
    state = state.copyWith(
      properties: updated,
      selectedPropertyId: newSelected,
      tenants: state.tenants
          .map(
            (t) => t.propertyId == propertyId
                ? t.copyWith(propertyId: fallbackId, updatedAt: stampedAt)
                : t,
          )
          .toList(),
      payments: state.payments
          .map(
            (p) => p.propertyId == propertyId
                ? p.copyWith(propertyId: fallbackId, updatedAt: stampedAt)
                : p,
          )
          .toList(),
      expenses: state.expenses
          .map(
            (e) => e.propertyId == propertyId
                ? e.copyWith(propertyId: fallbackId, updatedAt: stampedAt)
                : e,
          )
          .toList(),
      workOrders: state.workOrders
          .map(
            (w) => w.propertyId == propertyId
                ? w.copyWith(propertyId: fallbackId, updatedAt: stampedAt)
                : w,
          )
          .toList(),
      documents: state.documents
          .map(
            (d) => d.propertyId == propertyId
                ? d.copyWith(propertyId: fallbackId, updatedAt: stampedAt)
                : d,
          )
          .toList(),
      bankDeposits: state.bankDeposits
          .map(
            (d) => d.propertyId == propertyId
                ? d.copyWith(propertyId: fallbackId, updatedAt: stampedAt)
                : d,
          )
          .toList(),
      monthlyNotes: state.monthlyNotes
          .map(
            (n) => n.propertyId == propertyId
                ? n.copyWith(propertyId: fallbackId, updatedAt: stampedAt)
                : n,
          )
          .toList(),
      zakat: state.zakat
          .map(
            (z) => z.propertyId == propertyId
                ? z.copyWith(propertyId: fallbackId, updatedAt: stampedAt)
                : z,
          )
          .toList(),
    );
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () async {
      await _persist();
      if (state.preferences.driveAutoSync &&
          state.preferences.driveSyncFrequency == 'on_change') {
        DriveBackupService.triggerDebouncedSync(
          state,
          onSynced: (timestamp) {
            state = state.copyWith(
              preferences: state.preferences.copyWith(lastDriveSync: timestamp),
            );
            AppStorage.writeJson(
              StorageKeys.preferences,
              state.preferences.toJson(),
            );
          },
          onRemoteMerged: () {
            try {
              reloadFromStorage();
            } catch (e) {
              debugPrint('Debounced sync state refresh note: $e');
            }
          },
        );
      }
    });
  }

  Future<void> _persist() async {
    final s = state;
    await Future.wait([
      if (s.propertyManager != null)
        AppStorage.writeJson(
          StorageKeys.propertyManager,
          s.propertyManager!.toJson(),
        )
      else
        AppStorage.delete(StorageKeys.propertyManager),
      AppStorage.writeList(
        StorageKeys.properties,
        s.properties.map((e) => e.toJson()).toList(),
      ),
      AppStorage.writeString(
        StorageKeys.selectedPropertyId,
        s.selectedPropertyId,
      ),
      AppStorage.writeList(
        StorageKeys.tenants,
        s.tenants.map((e) => e.toJson()).toList(),
      ),
      AppStorage.writeList(
        StorageKeys.payments,
        s.payments.map((e) => e.toJson()).toList(),
      ),
      AppStorage.writeList(
        StorageKeys.expenses,
        s.expenses.map((e) => e.toJson()).toList(),
      ),
      AppStorage.writeList(
        StorageKeys.workOrders,
        s.workOrders.map((e) => e.toJson()).toList(),
      ),
      AppStorage.writeList(
        StorageKeys.banks,
        s.banks.map((e) => e.toJson()).toList(),
      ),
      AppStorage.writeList(
        StorageKeys.zakat,
        s.zakat.map((e) => e.toJson()).toList(),
      ),
      AppStorage.writeList(
        StorageKeys.documents,
        s.documents.map((e) => e.toJson()).toList(),
      ),
      AppStorage.writeList(
        StorageKeys.documentGroups,
        s.documentGroups.map((e) => e.toJson()).toList(),
      ),
      AppStorage.writeJson(StorageKeys.preferences, s.preferences.toJson()),
      AppStorage.writeString(StorageKeys.selectedCurrency, s.selectedCurrency),
      AppStorage.writeString(StorageKeys.selectedYear, '${s.selectedYear}'),
      AppStorage.writeList(
        StorageKeys.expenseCategories,
        s.expenseCategories.map((e) => e.toJson()).toList(),
      ),
      AppStorage.writeList(
        StorageKeys.documentCategories,
        s.documentCategories.map((e) => e.toJson()).toList(),
      ),
      AppStorage.writeList(
        StorageKeys.zakatCategories,
        s.zakatCategories.map((e) => e.toJson()).toList(),
      ),
      AppStorage.writeList(
        StorageKeys.monthlyNotes,
        s.monthlyNotes.map((e) => e.toJson()).toList(),
      ),
      AppStorage.writeList(
        StorageKeys.bankDeposits,
        s.bankDeposits.map((e) => e.toJson()).toList(),
      ),
      AppStorage.writeList(
        StorageKeys.recentlyDeletedDocs,
        s.recentlyDeletedDocs.map((e) => e.toJson()).toList(),
      ),
      AppStorage.writeString(
        StorageKeys.predefinedDescriptions,
        jsonEncode(s.predefinedDescriptions),
      ),
    ]);
  }

  // ---- Mutations (each mirrors handleDataUpdate in App.tsx) ----
  void dismissSplash() => state = state.copyWith(showSplash: false);
  void setYear(int y) {
    state = state.copyWith(selectedYear: y);
    _scheduleSave();
  }

  void setCurrency(String c) {
    state = state.copyWith(selectedCurrency: c);
    _scheduleSave();
  }

  void setPreferences(AppPreferences p) {
    state = state.copyWith(preferences: p);
    _scheduleSave();
  }

  void setThemeMode(String mode) {
    setPreferences(state.preferences.copyWith(themeMode: mode));
  }

  void setExpenseCategories(List<ExpenseCategory> list) {
    state = state.copyWith(
      expenseCategories: DefaultData.normalizedExpenseCategories(list),
    );
    _scheduleSave();
  }

  void setDocumentCategories(List<DocumentCategory> list) {
    state = state.copyWith(
      documentCategories: DefaultData.normalizedDocumentCategories(list),
    );
    _scheduleSave();
  }

  void setZakatCategories(List<ZakatCategory> list) {
    state = state.copyWith(
      zakatCategories: DefaultData.normalizedZakatCategories(list),
    );
    _scheduleSave();
  }

  void setDescriptions(List<String> list) {
    state = state.copyWith(predefinedDescriptions: list);
    _scheduleSave();
  }

  void setPropertyManager(PropertyManager m) {
    m = m.copyWith(updatedAt: DateTime.now().toIso8601String());
    final properties = _syncPropertiesWithManager(
      state.properties,
      m,
      state.tenants,
    );
    var selected = state.selectedPropertyId;
    if (properties.isNotEmpty &&
        (selected.isEmpty ||
            selected == 'all' ||
            !properties.any((p) => p.id == selected))) {
      selected = properties.first.id;
    }
    state = state.copyWith(
      propertyManager: m,
      properties: properties,
      selectedPropertyId: selected,
    );
    _scheduleSave();
  }

  /// Keeps the setup wizard mounted after a restore that imported an
  /// already-completed `onboardingCompleted` flag.
  void setShowOnboarding(bool value) {
    state = state.copyWith(showOnboarding: value);
  }

  Future<void> completeOnboarding() async {
    await AppStorage.writeString(StorageKeys.onboardingCompleted, 'true');
    // Release the Drive auto-sync pull gate (the setup wizard is done).
    // main.dart restarts the periodic sync timer when showOnboarding flips.
    DriveBackupService.setPullGate(false);
    state = state.copyWith(showOnboarding: false);
  }

  void upsertTenant(Tenant t) {
    var tenantToSave = t;
    final existing = state.tenants.where((e) => e.id == t.id).firstOrNull;
    if (existing != null &&
        (t.propertyId.isEmpty || t.propertyId == 'prop-default') &&
        existing.propertyId.isNotEmpty &&
        existing.propertyId != 'prop-default') {
      // Editing must never silently move a record onto the first property.
      tenantToSave = tenantToSave.copyWith(propertyId: existing.propertyId);
    } else if (state.selectedPropertyId != 'all' &&
        (tenantToSave.propertyId.isEmpty ||
            tenantToSave.propertyId == 'prop-default') &&
        existing == null) {
      tenantToSave = tenantToSave.copyWith(
        propertyId: state.selectedPropertyId,
      );
    }
    tenantToSave = tenantToSave.copyWith(
      updatedAt: DateTime.now().toIso8601String(),
    );
    final list = [...state.tenants];
    final i = list.indexWhere((e) => e.id == tenantToSave.id);
    if (i >= 0) {
      list[i] = tenantToSave;
    } else {
      list.add(tenantToSave);
    }
    state = state.copyWith(tenants: list);
    _scheduleSave();
  }

  void deleteTenant(String id) {
    AppStorage.trackDeletedId(id);
    final doomed = state.tenants.where((e) => e.id == id).toList();
    final name = doomed.isEmpty ? null : doomed.first.name;
    final unit = doomed.isEmpty ? null : doomed.first.unit;
    final tenantPropId = doomed.isEmpty ? null : doomed.first.propertyId;
    final paymentIds = state.payments
        .where((p) => p.tenantId == id)
        .map((p) => p.id)
        .toList();
    if (paymentIds.isNotEmpty) {
      AppStorage.trackDeletedIds(paymentIds);
      for (final pid in paymentIds) {
        NotificationService.cancelById(NotificationService.stableIntId(pid));
      }
    }
    final doomedDocs = name == null
        ? const <RentDoc>[]
        : state.documents.where((d) {
            if (d.tenant != name) return false;
            // Never delete a same-named tenant's documents from another
            // property. Legacy docs without an explicit property are only
            // matched by unit.
            final docProp = d.propertyId;
            if (tenantPropId != null &&
                tenantPropId.isNotEmpty &&
                tenantPropId != 'prop-default' &&
                docProp != null &&
                docProp.isNotEmpty &&
                docProp != 'prop-default' &&
                docProp != tenantPropId) {
              return false;
            }
            return unit == null ||
                unit.isEmpty ||
                d.unit == null ||
                d.unit!.isEmpty ||
                d.unit == unit;
          }).toList();
    AppStorage.trackDeletedIds(doomedDocs.map((d) => d.id));
    final workOrderIds = state.workOrders
        .where((w) => w.tenantId == id)
        .map((w) => w.id)
        .toList();
    if (workOrderIds.isNotEmpty) {
      AppStorage.trackDeletedIds(workOrderIds);
    }
    state = state.copyWith(
      tenants: state.tenants.where((e) => e.id != id).toList(),
      payments: state.payments.where((p) => p.tenantId != id).toList(),
      workOrders: state.workOrders.where((w) => w.tenantId != id).toList(),
      documents: doomedDocs.isEmpty
          ? state.documents
          : state.documents
                .where((d) => !doomedDocs.any((x) => x.id == d.id))
                .toList(),
    );
    _scheduleSave();
  }

  /// Bulk status update for rent-roll rows (long-press actions).
  void markPayments(List<String> ids, String status) {
    final stampedAt = DateTime.now().toIso8601String();
    state = state.copyWith(
      payments: state.payments
          .map(
            (p) => ids.contains(p.id)
                ? p.copyWith(
                    status: status,
                    updatedAt: stampedAt,
                    paidDate: status == 'paid'
                        ? (p.paidDate ?? stampedAt)
                        : p.paidDate,
                  )
                : p,
          )
          .toList(),
    );
    _scheduleSave();
    if (status != 'pending' && status != 'overdue') {
      for (final id in ids) {
        NotificationService.cancelById(NotificationService.stableIntId(id));
      }
    }
  }

  void deletePayments(List<String> ids) {
    AppStorage.trackDeletedIds(ids);
    for (final id in ids) {
      NotificationService.cancelById(NotificationService.stableIntId(id));
    }
    state = state.copyWith(
      payments: state.payments.where((p) => !ids.contains(p.id)).toList(),
    );
    _scheduleSave();
  }

  void deleteExpenses(List<String> ids) {
    AppStorage.trackDeletedIds(ids);
    state = state.copyWith(
      expenses: state.expenses.where((e) => !ids.contains(e.id)).toList(),
    );
    _scheduleSave();
  }

  void upsertPayment(Payment p) {
    var paymentToSave = p;
    final existing = state.payments.where((e) => e.id == p.id).firstOrNull;
    if (existing != null &&
        (p.propertyId == null ||
            p.propertyId!.isEmpty ||
            p.propertyId == 'prop-default') &&
        existing.propertyId != null &&
        existing.propertyId!.isNotEmpty &&
        existing.propertyId != 'prop-default') {
      paymentToSave = paymentToSave.copyWith(propertyId: existing.propertyId);
    } else if (paymentToSave.propertyId == null ||
        paymentToSave.propertyId!.isEmpty ||
        paymentToSave.propertyId == 'prop-default') {
      final tenant = state.tenants.where((t) => t.id == p.tenantId).firstOrNull;
      if (tenant != null &&
          tenant.propertyId.isNotEmpty &&
          tenant.propertyId != 'prop-default') {
        paymentToSave = paymentToSave.copyWith(propertyId: tenant.propertyId);
      } else if (state.selectedPropertyId != 'all') {
        paymentToSave = paymentToSave.copyWith(
          propertyId: state.selectedPropertyId,
        );
      }
    }
    paymentToSave = paymentToSave.copyWith(
      updatedAt: DateTime.now().toIso8601String(),
    );
    final list = [...state.payments];
    final i = list.indexWhere((e) => e.id == paymentToSave.id);
    final oldStatus = i >= 0 ? list[i].status : null;
    if (i >= 0) {
      list[i] = paymentToSave;
    } else {
      list.add(paymentToSave);
    }
    state = state.copyWith(payments: list);
    _scheduleSave();
    // Payment left the pending/overdue window: kill any scheduled reminder.
    if (oldStatus == 'pending' || oldStatus == 'overdue') {
      if (paymentToSave.status != 'pending' &&
          paymentToSave.status != 'overdue') {
        NotificationService.cancelById(
          NotificationService.stableIntId(paymentToSave.id),
        );
      }
    }
    _maybeScheduleRentReminder(paymentToSave);
  }

  void upsertPayments(List<Payment> newPayments) {
    if (newPayments.isEmpty) return;
    final list = [...state.payments];
    final processed = <Payment>[];
    for (var p in newPayments) {
      final existing = list.where((e) => e.id == p.id).firstOrNull;
      if (existing != null &&
          (p.propertyId == null ||
              p.propertyId!.isEmpty ||
              p.propertyId == 'prop-default') &&
          existing.propertyId != null &&
          existing.propertyId!.isNotEmpty &&
          existing.propertyId != 'prop-default') {
        p = p.copyWith(propertyId: existing.propertyId);
      } else if (p.propertyId == null ||
          p.propertyId!.isEmpty ||
          p.propertyId == 'prop-default') {
        final tenant = state.tenants
            .where((t) => t.id == p.tenantId)
            .firstOrNull;
        if (tenant != null &&
            tenant.propertyId.isNotEmpty &&
            tenant.propertyId != 'prop-default') {
          p = p.copyWith(propertyId: tenant.propertyId);
        } else if (state.selectedPropertyId != 'all') {
          p = p.copyWith(propertyId: state.selectedPropertyId);
        }
      }
      p = p.copyWith(updatedAt: DateTime.now().toIso8601String());
      processed.add(p);
      final i = list.indexWhere((e) => e.id == p.id);
      if (i >= 0) {
        list[i] = p;
      } else {
        list.add(p);
      }
    }
    state = state.copyWith(payments: list);
    _scheduleSave();
    for (final p in processed) {
      _maybeScheduleRentReminder(p);
    }
  }

  /// Ports rent-due (T-1 day) scheduling, gated by notification prefs.
  void _maybeScheduleRentReminder(Payment p) {
    try {
      if (!state.preferences.notifRentDue) return;
      if (p.status != 'pending' && p.status != 'overdue') return;
      final due = p.dueDate == null ? null : DateTime.tryParse(p.dueDate!);
      if (due == null) return;
      final fire = due.subtract(const Duration(days: 1));
      if (fire.isBefore(DateTime.now())) return;
      final tenant = state.tenants.where((t) => t.id == p.tenantId).toList();
      NotificationService.rentDueReminderAt(
        id: NotificationService.stableIntId(p.id),
        tenant: tenant.isEmpty ? 'Tenant' : tenant.first.name,
        unit: tenant.isEmpty ? '' : tenant.first.unit,
        at: fire,
      );
    } catch (_) {}
  }

  void deletePayment(String id) {
    AppStorage.trackDeletedId(id);
    NotificationService.cancelById(NotificationService.stableIntId(id));
    state = state.copyWith(
      payments: state.payments.where((e) => e.id != id).toList(),
    );
    _scheduleSave();
  }

  void upsertExpense(Expense e) {
    var expenseToSave = e;
    final existing = state.expenses.where((x) => x.id == e.id).firstOrNull;
    if (existing != null &&
        (e.propertyId == null ||
            e.propertyId!.isEmpty ||
            e.propertyId == 'prop-default') &&
        existing.propertyId != null &&
        existing.propertyId!.isNotEmpty &&
        existing.propertyId != 'prop-default') {
      expenseToSave = expenseToSave.copyWith(propertyId: existing.propertyId);
    } else if (state.selectedPropertyId != 'all' &&
        (expenseToSave.propertyId == null ||
            expenseToSave.propertyId!.isEmpty ||
            expenseToSave.propertyId == 'prop-default') &&
        existing == null) {
      expenseToSave = expenseToSave.copyWith(
        propertyId: state.selectedPropertyId,
      );
    }
    expenseToSave = expenseToSave.copyWith(
      updatedAt: DateTime.now().toIso8601String(),
    );
    final list = [...state.expenses];
    final i = list.indexWhere((x) => x.id == expenseToSave.id);
    if (i >= 0) {
      list[i] = expenseToSave;
    } else {
      list.add(expenseToSave);
    }
    state = state.copyWith(expenses: list);
    _scheduleSave();
  }

  void deleteExpense(String id) {
    AppStorage.trackDeletedId(id);
    state = state.copyWith(
      expenses: state.expenses.where((e) => e.id != id).toList(),
    );
    _scheduleSave();
  }

  void upsertWorkOrder(WorkOrder w) {
    var workOrderToSave = w;
    final existing = state.workOrders.where((x) => x.id == w.id).firstOrNull;
    if (existing != null &&
        (w.propertyId == null ||
            w.propertyId!.isEmpty ||
            w.propertyId == 'prop-default') &&
        existing.propertyId != null &&
        existing.propertyId!.isNotEmpty &&
        existing.propertyId != 'prop-default') {
      workOrderToSave = workOrderToSave.copyWith(
        propertyId: existing.propertyId,
      );
    } else if (workOrderToSave.propertyId == null ||
        workOrderToSave.propertyId!.isEmpty ||
        workOrderToSave.propertyId == 'prop-default') {
      Tenant? tenant;
      if (w.tenantId != null && w.tenantId!.isNotEmpty) {
        tenant = state.tenants.where((t) => t.id == w.tenantId).firstOrNull;
      }
      if (tenant != null &&
          tenant.propertyId.isNotEmpty &&
          tenant.propertyId != 'prop-default') {
        workOrderToSave = workOrderToSave.copyWith(
          propertyId: tenant.propertyId,
        );
      } else if (state.selectedPropertyId != 'all' && existing == null) {
        workOrderToSave = workOrderToSave.copyWith(
          propertyId: state.selectedPropertyId,
        );
      }
    }
    workOrderToSave = workOrderToSave.copyWith(
      updatedAt: DateTime.now().toIso8601String(),
    );
    final list = [...state.workOrders];
    final i = list.indexWhere((e) => e.id == workOrderToSave.id);
    final was = i >= 0 ? list[i].status : null;
    if (i >= 0) {
      list[i] = workOrderToSave;
    } else {
      list.add(workOrderToSave);
    }
    state = state.copyWith(workOrders: list);
    _scheduleSave();
    try {
      if (w.status == 'completed' &&
          was != 'completed' &&
          state.preferences.notifWorkOrder) {
        NotificationService.immediate(
          id: w.id.hashCode & 0x7fffffff,
          channel: 'work_orders',
          title: 'Work order completed',
          body: '${w.title} marked as completed.',
        );
      }
    } catch (_) {}
  }

  void deleteWorkOrder(String id) {
    AppStorage.trackDeletedId(id);
    state = state.copyWith(
      workOrders: state.workOrders.where((e) => e.id != id).toList(),
    );
    _scheduleSave();
  }

  void upsertZakat(ZakatTransaction z) {
    var entry = z.copyWith(updatedAt: DateTime.now().toIso8601String());
    final list = [...state.zakat];
    final i = list.indexWhere((e) => e.id == z.id);
    if (i >= 0) {
      final existingProp = list[i].propertyId;
      if ((entry.propertyId == null || entry.propertyId!.isEmpty) &&
          existingProp != null &&
          existingProp.isNotEmpty) {
        entry = entry.copyWith(propertyId: existingProp);
      }
      list[i] = entry;
    } else {
      final tagged =
          (entry.propertyId == null || entry.propertyId!.isEmpty) &&
              state.selectedPropertyId != 'all' &&
              state.selectedPropertyId.isNotEmpty
          ? entry.copyWith(propertyId: state.selectedPropertyId)
          : entry;
      list.add(tagged);
    }
    state = state.copyWith(zakat: list);
    _scheduleSave();
  }

  void deleteZakat(String id) {
    AppStorage.trackDeletedId(id);
    state = state.copyWith(
      zakat: state.zakat.where((e) => e.id != id).toList(),
    );
    _scheduleSave();
  }

  void deleteZakats(List<String> ids) {
    AppStorage.trackDeletedIds(ids);
    state = state.copyWith(
      zakat: state.zakat.where((e) => !ids.contains(e.id)).toList(),
    );
    _scheduleSave();
  }

  void setZakat(List<ZakatTransaction> list) {
    state = state.copyWith(zakat: list);
    _scheduleSave();
  }

  void upsertDocument(RentDoc d) {
    var docToSave = d;
    final existing = state.documents.where((x) => x.id == d.id).firstOrNull;
    if (existing != null &&
        (d.propertyId == null ||
            d.propertyId!.isEmpty ||
            d.propertyId == 'prop-default') &&
        existing.propertyId != null &&
        existing.propertyId!.isNotEmpty &&
        existing.propertyId != 'prop-default') {
      docToSave = docToSave.copyWith(propertyId: existing.propertyId);
    } else if (docToSave.propertyId == null ||
        docToSave.propertyId!.isEmpty ||
        docToSave.propertyId == 'prop-default') {
      Tenant? tenant;
      if (d.tenant != null && d.tenant!.isNotEmpty) {
        tenant = state.tenants.where((t) => t.name == d.tenant).firstOrNull;
      }
      if (tenant != null &&
          tenant.propertyId.isNotEmpty &&
          tenant.propertyId != 'prop-default') {
        docToSave = docToSave.copyWith(propertyId: tenant.propertyId);
      } else if (state.selectedPropertyId != 'all' && existing == null) {
        docToSave = docToSave.copyWith(propertyId: state.selectedPropertyId);
      }
    }
    docToSave = docToSave.copyWith(updatedAt: DateTime.now().toIso8601String());
    final list = [...state.documents];
    final i = list.indexWhere((e) => e.id == docToSave.id);
    if (i >= 0) {
      list[i] = docToSave;
    } else {
      list.add(docToSave);
    }
    state = state.copyWith(documents: list);
    _scheduleSave();
  }

  /// Permanently deletes a document — Expo `handleDeleteDocument` behavior.
  void deleteDocument(String id) {
    AppStorage.trackDeletedId(id);
    state = state.copyWith(
      documents: state.documents.where((e) => e.id != id).toList(),
    );
    _scheduleSave();
  }

  void upsertDocumentGroup(DocumentGroup g) {
    final stamped = g.copyWith(updatedAt: DateTime.now().toIso8601String());
    final list = [...state.documentGroups];
    final i = list.indexWhere((e) => e.id == stamped.id);
    if (i >= 0) {
      list[i] = stamped;
    } else {
      list.add(stamped);
    }
    state = state.copyWith(documentGroups: list);
    _scheduleSave();
  }

  /// Deletes a group record; its files stay in the library (ungrouped).
  void deleteDocumentGroup(String id) {
    AppStorage.trackDeletedId(id);
    state = state.copyWith(
      documentGroups: state.documentGroups.where((g) => g.id != id).toList(),
      documents: state.documents
          .map(
            (d) => d.groupId == id
                ? RentDoc(
                    id: d.id,
                    title: d.title,
                    type: d.type,
                    fileName: d.fileName,
                    fileSize: d.fileSize,
                    uploadedBy: d.uploadedBy,
                    uploadedDate: d.uploadedDate,
                    status: d.status,
                    unit: d.unit,
                    tenant: d.tenant,
                    fileUri: d.fileUri,
                    description: d.description,
                    tags: d.tags,
                    priority: d.priority,
                    propertyId: d.propertyId,
                    expiryDate: d.expiryDate,
                    groupId: null,
                    version: d.version,
                    thumbnailUri: d.thumbnailUri,
                    isPdf: d.isPdf,
                    pageCount: d.pageCount,
                    updatedAt: DateTime.now().toIso8601String(),
                  )
                : d,
          )
          .toList(),
    );
    _scheduleSave();
  }

  void trashDocument(String id) {
    final doc = state.documents.where((e) => e.id == id).toList();
    if (doc.isEmpty) return;
    final stamped = doc.first.copyWith(
      updatedAt: DateTime.now().toIso8601String(),
    );
    state = state.copyWith(
      documents: state.documents.where((e) => e.id != id).toList(),
      recentlyDeletedDocs: [...state.recentlyDeletedDocs, stamped],
    );
    _scheduleSave();
  }

  void restoreDocument(String id) {
    final doc = state.recentlyDeletedDocs.where((e) => e.id == id).toList();
    if (doc.isEmpty) return;
    final stamped = doc.first.copyWith(
      updatedAt: DateTime.now().toIso8601String(),
    );
    state = state.copyWith(
      recentlyDeletedDocs: state.recentlyDeletedDocs
          .where((e) => e.id != id)
          .toList(),
      documents: [...state.documents, stamped],
    );
    _scheduleSave();
  }

  // ===================== Tenant document sync =====================

  void loadTenantSyncStatuses() {
    final raw = AppStorage.readString('tenantSyncStatus');
    tenantSyncStatuses.clear();
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List;
      tenantSyncStatuses.addAll(
        list.map(
          (e) => TenantSyncStatus.fromJson(Map<String, dynamic>.from(e as Map)),
        ),
      );
    } catch (_) {
      tenantSyncStatuses.clear();
    }
  }

  void _persistTenantSyncStatuses() {
    AppStorage.writeString(
      'tenantSyncStatus',
      jsonEncode(tenantSyncStatuses.map((e) => e.toJson()).toList()),
    );
  }

  TenantSyncStatus? tenantSyncStatusFor(String tenantName) =>
      tenantSyncStatuses.where((x) => x.tenantName == tenantName).firstOrNull;

  void recordTenantSync(TenantSyncStatus s) {
    tenantSyncStatuses.removeWhere((x) => x.tenantName == s.tenantName);
    tenantSyncStatuses.add(s);
    _persistTenantSyncStatuses();
  }

  /// Port of Expo `syncTenantDocuments`: copies tenant documents into the main
  /// Documents library under a per-tenant group. Returns (synced, failed).
  ({int synced, int failed}) syncTenantDocuments(
    Tenant t, {
    bool retry = false,
  }) {
    if (t.documents.isEmpty) return (synced: 0, failed: 0);
    // Group by immutable tenant id. Names are not unique across properties, so
    // name-keyed groups used to overwrite another tenant's documents.
    final groupId = 'tenant_${t.id}';

    // Find existing documents for this tenant (by group ID or legacy name
    // match), but never cross a property boundary.
    final existingForTenant = state.documents.where((d) {
      final sameName =
          d.tenant != null &&
          d.tenant!.trim().toLowerCase() == t.name.trim().toLowerCase();
      if (d.groupId != groupId && !sameName) return false;
      if (d.groupId == groupId) return true;
      final docProp = d.propertyId;
      return docProp == null ||
          docProp.isEmpty ||
          docProp == 'prop-default' ||
          t.propertyId == 'prop-default' ||
          docProp == t.propertyId;
    }).toList();

    final existingByTitle = <String, RentDoc>{};
    for (final d in existingForTenant) {
      existingByTitle[d.title.trim().toLowerCase()] = d;
    }

    int synced = 0;
    int failed = 0;
    final inFlightTitles = <String>{};

    for (final td in t.documents) {
      final titleKey = td.name.trim().toLowerCase();
      if (titleKey.isEmpty) {
        failed++;
        continue;
      }
      if (inFlightTitles.contains(titleKey)) {
        continue; // Prevent intra-batch duplicates
      }
      inFlightTitles.add(titleKey);

      final existingDoc = existingByTitle[titleKey];
      if (existingDoc != null) {
        // Update existing document instead of creating a duplicate clone
        final updated = RentDoc(
          id: existingDoc.id,
          title: td.name,
          type: td.type.isNotEmpty ? td.type : existingDoc.type,
          fileName: td.name,
          fileSize: existingDoc.fileSize,
          uploadedBy: existingDoc.uploadedBy,
          uploadedDate: td.uploadedAt.isNotEmpty
              ? td.uploadedAt
              : existingDoc.uploadedDate,
          status: 'active',
          unit: t.unit,
          tenant: t.name,
          fileUri: td.uri.isNotEmpty ? td.uri : existingDoc.fileUri,
          description: 'Tenant document: ${td.name}',
          priority: existingDoc.priority,
          tags: ['tenant-document', td.type, 'tenant-group'],
          groupId: groupId,
          propertyId: existingDoc.propertyId ?? t.propertyId,
        );
        upsertDocument(updated);
        synced++;
      } else {
        if (td.uri.isEmpty && !retry) {
          failed++;
          continue;
        }
        final newDoc = RentDoc(
          id: newId(),
          title: td.name,
          type: td.type,
          fileName: 'tenant_${td.name}',
          fileSize: 'Unknown',
          uploadedBy: 'System',
          uploadedDate: td.uploadedAt.isEmpty
              ? DateTime.now().toIso8601String()
              : td.uploadedAt,
          status: 'active',
          unit: t.unit,
          tenant: t.name,
          fileUri: td.uri,
          description: 'Tenant document: ${td.name}',
          priority: 'medium',
          tags: ['tenant-document', td.type, 'tenant-group'],
          groupId: groupId,
          propertyId: t.propertyId,
        );
        existingByTitle[titleKey] = newDoc;
        upsertDocument(newDoc);
        synced++;
      }
    }

    // Refresh tenant document group
    final currentTenantDocs = state.documents
        .where(
          (d) =>
              d.groupId == groupId ||
              (d.tenant == t.name && d.tags.contains('tenant-document')),
        )
        .toList();

    if (currentTenantDocs.isNotEmpty) {
      upsertDocumentGroup(
        DocumentGroup(
          id: groupId,
          title: 'Tenant Documents - ${t.name}',
          type: t.documents.first.type,
          description: 'Documents for tenant ${t.name} in unit ${t.unit}',
          uploadedBy: 'System',
          uploadedDate: DateTime.now().toIso8601String(),
          unit: t.unit,
          tenant: t.name,
          documents: currentTenantDocs,
        ),
      );
    }
    return (synced: synced, failed: failed);
  }

  void upsertBank(BankInfo b) {
    final stamped = b.copyWith(updatedAt: DateTime.now().toIso8601String());
    final list = [...state.banks];
    final i = list.indexWhere((e) => e.id == stamped.id);
    if (i >= 0) {
      list[i] = stamped;
    } else {
      list.add(stamped);
    }
    state = state.copyWith(banks: list);
    _scheduleSave();
  }

  /// Replace the whole bank list (ports setupManager.saveBanks used by the
  /// onboarding BankSetupModal, which saves the full edited array at once).
  void setBanks(List<BankInfo> list) {
    final stampedAt = DateTime.now().toIso8601String();
    state = state.copyWith(
      banks: list.map((b) => b.copyWith(updatedAt: stampedAt)).toList(),
    );
    _scheduleSave();
  }

  void upsertDeposit(BankDeposit d) {
    final existing = state.bankDeposits.where((e) => e.id == d.id).firstOrNull;
    String? propertyId = d.propertyId;
    if ((propertyId == null || propertyId.isEmpty) &&
        existing?.propertyId != null &&
        existing!.propertyId!.isNotEmpty) {
      propertyId = existing.propertyId;
    }
    final activePropId =
        propertyId ??
        (state.selectedPropertyId == 'all'
            ? (state.activeProperty?.id ?? 'prop-default')
            : state.selectedPropertyId);
    final depositToSave = d.copyWith(
      propertyId: activePropId,
      updatedAt: DateTime.now().toIso8601String(),
    );

    final list = [...state.bankDeposits];
    final i = list.indexWhere((e) => e.id == depositToSave.id);
    if (i >= 0) {
      list[i] = depositToSave;
    } else {
      list.add(depositToSave);
    }
    state = state.copyWith(bankDeposits: list);
    _scheduleSave();
  }

  void deleteDeposit(String id) {
    AppStorage.trackDeletedId(id);
    state = state.copyWith(
      bankDeposits: state.bankDeposits.where((d) => d.id != id).toList(),
    );
    _scheduleSave();
  }

  void toggleNote(String id) {
    final stampedAt = DateTime.now().toIso8601String();
    state = state.copyWith(
      monthlyNotes: state.monthlyNotes
          .map(
            (n) => n.id == id
                ? n.copyWith(done: !n.done, updatedAt: stampedAt)
                : n,
          )
          .toList(),
    );
    _scheduleSave();
  }

  /// Port of the checklist edit (multiline modal) + long-press delete.
  void updateNoteText(String id, String text) {
    final stampedAt = DateTime.now().toIso8601String();
    state = state.copyWith(
      monthlyNotes: state.monthlyNotes
          .map(
            (n) =>
                n.id == id ? n.copyWith(text: text, updatedAt: stampedAt) : n,
          )
          .toList(),
    );
    _scheduleSave();
  }

  void deleteNote(String id) {
    AppStorage.trackDeletedId(id);
    state = state.copyWith(
      monthlyNotes: state.monthlyNotes.where((n) => n.id != id).toList(),
    );
    _scheduleSave();
  }

  void addNote(MonthlyNote n) {
    final activePropId =
        n.propertyId ??
        (state.selectedPropertyId == 'all'
            ? (state.activeProperty?.id ?? 'prop-default')
            : state.selectedPropertyId);
    final stampedAt = DateTime.now().toIso8601String();
    final noteToSave = (n.propertyId == null || n.propertyId!.isEmpty)
        ? n.copyWith(propertyId: activePropId, updatedAt: stampedAt)
        : n.copyWith(updatedAt: stampedAt);

    final cleanText = noteToSave.text.trim().toLowerCase();
    final exists = state.monthlyNotes.any((existing) {
      final existingProp = existing.propertyId ?? 'prop-default';
      return existing.month == noteToSave.month &&
          existing.text.trim().toLowerCase() == cleanText &&
          (existingProp == activePropId || state.properties.isEmpty);
    });
    if (exists) {
      // Avoid duplicate notes with identical text for the same month and property
      return;
    }
    state = state.copyWith(monthlyNotes: [...state.monthlyNotes, noteToSave]);
    _scheduleSave();
  }

  /// Replace a month's whole checklist (Expo monthlyNotes[month] = items[]).
  /// Scoped to the active or specified propertyId.
  /// Completion is preserved for items whose text is unchanged.
  void setNotesForMonth(
    String month,
    List<String> items, {
    String? propertyId,
  }) {
    final targetPropId =
        propertyId ??
        (state.selectedPropertyId == 'all'
            ? (state.activeProperty?.id ?? 'prop-default')
            : state.selectedPropertyId);

    final existing = state.monthlyNotes.where((n) {
      final pid = n.propertyId ?? 'prop-default';
      final matchesProp =
          pid == targetPropId ||
          ((n.propertyId == null || n.propertyId!.isEmpty) &&
              (targetPropId == 'prop-default' || state.properties.isEmpty));
      return n.month == month && matchesProp;
    }).toList();

    final stampedAt = DateTime.now().toIso8601String();
    final kept = <MonthlyNote>[];
    for (final text in items) {
      MonthlyNote? match;
      for (final e in existing) {
        if (e.text == text) {
          match = e;
          break;
        }
      }
      kept.add(
        match?.copyWith(updatedAt: stampedAt) ??
            MonthlyNote(
              id: newId(),
              text: text,
              month: month,
              done: false,
              propertyId: targetPropId,
              updatedAt: stampedAt,
            ),
      );
    }
    state = state.copyWith(
      monthlyNotes: [
        ...state.monthlyNotes.where((n) {
          final pid = n.propertyId ?? 'prop-default';
          final matchesProp =
              pid == targetPropId ||
              ((n.propertyId == null || n.propertyId!.isEmpty) &&
                  (targetPropId == 'prop-default' || state.properties.isEmpty));
          return !(n.month == month && matchesProp);
        }),
        ...kept,
      ],
    );
    _scheduleSave();
  }

  Future<void> resetApp() async {
    // Cancel any pending debounced write. Otherwise a save scheduled moments
    // before the reset can fire after clearAll() and resurrect the old data.
    _saveTimer?.cancel();
    // Full clean slate: also detach Drive sync so the periodic sync timer
    // cannot silently restore old cloud data (and flipped onboarding state)
    // over the wiped local database.
    DriveBackupService.setPullGate(true);
    DriveBackupService.stopPeriodicSync();
    try {
      await DriveBackupService.signOut();
    } catch (_) {}
    await AppStorage.clearAll();
    state = AppDataState(
      preferences: AppPreferences(showZakat: true),
      selectedYear: DateTime.now().year,
      isLoading: false,
      showSplash: false,
      showOnboarding: true,
    );
  }

  /// Import engine — port of ImportPreviewModal `replace|merge` mode plus
  /// per-type duplicateResolution `skip|update|create`.
  /// Returns per-section {added, updated, skipped} counts.
  Future<Map<String, Map<String, int>>> applyImport(
    Map<String, dynamic> rawMap, {
    String mode = 'replace',
    Map<String, String> strategies = const {},
  }) async {
    final map = await AppMediaBackup.unpackMedia(rawMap);
    List<Map<String, dynamic>> decode(String key) {
      final v = map[key];
      if (v == null) return [];
      try {
        final raw = v is String ? jsonDecode(v) : v;
        if (raw is List) {
          return raw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {}
      return [];
    }

    List<T> safeList<T>(
      List<Map<String, dynamic>> rawList,
      T Function(Map<String, dynamic>) fromJson,
    ) {
      final out = <T>[];
      for (final m in rawList) {
        try {
          out.add(fromJson(m));
        } catch (_) {}
      }
      return out;
    }

    final summary = <String, Map<String, int>>{};
    final tombstones = AppStorage.getDeletedIds();
    List<Map<String, dynamic>> mergeLists(
      String key,
      List<Map<String, dynamic>> current,
      List<Map<String, dynamic>> incoming,
    ) {
      final counts = {'added': 0, 'updated': 0, 'skipped': 0};
      summary[key] = counts;
      if (!map.containsKey(key)) return current;
      if (incoming.isEmpty) {
        if (mode == 'replace') {
          counts['added'] = 0;
          return [];
        }
        return current;
      }
      if (mode == 'replace') {
        counts['added'] = incoming.length;
        return incoming;
      }
      final strat = strategies[key] ?? 'skip';
      final byId = {for (final e in current) '${e['id']}': e};
      final out = [...current];
      for (final item in incoming) {
        final id = '${item['id']}';
        // Never resurrect records the user explicitly deleted on this device.
        if (tombstones.contains(id)) {
          counts['skipped'] = counts['skipped']! + 1;
          continue;
        }
        final idx = out.indexWhere((e) => '${e['id']}' == id);
        if (idx < 0) {
          out.add(item);
          byId[id] = item;
          counts['added'] = counts['added']! + 1;
        } else if (strat == 'update') {
          out[idx] = item;
          counts['updated'] = counts['updated']! + 1;
        } else if (strat == 'create') {
          final copy = Map<String, dynamic>.from(item);
          copy['id'] = newId();
          out.add(copy);
          counts['added'] = counts['added']! + 1;
        } else {
          counts['skipped'] = counts['skipped']! + 1;
        }
      }
      return out;
    }

    final props = mergeLists(
      'properties',
      state.properties.map((e) => e.toJson()).toList(),
      decode('properties'),
    );
    final tenants = mergeLists(
      'tenants',
      state.tenants.map((e) => e.toJson()).toList(),
      decode('tenants'),
    );
    final payments = mergeLists(
      'payments',
      state.payments.map((e) => e.toJson()).toList(),
      decode('payments'),
    );
    final expenses = mergeLists(
      'expenses',
      state.expenses.map((e) => e.toJson()).toList(),
      decode('expenses'),
    );
    final workOrders = mergeLists(
      'workOrders',
      state.workOrders.map((e) => e.toJson()).toList(),
      decode('workOrders'),
    );
    final banks = mergeLists(
      'banks',
      state.banks.map((e) => e.toJson()).toList(),
      decode('banks'),
    );
    final zakat = mergeLists(
      'zakat',
      state.zakat.map((e) => e.toJson()).toList(),
      decode('zakat'),
    );
    final documents = mergeLists(
      'documents',
      state.documents.map((e) => e.toJson()).toList(),
      decode('documents'),
    );
    final groups = mergeLists(
      'documentGroups',
      state.documentGroups.map((e) => e.toJson()).toList(),
      decode('documentGroups'),
    );
    final deposits = mergeLists(
      'bankDeposits',
      state.bankDeposits.map((e) => e.toJson()).toList(),
      decode('bankDeposits'),
    );
    final notes = mergeLists(
      'monthlyNotes',
      state.monthlyNotes.map((e) => e.toJson()).toList(),
      decode('monthlyNotes'),
    );
    final expCats = mergeLists(
      'expenseCategories',
      state.expenseCategories.map((e) => e.toJson()).toList(),
      decode('expenseCategories'),
    );
    final docCats = mergeLists(
      'documentCategories',
      state.documentCategories.map((e) => e.toJson()).toList(),
      decode('documentCategories'),
    );
    final zakCats = mergeLists(
      'zakatCategories',
      state.zakatCategories.map((e) => e.toJson()).toList(),
      decode('zakatCategories'),
    );

    List<String> descs = state.predefinedDescriptions;
    if (map['predefinedDescriptions'] != null) {
      try {
        final raw = map['predefinedDescriptions'];
        final list = raw is String
            ? List<String>.from(jsonDecode(raw) as List)
            : List<String>.from(raw as List);
        descs = mode == 'replace' ? list : {...descs, ...list}.toList();
      } catch (_) {}
    }

    // Restore polymorphic preferences to SharedPreferences if provided
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

    String curr = state.selectedCurrency;
    if (map['selectedCurrency'] != null) {
      curr = map['selectedCurrency'].toString();
    }

    T? single<T>(String key, T Function(Map<String, dynamic>) f) {
      final v = map[key];
      if (v == null) return null;
      try {
        final m = v is String
            ? Map<String, dynamic>.from(jsonDecode(v) as Map)
            : Map<String, dynamic>.from(v as Map);
        return f(m);
      } catch (_) {
        return null;
      }
    }

    // Restore the property list too; without this, imported records reference
    // properties that do not exist locally and disappear from every view.
    final importedProperties = safeList(props, Property.fromJson);
    final effectiveProperties = importedProperties.isEmpty
        ? state.properties
        : importedProperties;
    String selectedProp =
        map['selectedPropertyId']?.toString() ?? state.selectedPropertyId;
    if (effectiveProperties.isNotEmpty &&
        !effectiveProperties.any((p) => p.id == selectedProp)) {
      selectedProp = effectiveProperties.first.id;
    }

    String remapProperty(String? id) {
      if (id == null || id.isEmpty || id == 'prop-default') {
        return effectiveProperties.isNotEmpty
            ? effectiveProperties.first.id
            : 'prop-default';
      }
      if (effectiveProperties.isNotEmpty &&
          !effectiveProperties.any((p) => p.id == id)) {
        return effectiveProperties.first.id;
      }
      return id;
    }

    final importedManager = single('propertyManager', PropertyManager.fromJson);
    final managerKeyPresent = map.containsKey('propertyManager');

    state = state.copyWith(
      properties: effectiveProperties,
      selectedPropertyId: selectedProp,
      tenants: safeList(tenants, Tenant.fromJson)
          .map((t) => t.copyWith(propertyId: remapProperty(t.propertyId)))
          .toList(),
      payments: safeList(payments, Payment.fromJson)
          .map((p) => p.copyWith(propertyId: remapProperty(p.propertyId)))
          .toList(),
      expenses: safeList(expenses, Expense.fromJson)
          .map((e) => e.copyWith(propertyId: remapProperty(e.propertyId)))
          .toList(),
      workOrders: safeList(workOrders, WorkOrder.fromJson)
          .map((w) => w.copyWith(propertyId: remapProperty(w.propertyId)))
          .toList(),
      banks: safeList(banks, BankInfo.fromJson),
      zakat: safeList(zakat, ZakatTransaction.fromJson)
          .map((z) => z.copyWith(propertyId: remapProperty(z.propertyId)))
          .toList(),
      documents: safeList(documents, RentDoc.fromJson)
          .map((d) => d.copyWith(propertyId: remapProperty(d.propertyId)))
          .toList(),
      documentGroups: safeList(groups, DocumentGroup.fromJson),
      bankDeposits: safeList(deposits, BankDeposit.fromJson)
          .map((d) => d.copyWith(propertyId: remapProperty(d.propertyId)))
          .toList(),
      monthlyNotes: safeList(notes, MonthlyNote.fromJson)
          .map((n) => n.copyWith(propertyId: remapProperty(n.propertyId)))
          .toList(),
      expenseCategories: DefaultData.normalizedExpenseCategories(
        expCats.isEmpty
            ? state.expenseCategories
            : safeList(expCats, ExpenseCategory.fromJson),
      ),
      documentCategories: DefaultData.normalizedDocumentCategories(
        docCats.isEmpty
            ? state.documentCategories
            : safeList(docCats, DocumentCategory.fromJson),
      ),
      zakatCategories: DefaultData.normalizedZakatCategories(
        zakCats.isEmpty
            ? state.zakatCategories
            : safeList(zakCats, ZakatCategory.fromJson),
      ),
      predefinedDescriptions: descs,
      propertyManager: importedManager,
      clearManager: managerKeyPresent && importedManager == null,
      preferences:
          single('preferences', AppPreferences.fromJson) ?? state.preferences,
      selectedCurrency: curr,
    );

    // Reconcile and auto-deduplicate imported data before committing to disk
    final reconciled = await AutoDeduplicationService.reconcileAndPersist(
      payments: state.payments,
      expenses: state.expenses,
      documents: state.documents,
      expenseCategories: state.expenseCategories,
      tenantById: {for (final t in state.tenants) t.id: t},
    );
    state = state.copyWith(
      payments: reconciled.payments,
      expenses: reconciled.expenses,
      documents: reconciled.documents,
      expenseCategories: reconciled.expenseCategories,
    );

    await _persist();

    // A deliberate full "Restore & Replace" overrides local deletion markers:
    // lift tombstones for every record that was restored so future Drive
    // merges don't filter them straight back out.
    if (mode == 'replace') {
      final restoredIds = <String>{
        for (final p in state.properties) p.id,
        for (final t in state.tenants) t.id,
        for (final p in state.payments) p.id,
        for (final e in state.expenses) e.id,
        for (final w in state.workOrders) w.id,
        for (final b in state.banks) b.id,
        for (final z in state.zakat) z.id,
        for (final d in state.documents) d.id,
        for (final g in state.documentGroups) g.id,
        for (final dep in state.bankDeposits) dep.id,
        for (final n in state.monthlyNotes) n.id,
        for (final c in state.expenseCategories) c.id,
        for (final c in state.documentCategories) c.id,
        for (final c in state.zakatCategories) c.id,
      };
      await AppStorage.clearDeletedIds(restoredIds);
    }
    return summary;
  }

  /// Cancels the debounce and writes the current state immediately. Call this
  /// when the app is backgrounded so the last edit is not lost.
  Future<void> flush() async {
    _saveTimer?.cancel();
    await _persist();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    unawaited(_persist().catchError((_) {}));
    super.dispose();
  }
}

final appDataProvider = StateNotifierProvider<AppDataNotifier, AppDataState>(
  (ref) => AppDataNotifier(),
);
