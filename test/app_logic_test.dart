import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/models/models.dart';
import 'package:rentmanager/core/state/app_data.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:rentmanager/core/storage/app_media_backup.dart';
import 'package:rentmanager/core/widgets/media_widgets.dart';
import 'package:rentmanager/services/deep_linking.dart';
import 'package:rentmanager/services/drive_backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('DeepLinkBus (DeepLinkingService port)', () {
    test('maps screens to tab indices', () {
      expect(DeepLinkBus.tabIndexFor('rentmanager://overview'), 0);
      expect(DeepLinkBus.tabIndexFor('rentmanager://tenants'), 1);
      expect(DeepLinkBus.tabIndexFor('rentmanager://work'), 2);
      expect(DeepLinkBus.tabIndexFor('rentmanager://documents'), 3);
      expect(DeepLinkBus.tabIndexFor('rentmanager://reports'), 4);
      expect(DeepLinkBus.tabIndexFor('rentmanager://zakat'), 5);
      expect(DeepLinkBus.tabIndexFor('rentmanager://settings'), -1);
      expect(
          DeepLinkBus.tabIndexFor('rentmanager://tenants/add?id=1'), 1);
    });
    test('unknown links return null', () {
      expect(DeepLinkBus.tabIndexFor('rentmanager://nope'), isNull);
      expect(DeepLinkBus.tabIndexFor('https://example.com'), isNull);
    });
    test('create builds links', () {
      expect(DeepLinkBus.create('tenants'), 'rentmanager://tenants');
      expect(DeepLinkBus.create('work', {'id': '1'}),
          'rentmanager://work?id=1');
    });
  });

  group('Currency options (SettingsScreen port)', () {
    test('exact 10 currencies with BDT', () {
      expect(kCurrencyOptions.length, 10);
      expect(kCurrencyOptions.map((c) => c.code),
          containsAll(['USD', 'EUR', 'BDT', 'PKR', 'INR']));
      expect(kCurrencyOptions.map((c) => c.symbol), contains('৳'));
    });
  });

  group('Preferences biometric lock', () {
    test('defaults match Expo (lock off, zakat on)', () {
      final p = AppPreferences.fromJson({});
      expect(p.showZakat, isTrue);
      expect(p.biometricLock, isFalse);
    });
    test('round-trips through JSON', () {
      final p = AppPreferences(showZakat: false, biometricLock: true);
      final back = AppPreferences.fromJson(p.toJson());
      expect(back.showZakat, isFalse);
      expect(back.biometricLock, isTrue);
    });
  });

  group('Model JSON round-trips', () {
    test('tenant with documents', () {
      final t = Tenant(
        id: 't1', name: 'Karim', unit: 'A-1', phone: '01',
        email: 'k@x.com', rentAmount: 5000, joinDate: '2024-01-01',
        documents: [
          TenantDocument(id: 'd1', name: 'NID', uri: '/a.jpg',
              type: 'id-card', uploadedAt: '2024-01-02'),
        ],
      );
      final back = Tenant.fromJson(t.toJson());
      expect(back.name, 'Karim');
      expect(back.documents.length, 1);
      expect(back.documents.first.type, 'id-card');
    });
    test('payment statuses preserved', () {
      for (final st in ['paid', 'pending', 'overdue', 'partial']) {
        final p = Payment(id: 'p', tenantId: 't', amount: 100,
            status: st);
        expect(Payment.fromJson(p.toJson()).status, st);
      }
    });
    test('work order costs preserved', () {
      final w = WorkOrder(id: 'w', title: 'Fix', description: 'x',
          assignedTo: 'M', createdAt: '2024-01-01',
          dueDate: '2024-01-08', productPrice: 200,
          workerCost: 150, receipt: '/r.jpg');
      final back = WorkOrder.fromJson(w.toJson());
      expect(back.productPrice, 200);
      expect(back.workerCost, 150);
      expect(back.receipt, '/r.jpg');
    });
    test('document file fields preserved', () {
      final d = RentDoc(id: 'd', title: 'Lease', type: 'lease',
          fileName: 'l.pdf', fileSize: '1 MB', uploadedBy: 'Owner',
          uploadedDate: '2024-01-01', fileUri: '/l.pdf',
          isPdf: true, pageCount: 3, tags: ['2024']);
      final back = RentDoc.fromJson(d.toJson());
      expect(back.isPdf, isTrue);
      expect(back.fileUri, '/l.pdf');
      expect(back.tags, ['2024']);
    });
    test('expense receipt + month preserved', () {
      final e = Expense(id: 'e', category: 'Repairs',
          description: 'Tap', amount: 50, date: '2024-05-01',
          expenseForMonth: '2024-05', receipt: '/r.jpg');
      final back = Expense.fromJson(e.toJson());
      expect(back.receipt, '/r.jpg');
      expect(back.expenseForMonth, '2024-05');
    });
  });

  group('Import engine (ImportPreviewModal port)', () {
    test('replace overwrites, merge respects strategies',
        () async {
      SharedPreferences.setMockInitialValues({});
      final dir =
          await Directory.systemTemp.createTemp('hive-import');
      await AppStorage.initWithPath(dir.path);
      final n = AppDataNotifier();
      n.upsertTenant(Tenant(
          id: 't1', name: 'Old', unit: 'U1', phone: '',
          email: '', rentAmount: 1, joinDate: ''));
      final incoming = {
        'tenants': [
          Tenant(
              id: 't1', name: 'New', unit: 'U1', phone: '',
              email: '', rentAmount: 2, joinDate: '')
              .toJson(),
          Tenant(
              id: 't2', name: 'Added', unit: 'U2',
              phone: '', email: '', rentAmount: 3,
              joinDate: '')
              .toJson(),
        ],
      };
      // Merge with skip: t1 kept, t2 added.
      final sum1 = await n.applyImport(incoming,
          mode: 'merge', strategies: {'tenants': 'skip'});
      expect(n.state.tenants.length, 2);
      expect(
          n.state.tenants
              .firstWhere((t) => t.id == 't1')
              .name,
          'Old');
      expect(sum1['tenants']!['added'], 1);
      expect(sum1['tenants']!['skipped'], 1);
      // Merge with update: t1 overwritten.
      final sum2 = await n.applyImport(incoming,
          mode: 'merge', strategies: {'tenants': 'update'});
      expect(
          n.state.tenants
              .firstWhere((t) => t.id == 't1')
              .name,
          'New');
      expect(sum2['tenants']!['updated'], 2);
      // Replace: only incoming remain.
      n.upsertTenant(Tenant(
          id: 't9', name: 'Gone', unit: 'U9', phone: '',
          email: '', rentAmount: 9, joinDate: ''));
      await n.applyImport(incoming, mode: 'replace');
      expect(
          n.state.tenants.any((t) => t.id == 't9'),
          isFalse);
      expect(n.state.tenants.length, 2);
      n.dispose();
      await AppStorage.close();
    });
  });

  group('AppStorage export/import', () {    test('round-trips lists with duplicate-ID guard', () async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('hive-test');
      await AppStorage.initWithPath(dir.path);
      await AppStorage.writeList('tenants', [
        Tenant(id: 't1', name: 'A', unit: 'U1', phone: '', email: '',
                rentAmount: 1, joinDate: '')
            .toJson(),
        Tenant(id: 't1', name: 'DUPE', unit: 'U9', phone: '',
                email: '', rentAmount: 9, joinDate: '')
            .toJson(),
      ]);
      final read =
          AppStorage.readList('tenants', Tenant.fromJson);
      expect(read.length, 1);
      expect(read.first.name, 'A');

       final exported = await AppStorage.exportAll();
      expect(exported['tenants'], isA<List>());
      await AppStorage.clearAll();
      expect(AppStorage.readList('tenants', Tenant.fromJson),
          isEmpty);
      await AppStorage.importAll(exported);
      expect(AppStorage.readList('tenants', Tenant.fromJson).length,
          1);
      await AppStorage.close();
    });

    test('importAll restores polymorphic preferences without TypeError', () async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('hive-test-prefs');
      await AppStorage.initWithPath(dir.path);

      final complexBackup = {
        'tenants': [
          {'id': 't2', 'name': 'Bob', 'unit': 'B2', 'phone': '', 'email': '', 'rentAmount': 500, 'joinDate': ''}
        ],
        '__prefs__': {
          'is_dark_mode': true,
          'notification_count': 5,
          'tax_rate': 0.15,
          'search_history': ['unit 1', 'tenant bob'],
          'user_currency': 'USD',
        },
      };

      await AppStorage.importAll(complexBackup);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('is_dark_mode'), isTrue);
      expect(prefs.getInt('notification_count'), 5);
      expect(prefs.getDouble('tax_rate'), 0.15);
      expect(prefs.getStringList('search_history'), ['unit 1', 'tenant bob']);
      expect(prefs.getString('user_currency'), 'USD');

      final tenants = AppStorage.readList('tenants', Tenant.fromJson);
      expect(tenants.length, 1);
      expect(tenants.first.name, 'Bob');

      await AppStorage.close();
    });

    test('applyImport handles polymorphic types, replaces and merges cleanly', () async {
      SharedPreferences.setMockInitialValues({});
      final dir = await Directory.systemTemp.createTemp('hive-test-import');
      await AppStorage.initWithPath(dir.path);

      final notifier = AppDataNotifier();

      // Seed initial state with 1 tenant
      notifier.upsertTenant(Tenant(
        id: 't1',
        name: 'Existing Tenant',
        unit: '101',
        phone: '123',
        email: 'test@example.com',
        rentAmount: 1000.0,
        joinDate: '2026-01-01',
      ));

      // Backup with string amount numbers, BankDeposit with numeric amount, and new tenant
      final backup = {
        'tenants': [
          {
            'id': 't1',
            'name': 'Updated Tenant',
            'unit': '101',
            'phone': '999',
            'email': 'updated@example.com',
            'rentAmount': '1250.0', // String representation of number
            'joinDate': '2026-01-01',
          },
          {
            'id': 't2',
            'name': 'New Tenant',
            'unit': '102',
            'phone': '456',
            'email': 'new@example.com',
            'rentAmount': 1500, // int representation of double
            'joinDate': '2026-02-01',
          },
        ],
        'bankDeposits': [
          {
            'id': 'd1',
            'bankId': 'b1',
            'bankName': 'City Bank',
            'amount': 2500, // int instead of String
            'depositDate': '2026-02-01',
            'description': 'Rent deposit',
            'status': 'completed',
          }
        ],
        'selectedCurrency': 'EUR',
      };

      // Test merge mode with 'update' strategy
      final summary = await notifier.applyImport(
        backup,
        mode: 'merge',
        strategies: {'tenants': 'update'},
      );

      expect(summary['tenants']?['added'], 1);
      expect(summary['tenants']?['updated'], 1);
      expect(notifier.state.tenants.length, 2);
      expect(notifier.state.tenants.firstWhere((t) => t.id == 't1').name, 'Updated Tenant');
      expect(notifier.state.tenants.firstWhere((t) => t.id == 't1').rentAmount, 1250.0);
      expect(notifier.state.bankDeposits.length, 1);
      expect(notifier.state.bankDeposits.first.amount, 2500.0);
      expect(notifier.state.selectedCurrency, 'EUR');

      await AppStorage.close();
    });
  });

  group('DriveBackupService', () {
    test('formatFileSize converts bytes correctly', () {
      expect(DriveBackupService.formatFileSize(500), '500 B');
      expect(DriveBackupService.formatFileSize(2048), '2.0 KB');
      expect(DriveBackupService.formatFileSize(1572864), '1.50 MB');
    });

    test('DriveBackupFile models file metadata', () {
      const file = DriveBackupFile(
        id: 'drive_123',
        name: 'RentManager_Backup_2026-10-15.json',
        created: '2026-10-15T12:00:00Z',
        size: '12.5 KB',
        accountEmail: 'user@example.com',
      );
      expect(file.id, 'drive_123');
      expect(file.name, contains('RentManager_Backup'));
      expect(file.accountEmail, 'user@example.com');
    });

    test('DriveBackupService constants and flags', () {
      expect(DriveBackupService.folderName, 'RentManager_Backups');
      expect(DriveBackupService.filePrefix, 'RentManager_Backup_');
      expect(DriveBackupService.driveAvailable, isTrue);
      expect(DriveBackupService.driveMode, 'cloud+local');
    });
  });

  group('AppMediaBackup media packing and restoration', () {
    test('packs and unpacks media files, remapping local paths cleanly', () async {
      final tmpDir = await Directory.systemTemp.createTemp('media_test_src');
      final avatarFile = File('${tmpDir.path}/avatar.jpg');
      await avatarFile.writeAsString('FAKE_AVATAR_IMAGE_BYTES');

      final docFile = File('${tmpDir.path}/contract.pdf');
      await docFile.writeAsString('FAKE_PDF_DOCUMENT_BYTES');

      final initialData = {
        'tenants': [
          {
            'id': 't1',
            'name': 'Test Tenant',
            'avatar': avatarFile.path,
            'documents': [
              {
                'id': 'd1',
                'name': 'Lease',
                'uri': docFile.path,
              }
            ],
          }
        ],
        'expenses': [
          {
            'id': 'e1',
            'description': 'Repair',
            'receipt': avatarFile.path,
          }
        ],
      };

      // 1. Pack media
      final packed = await AppMediaBackup.packMedia(initialData);
      expect(packed.containsKey(AppMediaBackup.mediaKey), isTrue);
      expect(packed['__media_count__'], 2);

      final mediaMap = packed[AppMediaBackup.mediaKey] as Map<String, dynamic>;
      expect(mediaMap.length, 2);

      // Verify that references were converted to tokens
      final packedTenant = (packed['tenants'] as List).first as Map<String, dynamic>;
      expect(packedTenant['avatar'], startsWith(AppMediaBackup.mediaPrefix));

      // 2. Unpack media into persistent media storage
      final unpacked = await AppMediaBackup.unpackMedia(packed);
      expect(unpacked.containsKey(AppMediaBackup.mediaKey), isFalse);

      final unpackedTenant = (unpacked['tenants'] as List).first as Map<String, dynamic>;
      final restoredAvatarPath = unpackedTenant['avatar'] as String;
      expect(restoredAvatarPath, isNot(startsWith(AppMediaBackup.mediaPrefix)));
      expect(File(restoredAvatarPath).existsSync(), isTrue);
      expect(await File(restoredAvatarPath).readAsString(), 'FAKE_AVATAR_IMAGE_BYTES');

      final unpackedDoc = (unpackedTenant['documents'] as List).first as Map<String, dynamic>;
      final restoredDocPath = unpackedDoc['uri'] as String;
      expect(File(restoredDocPath).existsSync(), isTrue);
      expect(await File(restoredDocPath).readAsString(), 'FAKE_PDF_DOCUMENT_BYTES');

      final unpackedExpense = (unpacked['expenses'] as List).first as Map<String, dynamic>;
      expect(unpackedExpense['receipt'], restoredAvatarPath);

      // Clean up temp source files
      try {
        await tmpDir.delete(recursive: true);
      } catch (_) {}
    });
  });

  group('Notification Preferences and Input Validation', () {
    test('notification preferences round-trip and toggle properly', () {
      final p = AppPreferences(
        notifRentDue: true,
        notifWorkOrder: true,
        notifExpense: false,
        notifMaintenance: false,
        notifDaily: true,
      );
      final json = p.toJson();
      final restored = AppPreferences.fromJson(json);

      expect(restored.notifRentDue, isTrue);
      expect(restored.notifWorkOrder, isTrue);
      expect(restored.notifExpense, isFalse);
      expect(restored.notifMaintenance, isFalse);
      expect(restored.notifDaily, isTrue);

      final toggled = restored.copyWith(
        notifRentDue: false,
        notifWorkOrder: false,
      );
      expect(toggled.notifRentDue, isFalse);
      expect(toggled.notifWorkOrder, isFalse);
    });

    test('rent amount validation correctly enforces positive numbers', () {
      bool isValidRent(String input) {
        final val = double.tryParse(input.trim());
        return val != null && val > 0;
      }

      expect(isValidRent('5000'), isTrue);
      expect(isValidRent(' 1200.50 '), isTrue);
      expect(isValidRent('0'), isFalse);
      expect(isValidRent('-100'), isFalse);
      expect(isValidRent('abc'), isFalse);
      expect(isValidRent(''), isFalse);
    });

    test('email validation correctly validates format when provided', () {
      final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

      expect(emailRegex.hasMatch('test@example.com'), isTrue);
      expect(emailRegex.hasMatch('user.name@tenant.org'), isTrue);
      expect(emailRegex.hasMatch('invalid-email'), isFalse);
      expect(emailRegex.hasMatch('test@'), isFalse);
      expect(emailRegex.hasMatch('@domain.com'), isFalse);
    });
  });
}
