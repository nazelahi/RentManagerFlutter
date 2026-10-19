import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/services/auto_deduplication_service.dart';
import 'package:rentmanager/services/data_merge_service.dart';

void main() {
  group('AutoDeduplicationService Tests', () {
    test('retires redundant pending payment when paid payment exists for same month', () {
      final payments = [
        Payment(
          id: 'pay_paid_1',
          tenantId: 't1',
          paidForMonth: '2026-10',
          paidDate: '2026-10-05',
          amount: 1500.0,
          status: 'paid',
        ),
        Payment(
          id: 'pay_pending_1',
          tenantId: 't1',
          paidForMonth: '2026-10',
          dueDate: '2026-10-01',
          amount: 1500.0,
          status: 'pending',
        ),
      ];

      final result = AutoDeduplicationService.reconcilePayments(payments);

      expect(result.retiredIds, contains('pay_pending_1'));
      expect(result.retiredIds, isNot(contains('pay_paid_1')));
      expect(result.cleaned.length, 1);
      expect(result.cleaned.first.id, 'pay_paid_1');
      expect(result.retiredIds.isNotEmpty, isTrue);
    });

    test(
      'preserves legitimate multiple paid installment payments in same month',
      () {
        final payments = [
          Payment(
            id: 'pay_paid_pt1',
            tenantId: 't1',
            paidForMonth: '2026-10',
            paidDate: '2026-10-05',
            amount: 800.0,
            status: 'paid',
          ),
          Payment(
            id: 'pay_paid_pt2',
            tenantId: 't1',
            paidForMonth: '2026-10',
            paidDate: '2026-10-15',
            amount: 700.0,
            status: 'paid',
          ),
          Payment(
            id: 'pay_pending_ghost',
            tenantId: 't1',
            paidForMonth: '2026-10',
            dueDate: '2026-10-01',
            amount: 1500.0,
            status: 'pending',
          ),
        ];

        final result = AutoDeduplicationService.reconcilePayments(payments);

        expect(result.retiredIds, contains('pay_pending_ghost'));
        expect(result.cleaned.length, 2);
        expect(
          result.cleaned.map((p) => p.id),
          containsAll(['pay_paid_pt1', 'pay_paid_pt2']),
        );
      },
    );

    test('deduplicates duplicate pending sync artifacts, keeping the canonical one matching rentAmount', () {
      final tenant1 = Tenant(
        id: 't1',
        name: 'Jane Doe',
        unit: '101',
        phone: '1234567890',
        email: 'jane@example.com',
        rentAmount: 1600.0,
        joinDate: '2026-01-01',
      );

      final payments = [
        Payment(
          id: 'pay_pend_old',
          tenantId: 't1',
          paidForMonth: '2026-10',
          amount: 1500.0, // Stale amount doesn't match tenant rent
          status: 'pending',
        ),
        Payment(
          id: 'pay_pend_canon',
          tenantId: 't1',
          paidForMonth: '2026-10',
          amount: 1600.0, // Matches tenant rent amount
          status: 'pending',
        ),
      ];

      final result = AutoDeduplicationService.reconcilePayments(
        payments,
        tenantById: {'t1': tenant1},
      );

      expect(result.retiredIds, contains('pay_pend_old'));
      expect(result.cleaned.length, 1);
      expect(result.cleaned.first.id, 'pay_pend_canon');
      expect(result.cleaned.first.amount, 1600.0);
    });

    test('preserves payments across different months', () {
      final payments = [
        Payment(
          id: 'pay_oct',
          tenantId: 't1',
          paidForMonth: '2026-10',
          amount: 1500.0,
          status: 'pending',
        ),
        Payment(
          id: 'pay_nov',
          tenantId: 't1',
          paidForMonth: '2026-11',
          amount: 1500.0,
          status: 'pending',
        ),
      ];

      final result = AutoDeduplicationService.reconcilePayments(payments);

      expect(result.retiredIds, isEmpty);
      expect(result.cleaned.length, 2);
    });

    test('reconciles duplicate recurring expenses in same month', () {
      final expenses = [
        Expense(
          id: 'exp1',
          category: 'Utilities',
          description: 'Electricity Bill',
          amount: 120.0,
          date: '2026-10-05',
        ),
        Expense(
          id: 'exp1_dup',
          category: 'Utilities',
          description: 'Electricity Bill',
          amount: 120.0,
          date: '2026-10-05',
        ),
        Expense(
          id: 'exp2',
          category: 'Maintenance',
          description: 'Plumbing',
          amount: 120.0,
          date: '2026-10-05',
        ),
      ];

      final result = AutoDeduplicationService.reconcileExpenses(expenses);

      expect(result.retiredIds.length, 1);
      expect(result.cleaned.length, 2);
      expect(
        result.cleaned.map((e) => e.description),
        containsAll(['Electricity Bill', 'Plumbing']),
      );
    });

    test('reconciles duplicate tenant documents, keeping the best record with valid URI', () {
      final docs = [
        RentDoc(
          id: 'doc_old_ghost',
          title: 'National ID',
          type: 'id',
          fileName: 'tenant_National ID',
          fileSize: 'Unknown',
          uploadedBy: 'System',
          uploadedDate: '2026-10-01T08:00:00Z',
          tenant: 'Jobbar Miah',
          fileUri: '', // Missing URI
          tags: ['tenant-document', 'id'],
        ),
        RentDoc(
          id: 'doc_canonical',
          title: 'National ID',
          type: 'id',
          fileName: 'tenant_National ID',
          fileSize: '1.2 MB',
          uploadedBy: 'System',
          uploadedDate: '2026-10-02T10:00:00Z',
          tenant: 'Jobbar Miah',
          fileUri: '/documents/jobbar_nid.jpg', // Valid URI
          tags: ['tenant-document', 'id'],
        ),
        RentDoc(
          id: 'doc_other',
          title: 'Lease Agreement',
          type: 'contract',
          fileName: 'lease.pdf',
          fileSize: '2.5 MB',
          uploadedBy: 'System',
          uploadedDate: '2026-10-02T11:00:00Z',
          tenant: 'Jobbar Miah',
          fileUri: '/documents/lease.pdf',
          tags: ['tenant-document', 'contract'],
        ),
      ];

      final result = AutoDeduplicationService.reconcileDocuments(docs);

      expect(result.retiredIds, contains('doc_old_ghost'));
      expect(result.retiredIds, isNot(contains('doc_canonical')));
      expect(result.retiredIds, isNot(contains('doc_other')));
      expect(result.cleaned.length, 2);
      expect(
        result.cleaned.map((d) => d.id),
        containsAll(['doc_canonical', 'doc_other']),
      );
    });

    test('DataMergeService transparently reconciles duplicates and propagates retired IDs', () {
      final local = {
        StorageKeys.payments: [
          {
            'id': 'p_paid',
            'tenantId': 't1',
            'paidForMonth': '2026-10',
            'paidDate': '2026-10-05',
            'amount': 1500.0,
            'status': 'paid',
            'updatedAt': '2026-10-05T12:00:00Z',
          },
        ],
        StorageKeys.documents: [
          {
            'id': 'doc_1',
            'title': 'Passport',
            'type': 'id',
            'fileName': 'passport.jpg',
            'fileSize': '1 MB',
            'uploadedBy': 'System',
            'uploadedDate': '2026-10-05T12:00:00Z',
            'tenant': 'Furnished',
            'fileUri': '/docs/passport.jpg',
            'tags': ['tenant-document'],
          },
        ],
      };
      final remote = {
        StorageKeys.payments: [
          {
            'id': 'p_pending_dup',
            'tenantId': 't1',
            'paidForMonth': '2026-10',
            'dueDate': '2026-10-01',
            'amount': 1500.0,
            'status': 'pending',
            'updatedAt': '2026-10-01T10:00:00Z',
          },
        ],
        StorageKeys.documents: [
          {
            'id': 'doc_1_dup',
            'title': 'Passport',
            'type': 'id',
            'fileName': 'passport.jpg',
            'fileSize': 'Unknown',
            'uploadedBy': 'System',
            'uploadedDate': '2026-10-01T10:00:00Z',
            'tenant': 'Furnished',
            'fileUri': '',
            'tags': ['tenant-document'],
          },
        ],
      };

      final mergeResult = DataMergeService.merge(local: local, remote: remote);

      final mergedPayments =
          mergeResult.mergedData[StorageKeys.payments] as List;
      final mergedDocs = mergeResult.mergedData[StorageKeys.documents] as List;
      final mergedDeletedIds =
          mergeResult.mergedData[StorageKeys.deletedRecordIds] as Map;

      expect(mergedPayments.length, 1);
      expect(mergedPayments.first['id'], 'p_paid');
      expect(mergedDocs.length, 1);
      expect(mergedDocs.first['id'], 'doc_1');
      expect(
        mergedDeletedIds.keys,
        containsAll(['p_pending_dup', 'doc_1_dup']),
      );
      expect(
        mergeResult.hasLocalNewerData,
        isTrue,
      ); // Ensures clean reconciled state syncs to cloud
    });

    test('reconciles duplicate expense categories and merges descriptions', () {
      final cats = [
        ExpenseCategory(
          id: 'cat_1',
          name: 'Utilities',
          description: 'Utilities expenses',
          color: '#4CAF50',
          icon: 'flash',
          createdAt: '2026-01-01',
          updatedAt: '2026-01-01',
          suggestedDescriptions: ['Electric bill'],
        ),
        ExpenseCategory(
          id: 'cat_1_dup',
          name: ' utilities ', // duplicate with different spacing and case
          description: 'Power bills',
          color: '#2196F3',
          icon: 'water',
          createdAt: '2026-02-01',
          updatedAt: '2026-02-01',
          suggestedDescriptions: ['Water bill'],
        ),
        ExpenseCategory(
          id: 'cat_2',
          name: 'Maintenance',
          description: 'Maintenance expenses',
          color: '#FF9800',
          icon: 'build',
          createdAt: '2026-01-01',
          updatedAt: '2026-01-01',
        ),
      ];

      final result = AutoDeduplicationService.reconcileExpenseCategories(cats);

      expect(result.cleaned.length, 2);
      expect(result.retiredIds, contains('cat_1_dup'));
      final utilities = result.cleaned.firstWhere(
        (c) => c.name.toLowerCase() == 'utilities',
      );
      expect(
        utilities.suggestedDescriptions,
        containsAll(['Electric bill', 'Water bill']),
      );
    });
  });
}
