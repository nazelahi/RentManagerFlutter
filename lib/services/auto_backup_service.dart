import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../core/state/app_data.dart';
import '../core/storage/app_storage.dart';

/// Port of the SettingsScreen auto-backup scheduler
/// (autoBackupEnabled / lastBackupTime / nextBackupTime + keep-3 rotation).
class AutoBackupService {
  static const _prefix = 'RentManager_AutoBackup_';

  static DateTime _nextDue(AppDataState s) {
    final last = DateTime.tryParse(s.preferences.lastBackup ?? '');
    final base = last ?? DateTime.now();
    final days = s.preferences.backupSchedule == 'monthly' ? 30 : 7;
    return base.add(Duration(days: days));
  }

  static String nextLabel(AppDataState s) {
    final n = _nextDue(s);
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  /// Called once after boot (mirrors handleAutoBackup on data changes).
  static Future<String?> runIfDue(WidgetRef ref) async {
    final s = ref.read(appDataProvider);
    if (!s.preferences.autoBackup) return null;
    final last = DateTime.tryParse(s.preferences.lastBackup ?? '');
    if (last != null &&
        DateTime.now().isBefore(_nextDue(s))) {
      return null;
    }
    return runNow(ref);
  }

  static Future<String?> runNow(WidgetRef ref) async {
    try {
      final data = await AppStorage.exportAll();
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file =
          File('${dir.path}/$_prefix$stamp.json');
      await file.writeAsString(jsonEncode(data));
      // Keep-3 rotation (ports pre-import rotation logic).
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.split('/').last.startsWith(_prefix))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final extra in files.skip(3)) {
        try {
          await extra.delete();
        } catch (_) {}
      }
      ref.read(appDataProvider.notifier).setPreferences(
            ref
                .read(appDataProvider)
                .preferences
                .copyWith(
                    lastBackup:
                        DateTime.now().toIso8601String()),
          );
      return file.path.split('/').last;
    } catch (_) {
      return null;
    }
  }

  static Future<List<File>> listLocal() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.split('/').last.startsWith(_prefix))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      return files;
    } catch (_) {
      return [];
    }
  }

  static Future<Map<String, dynamic>?> readLocal(
      File f) async {
    try {
      final raw = await f.readAsString();
      return Map<String, dynamic>.from(
          jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }
}
