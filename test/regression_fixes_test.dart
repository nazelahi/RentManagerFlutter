import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/state/app_data.dart';
import 'package:rentmanager/core/storage/app_storage.dart';

Map<String, dynamic> _property(String id, String name) => {
      'id': id,
      'name': name,
      'address': '$name address',
      'createdAt': '2026-01-01T00:00:00.000',
    };

Map<String, dynamic> _tenant(String id, String name, String propertyId) => {
      'id': id,
      'name': name,
      'unit': '101',
      'phone': '123',
      'email': '$id@example.com',
      'rentAmount': 1000,
      'status': 'active',
      'joinDate': '2026-01-01',
      'propertyId': propertyId,
    };

void main() {
  late Directory tempDir;
  late AppDataNotifier notifier;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rentmanager_regression');
    await AppStorage.initWithPath(tempDir.path);
    notifier = AppDataNotifier();
  });

  tearDown(() async {
    notifier.dispose();
    await AppStorage.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('applyImport restores properties and keeps record property ids', () async {
    await notifier.applyImport({
      'properties': [_property('p1', 'Alpha'), _property('p2', 'Beta')],
      'selectedPropertyId': 'p2',
      'tenants': [_tenant('t1', 'Tenant One', 'p2')],
      'payments': [
        {
          'id': 'pay1',
          'tenantId': 't1',
          'amount': 1000,
          'status': 'paid',
          'propertyId': 'p2',
          'paidForMonth': '2026-10',
        }
      ],
    }, mode: 'replace');

    expect(notifier.state.properties.length, 2);
    expect(notifier.state.selectedPropertyId, 'p2');
    expect(notifier.state.tenants.single.propertyId, 'p2');
    expect(notifier.state.payments.single.propertyId, 'p2');
  });

  test('deleteProperty reassigns dependent records to a remaining property',
      () async {
    await notifier.applyImport({
      'properties': [_property('p1', 'Alpha'), _property('p2', 'Beta')],
      'selectedPropertyId': 'p2',
      'tenants': [_tenant('t1', 'Tenant One', 'p2')],
      'payments': [
        {
          'id': 'pay1',
          'tenantId': 't1',
          'amount': 1000,
          'status': 'paid',
          'propertyId': 'p2',
          'paidForMonth': '2026-10',
        }
      ],
      'expenses': [
        {
          'id': 'e1',
          'category': 'Repair',
          'description': 'Fix',
          'amount': 50,
          'date': '2026-10-01',
          'propertyId': 'p2',
        }
      ],
    }, mode: 'replace');

    notifier.deleteProperty('p2');

    expect(notifier.state.properties.map((p) => p.id), ['p1']);
    expect(notifier.state.tenants.single.propertyId, 'p1');
    expect(notifier.state.payments.single.propertyId, 'p1');
    expect(notifier.state.expenses.single.propertyId, 'p1');
  });

  test('manager profile creates/renames the default property', () {
    notifier.setPropertyManager(PropertyManager(
      id: 'm1',
      name: 'Manager',
      email: 'm@example.com',
      phone: '123',
      address: '12 Main Street',
      propertyName: 'Sunset Villa',
      ownerName: 'Owner',
      propertyPictures: const [],
    ));

    expect(notifier.state.properties.length, 1);
    expect(notifier.state.properties.single.name, 'Sunset Villa');
    expect(notifier.state.properties.single.address, '12 Main Street');
    expect(notifier.state.selectedPropertyId, notifier.state.properties.single.id);
  });

  test('manager profile renames an existing auto-created property', () async {
    await notifier.applyImport({
      'properties': [_property('prop-default', 'Primary Property')],
      'propertyManager': {
        'id': 'm1',
        'name': 'Manager',
        'email': 'm@example.com',
        'phone': '123',
        'address': '12 Main Street',
        'propertyName': 'Sunset Villa',
      },
    }, mode: 'replace');

    notifier.setPropertyManager(PropertyManager(
      id: 'm1',
      name: 'Manager',
      email: 'm@example.com',
      phone: '123',
      address: '12 Main Street',
      propertyName: 'Sunset Villa',
      ownerName: 'Owner',
      propertyPictures: const [],
    ));

    expect(notifier.state.properties.single.name, 'Sunset Villa');
  });

  test('editing a tenant keeps its existing property assignment', () async {
    await notifier.applyImport({
      'properties': [_property('p1', 'Alpha'), _property('p2', 'Beta')],
      'selectedPropertyId': 'p1',
      'tenants': [_tenant('t1', 'Tenant One', 'p2')],
    }, mode: 'replace');

    final existing = notifier.state.tenants.single;
    notifier.upsertTenant(Tenant(
      id: existing.id,
      name: 'Renamed',
      unit: existing.unit,
      phone: existing.phone,
      email: existing.email,
      rentAmount: existing.rentAmount,
      joinDate: existing.joinDate,
    ));

    expect(notifier.state.tenants.single.name, 'Renamed');
    expect(notifier.state.tenants.single.propertyId, 'p2');
  });

  test('deleteTenant does not remove same-name documents in another property',
      () async {
    await notifier.applyImport({
      'properties': [_property('p1', 'Alpha'), _property('p2', 'Beta')],
      'selectedPropertyId': 'p1',
      'tenants': [
        _tenant('t1', 'Same Name', 'p1'),
        _tenant('t2', 'Same Name', 'p2'),
      ],
      'documents': [
        {
          'id': 'd1',
          'title': 'Lease',
          'type': 'lease',
          'fileName': 'a.pdf',
          'fileSize': '1 MB',
          'uploadedBy': 'System',
          'uploadedDate': '2026-01-01',
          'tenant': 'Same Name',
          'unit': '101',
          'propertyId': 'p1',
        },
        {
          'id': 'd2',
          'title': 'Lease',
          'type': 'lease',
          'fileName': 'b.pdf',
          'fileSize': '1 MB',
          'uploadedBy': 'System',
          'uploadedDate': '2026-01-01',
          'tenant': 'Same Name',
          'unit': '101',
          'propertyId': 'p2',
        },
      ],
    }, mode: 'replace');

    notifier.deleteTenant('t1');

    expect(notifier.state.documents.map((d) => d.id), ['d2']);
  });

  test('WorkOrder.copyWith can clear a stale completion timestamp', () {
    final order = WorkOrder(
      id: 'w1',
      title: 'Fix',
      description: 'Fix it',
      assignedTo: 'Tech',
      createdAt: '2026-10-01',
      dueDate: '2026-10-05',
      completedAt: '2026-10-04',
    );

    final reopened = order.copyWith(
      status: 'in-progress',
      clearCompletedAt: true,
    );

    expect(reopened.completedAt, isNull);
  });

  test('ZakatTransaction normalizes legacy type casing', () {
    final txn = ZakatTransaction.fromJson({
      'id': 'z1',
      'type': ' Outflow ',
      'amount': 10,
      'date': '2026-10-01',
    });
    expect(txn.type, 'outflow');
  });

  test('Property.fromJson derives a stable id when the field is missing', () {
    final raw = {'name': 'Alpha', 'address': 'A street'};
    expect(Property.fromJson(raw).id, Property.fromJson(raw).id);
  });

  test('AppStorage.readList preserves legacy records without ids', () async {
    await AppStorage.writeList(StorageKeys.tenants, [
      {'name': 'Legacy One', 'unit': '1'},
      {'name': 'Legacy Two', 'unit': '2'},
    ]);

    final tenants =
        AppStorage.readList(StorageKeys.tenants, Tenant.fromJson);
    expect(tenants.length, 2);
  });
}
