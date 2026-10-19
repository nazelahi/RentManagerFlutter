import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rentmanager/core/storage/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('rm-tombstones');
    await AppStorage.initWithPath(tempDir.path);
  });

  tearDown(() async {
    await AppStorage.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('import keeps a newer local deletion tombstone', () async {
    await AppStorage.trackDeletedId('t1');

    await AppStorage.importAll({
      StorageKeys.tenants: [
        {
          'id': 't1',
          'name': 'Deleted on this device',
          'updatedAt': '2000-01-01T00:00:00Z',
        },
        {
          'id': 't2',
          'name': 'Still active',
          'updatedAt': '2000-01-01T00:00:00Z',
        },
      ],
    });

    final tenants = AppStorage.readList(StorageKeys.tenants, (m) => m);
    expect(tenants.map((e) => e['id']), ['t2']);
    expect(AppStorage.getDeletedIds(), contains('t1'));
  });

  test('import resurrects a record edited after its deletion', () async {
    await AppStorage.trackDeletedId('t1');
    final tombstone = AppStorage.getDeletedTombstones()['t1']!;

    await AppStorage.importAll({
      StorageKeys.tenants: [
        {
          'id': 't1',
          'name': 'Edited on another device',
          'updatedAt': tombstone
              .add(const Duration(minutes: 1))
              .toUtc()
              .toIso8601String(),
        },
      ],
    });

    final tenants = AppStorage.readList(StorageKeys.tenants, (m) => m);
    expect(tenants.length, 1);
    expect(tenants.first['name'], 'Edited on another device');
    expect(AppStorage.getDeletedIds().contains('t1'), isFalse);
  });
}
