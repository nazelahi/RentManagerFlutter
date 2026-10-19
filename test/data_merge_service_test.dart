import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/services/data_merge_service.dart';

void main() {
  group('DataMergeService 2-way sync tests', () {
    test('merges disjoint items from local and remote', () {
      final local = {
        StorageKeys.tenants: [
          {'id': 't1', 'name': 'Tenant 1', 'updatedAt': '2026-10-17T10:00:00Z'},
        ],
      };
      final remote = {
        StorageKeys.tenants: [
          {'id': 't2', 'name': 'Tenant 2', 'updatedAt': '2026-10-17T11:00:00Z'},
        ],
      };

      final result = DataMergeService.merge(local: local, remote: remote);

      final tenants = result.mergedData[StorageKeys.tenants] as List;
      expect(tenants.length, 2);
      final ids = tenants.map((e) => e['id']).toSet();
      expect(ids, containsAll(['t1', 't2']));
      expect(result.hasRemoteNewerData, isTrue);
      expect(result.hasLocalNewerData, isTrue);
    });

    test('remote newer update overwrites older local item', () {
      final local = {
        StorageKeys.expenses: [
          {
            'id': 'exp1',
            'description': 'Old Plumbing',
            'amount': 50.0,
            'updatedAt': '2026-10-17T09:00:00Z',
          },
        ],
      };
      final remote = {
        StorageKeys.expenses: [
          {
            'id': 'exp1',
            'description': 'Updated Plumbing Work',
            'amount': 85.0,
            'updatedAt': '2026-10-17T11:30:00Z',
          },
        ],
      };

      final result = DataMergeService.merge(local: local, remote: remote);
      final expenses = result.mergedData[StorageKeys.expenses] as List;
      expect(expenses.length, 1);
      expect(expenses.first['description'], 'Updated Plumbing Work');
      expect(expenses.first['amount'], 85.0);
      expect(result.hasRemoteNewerData, isTrue);
    });

    test('local newer update preserves local item over older remote item', () {
      final local = {
        StorageKeys.payments: [
          {
            'id': 'pay1',
            'amount': 1200.0,
            'status': 'paid',
            'updatedAt': '2026-10-17T12:00:00Z',
          },
        ],
      };
      final remote = {
        StorageKeys.payments: [
          {
            'id': 'pay1',
            'amount': 1200.0,
            'status': 'pending',
            'updatedAt': '2026-10-17T08:00:00Z',
          },
        ],
      };

      final result = DataMergeService.merge(local: local, remote: remote);
      final payments = result.mergedData[StorageKeys.payments] as List;
      expect(payments.length, 1);
      expect(payments.first['status'], 'paid');
      expect(result.hasLocalNewerData, isTrue);
    });

    test('prunes deleted records from both local and remote', () {
      final local = {
        StorageKeys.bankDeposits: [
          {'id': 'dep1', 'amount': '500', 'updatedAt': '2026-10-17T08:00:00Z'},
          {'id': 'dep2', 'amount': '1500', 'updatedAt': '2026-10-17T08:00:00Z'},
        ],
      };
      final remote = {
        StorageKeys.bankDeposits: [
          {'id': 'dep1', 'amount': '500', 'updatedAt': '2026-10-17T08:00:00Z'},
          {'id': 'dep3', 'amount': '2500', 'updatedAt': '2026-10-17T08:00:00Z'},
        ],
        StorageKeys.deletedRecordIds: ['dep1', 'dep3'],
      };

      final result = DataMergeService.merge(local: local, remote: remote);
      final deposits = result.mergedData[StorageKeys.bankDeposits] as List;
      expect(deposits.length, 1);
      expect(deposits.first['id'], 'dep2');
      expect(result.mergedDeletedIds, containsAll(['dep1', 'dep3']));
    });

    test('newer edit after deletion resurrects the record', () {
      final local = {
        StorageKeys.tenants: [
          {
            'id': 't1',
            'name': 'Updated after delete',
            'updatedAt': '2026-10-18T12:00:00Z',
          },
        ],
        StorageKeys.deletedRecordIds: {'t1': '2026-10-18T10:00:00Z'},
      };
      final remote = {
        StorageKeys.tenants: [
          {'id': 't1', 'name': 'Old copy', 'updatedAt': '2026-10-18T09:00:00Z'},
        ],
        StorageKeys.deletedRecordIds: {'t1': '2026-10-18T10:00:00Z'},
      };

      final result = DataMergeService.merge(local: local, remote: remote);
      final tenants = result.mergedData[StorageKeys.tenants] as List;
      final tombstones = result.mergedData[StorageKeys.deletedRecordIds] as Map;

      expect(tenants.length, 1);
      expect(tenants.first['name'], 'Updated after delete');
      expect(tombstones.containsKey('t1'), isFalse);
      expect(result.hasLocalNewerData, isTrue);
    });

    test('newer deletion wins over an older edit', () {
      final local = {
        StorageKeys.tenants: [
          {
            'id': 't1',
            'name': 'Stale edit',
            'updatedAt': '2026-10-18T09:00:00Z',
          },
        ],
      };
      final remote = {
        StorageKeys.tenants: [
          {
            'id': 't1',
            'name': 'Stale edit',
            'updatedAt': '2026-10-18T09:00:00Z',
          },
        ],
        StorageKeys.deletedRecordIds: {'t1': '2026-10-18T10:00:00Z'},
      };

      final result = DataMergeService.merge(local: local, remote: remote);
      final tenants = result.mergedData[StorageKeys.tenants] as List;

      expect(tenants, isEmpty);
      expect(result.mergedDeletedIds, contains('t1'));
      expect(result.hasRemoteNewerData, isTrue);
    });

    test('legacy tombstone list is dated with the remote snapshot time', () {
      final local = {
        StorageKeys.expenses: [
          {
            'id': 'e1',
            'description': 'Edited locally',
            'updatedAt': '2026-10-18T09:00:00Z',
          },
        ],
      };
      final remote = {
        StorageKeys.expenses: [
          {
            'id': 'e1',
            'description': 'Old snapshot',
            'updatedAt': '2026-10-18T08:00:00Z',
          },
        ],
        StorageKeys.deletedRecordIds: ['e1'],
      };

      final result = DataMergeService.merge(
        local: local,
        remote: remote,
        remoteSnapshotTime: DateTime.parse('2026-10-18T10:00:00Z'),
      );
      final expenses = result.mergedData[StorageKeys.expenses] as List;

      expect(expenses, isEmpty);
      expect(result.mergedDeletedIds, contains('e1'));
    });
  });
}
