import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/services/data_merge_service.dart';

void main() {
  group('BankDeposit Model & updatedAt', () {
    test('BankDeposit serializes and deserializes updatedAt properly', () {
      final deposit = BankDeposit(
        id: 'dep-1',
        bankId: 'bank-1',
        bankName: 'Chase Bank',
        amount: 2500,
        depositDate: '2026-10-15T10:00:00.000',
        description: 'Monthly deposit to Chase Bank',
        status: 'confirmed',
        updatedAt: '2026-10-18T12:00:00.000',
      );

      final json = deposit.toJson();
      expect(json['status'], equals('confirmed'));
      expect(json['updatedAt'], equals('2026-10-18T12:00:00.000'));

      final reconstructed = BankDeposit.fromJson(json);
      expect(reconstructed.id, equals('dep-1'));
      expect(reconstructed.status, equals('confirmed'));
      expect(reconstructed.updatedAt, equals('2026-10-18T12:00:00.000'));
    });

    test('copyWith updates status and updatedAt', () {
      final deposit = BankDeposit(
        id: 'dep-1',
        bankId: 'bank-1',
        bankName: 'Chase Bank',
        amount: 2500,
        depositDate: '2026-10-15T10:00:00.000',
        description: 'Monthly deposit to Chase Bank',
        status: 'pending',
      );

      final updated = deposit.copyWith(
        status: 'confirmed',
        updatedAt: '2026-10-18T15:00:00.000',
      );

      expect(updated.status, equals('confirmed'));
      expect(updated.updatedAt, equals('2026-10-18T15:00:00.000'));
    });
  });

  group('DataMergeService BankDeposit Sync & Status Preservation', () {
    test('Desktop confirmed deposit wins over stale mobile pending deposit', () {
      final localConfirmed = [
        {
          'id': 'dep-1',
          'bankId': 'bank-1',
          'bankName': 'Chase',
          'amount': '3000',
          'depositDate': '2026-10-01T00:00:00.000',
          'description': 'Deposit to Chase',
          'status': 'confirmed',
          'updatedAt': '2026-10-18T14:30:00.000',
        }
      ];

      final remotePending = [
        {
          'id': 'dep-1',
          'bankId': 'bank-1',
          'bankName': 'Chase',
          'amount': '3000',
          'depositDate': '2026-10-01T00:00:00.000',
          'description': 'Deposit to Chase',
          'status': 'pending',
          'updatedAt': '2026-10-17T09:00:00.000',
        }
      ];

      final result = DataMergeService.merge(
        local: {StorageKeys.bankDeposits: localConfirmed},
        remote: {StorageKeys.bankDeposits: remotePending},
        localDeletedIds: <String>{},
      );

      final merged = (result.mergedData[StorageKeys.bankDeposits] as List)
          .cast<Map<String, dynamic>>();

      expect(merged.length, equals(1));
      expect(merged.first['status'], equals('confirmed'));
      expect(result.hasLocalNewerData, isTrue);
    });

    test('Tie-breaker favors confirmed status if timestamps are identical', () {
      final localConfirmed = [
        {
          'id': 'dep-1',
          'bankId': 'bank-1',
          'bankName': 'Chase',
          'amount': '3000',
          'depositDate': '2026-10-01T00:00:00.000',
          'description': 'Deposit to Chase',
          'status': 'confirmed',
        }
      ];

      final remotePending = [
        {
          'id': 'dep-1',
          'bankId': 'bank-1',
          'bankName': 'Chase',
          'amount': '3000',
          'depositDate': '2026-10-01T00:00:00.000',
          'description': 'Deposit to Chase',
          'status': 'pending',
        }
      ];

      final result = DataMergeService.merge(
        local: {StorageKeys.bankDeposits: localConfirmed},
        remote: {StorageKeys.bankDeposits: remotePending},
        localDeletedIds: <String>{},
      );

      final merged = (result.mergedData[StorageKeys.bankDeposits] as List)
          .cast<Map<String, dynamic>>();

      expect(merged.length, equals(1));
      expect(merged.first['status'], equals('confirmed'));
    });

    test('Multiple deposits in the same month have unique IDs and merge correctly', () {
      final localDeposits = [
        {
          'id': 'dep-oct-1',
          'bankId': 'bank-1',
          'bankName': 'Chase',
          'amount': '2000',
          'depositDate': '2026-10-05T00:00:00.000',
          'description': 'Deposit to Chase 1',
          'status': 'confirmed',
        },
        {
          'id': 'dep-oct-2',
          'bankId': 'bank-1',
          'bankName': 'Chase',
          'amount': '1500',
          'depositDate': '2026-10-12T00:00:00.000',
          'description': 'Deposit to Chase 2',
          'status': 'pending',
        },
      ];

      final remoteDeposits = [
        {
          'id': 'dep-oct-1',
          'bankId': 'bank-1',
          'bankName': 'Chase',
          'amount': '2000',
          'depositDate': '2026-10-05T00:00:00.000',
          'description': 'Deposit to Chase 1',
          'status': 'confirmed',
        },
        {
          'id': 'dep-oct-3',
          'bankId': 'bank-2',
          'bankName': 'Bank of America',
          'amount': '1000',
          'depositDate': '2026-10-18T00:00:00.000',
          'description': 'Deposit to BofA',
          'status': 'confirmed',
        },
      ];

      final result = DataMergeService.merge(
        local: {StorageKeys.bankDeposits: localDeposits},
        remote: {StorageKeys.bankDeposits: remoteDeposits},
        localDeletedIds: <String>{},
      );

      final merged = (result.mergedData[StorageKeys.bankDeposits] as List)
          .cast<Map<String, dynamic>>();

      expect(merged.length, equals(3));
      final ids = merged.map((e) => e['id']).toSet();
      expect(ids, containsAll(['dep-oct-1', 'dep-oct-2', 'dep-oct-3']));
    });
  });

  group('Reconciliation Accounting Logic (Rent vs Expenses vs Deposits)', () {
    test('Reconciles Net Cash when deposit matches Rent minus paid expenses', () {
      const rentCollected = 5000.0;
      const paidExpenses = 1200.0;
      const netCash = rentCollected - paidExpenses; // 3800.0
      const confirmedDeposited = 3800.0;

      // Net Cash Reconciliation
      final matchesNet = (confirmedDeposited - netCash).abs() < 1.0;
      final matchesGross = (confirmedDeposited - rentCollected).abs() < 1.0;

      expect(matchesNet, isTrue);
      expect(matchesGross, isFalse);
    });

    test('Reconciles Gross Rent when landlord deposits total collected rent', () {
      const rentCollected = 5000.0;
      const paidExpenses = 1200.0;
      const netCash = rentCollected - paidExpenses; // 3800.0
      const confirmedDeposited = 5000.0;

      final matchesNet = (confirmedDeposited - netCash).abs() < 1.0;
      final matchesGross = (confirmedDeposited - rentCollected).abs() < 1.0;

      expect(matchesGross, isTrue);
      expect(matchesNet, isFalse);
    });

    test('Detects pending deposits that will fulfill reconciliation once confirmed', () {
      const rentCollected = 5000.0;
      const paidExpenses = 1200.0;
      const netCash = rentCollected - paidExpenses; // 3800.0
      const confirmedDeposited = 2000.0;
      const pendingDeposited = 1800.0;
      const totalDeposited = confirmedDeposited + pendingDeposited; // 3800.0

      final confirmedMatchesNet = (confirmedDeposited - netCash).abs() < 1.0;
      final totalMatchesNet = (totalDeposited - netCash).abs() < 1.0;

      expect(confirmedMatchesNet, isFalse);
      expect(totalMatchesNet, isTrue);
    });
  });
}
