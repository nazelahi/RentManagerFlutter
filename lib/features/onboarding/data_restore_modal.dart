import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/common.dart';
import '../../services/auto_backup_service.dart';
import '../../services/drive_backup_service.dart';
import 'setup_sheet.dart';

/// Port of `src/components/DataRestoreModal.tsx` — Google Drive / file picker
/// / local backup / auto backup restore options.
///
/// Returns the restored data map, or `null` when the user skips.
Future<Map<String, dynamic>?> showDataRestoreSheet(
    BuildContext context) async {
  var loading = true;
  var restoring = false;
  String? selected;
  String? localBackup;
  String? autoBackup;
  var signedIn = false;
  List<DriveBackupFile> backups = const [];
  var driveLoading = false;
  final localFiles = <File>[];
  var localLoading = false;

  final result = await showSetupSheet<Map<String, dynamic>>(
    context: context,
    builder: (ctx, height) => StatefulBuilder(
      builder: (ctx, setS) {
        // Kick off option loading once.
        if (loading && !localLoading) {
          localLoading = true;
          Future(() async {
            String? manual;
            try {
              final prefs = await SharedPreferences.getInstance();
              manual = prefs.getString('manual_backup_data');
            } catch (_) {}
            final files = await AutoBackupService.listLocal();
            Map<String, dynamic>? auto;
            if (files.isNotEmpty) {
              final data = await AutoBackupService.readLocal(files.first);
              if (data != null) auto = data;
            }

            // Check if already signed in to Google Drive
            List<DriveBackupFile> driveBackups = [];
            bool isDriveSignedIn = DriveBackupService.isSignedIn;
            if (isDriveSignedIn) {
              try {
                driveBackups = await DriveBackupService.listBackups();
              } catch (_) {}
            }

            if (!ctx.mounted) return;
            setS(() {
              localFiles
                ..clear()
                ..addAll(files);
              localBackup = manual;
              autoBackup = auto == null ? null : jsonEncode(auto);
              if (isDriveSignedIn) {
                signedIn = true;
                backups = driveBackups;
              }
              loading = false;
            });
          });
        }

        final options = <_BackupOption>[
          _BackupOption(
            id: 'google_drive',
            title: 'Google Drive',
            description: signedIn && backups.isNotEmpty
                ? 'Latest: ${backups.first.name} (${backups.first.size})'
                : 'Restore from your Google Drive backups',
            icon: Ionicons.cloud,
            type: 'google_drive',
            available: signedIn && backups.isNotEmpty,
          ),
          const _BackupOption(
            id: 'file_picker',
            title: 'Choose File',
            description: 'Select a backup file from your device',
            icon: Ionicons.document,
            type: 'file_picker',
            available: true,
          ),
          _BackupOption(
            id: 'local_backup',
            title: 'Local Backup',
            description: 'Restore from manually saved backup file',
            icon: Ionicons.folder,
            type: 'local',
            available: localBackup != null,
          ),
          _BackupOption(
            id: 'auto_backup',
            title: 'Auto Backup',
            description: 'Restore from automatic backup data',
            icon: Ionicons.refresh,
            type: 'auto_backup',
            available: autoBackup != null,
          ),
        ];

        Future<void> restore() async {
          if (selected == null) return;
          final option =
              options.where((o) => o.id == selected).firstOrNull;
          if (option == null || !option.available) return;
          setS(() => restoring = true);
          try {
            Map<String, dynamic>? restored;
            switch (option.type) {
              case 'google_drive':
                if (backups.isNotEmpty) {
                  final data = await DriveBackupService.download(
                      backups.first.id);
                  if (data != null) {
                    await AppStorage.importAll(data);
                    restored = data;
                  }
                }
                break;
              case 'local':
                if (localBackup != null) {
                  final parsed = Map<String, dynamic>.from(
                      jsonDecode(localBackup!) as Map);
                  await AppStorage.importAll(parsed);
                  restored = parsed;
                }
                break;
              case 'file_picker':
                final f = await FilePicker.pickFile(
                  type: FileType.custom,
                  allowedExtensions: const ['json'],
                );
                if (f?.path == null) {
                  setS(() => restoring = false);
                  return;
                }
                final raw = await File(f!.path!).readAsString();
                final parsed =
                    Map<String, dynamic>.from(jsonDecode(raw) as Map);
                await AppStorage.importAll(parsed);
                restored = parsed;
                break;
              case 'auto_backup':
                if (autoBackup != null) {
                  final parsed = Map<String, dynamic>.from(
                      jsonDecode(autoBackup!) as Map);
                  await AppStorage.importAll(parsed);
                  restored = parsed;
                }
                break;
            }
            if (!ctx.mounted) return;
            if (restored != null) {
              Navigator.pop(ctx, restored);
            } else {
              setS(() => restoring = false);
            }
          } catch (e) {
            if (!ctx.mounted) return;
            setS(() => restoring = false);
            showAppToast(ctx, 'Failed to restore data: $e', isError: true);
          }
        }

        Future<void> signInDrive() async {
          setS(() => driveLoading = true);
          try {
            final account = await DriveBackupService.signIn();
            if (account == null) {
              if (ctx.mounted) setS(() => driveLoading = false);
              return;
            }
            final list = await DriveBackupService.listBackups();
            if (!ctx.mounted) return;
            setS(() {
              signedIn = true;
              backups = list;
              driveLoading = false;
              if (list.isNotEmpty) {
                selected = 'google_drive';
              }
            });
          } catch (e) {
            if (!ctx.mounted) return;
            setS(() => driveLoading = false);
            final s = '$e';
            if (!s.contains('cancel')) {
              showAppToast(ctx, 'Failed to sign in: $e', isError: true);
            }
          }
        }

        return SetupSheet(
          icon: Ionicons.cloudDownload,
          iconColor: const Color(0xFF9C27B0),
          title: 'Restore Data',
          onClose: () => Navigator.pop(ctx),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 12, 0, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Text(
                    "Choose where you'd like to restore your data from:",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondary,
                        height: 1.4),
                  ),
                ),
                const SizedBox(height: 24),
                if (loading)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        const CircularProgressIndicator(color: AppColors.primary),
                        const SizedBox(height: 16),
                        Text('Loading backup options...',
                            style: TextStyle(
                                fontSize: 16,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  )
                else ...[
                  for (final o in options)
                    _optionCard(
                      o,
                      selected == o.id,
                      restoring,
                      onTap: () => setS(() => selected = o.id),
                    ),
                  if (!signedIn) ...[
                    const SizedBox(height: 16),
                    Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4285F4),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: driveLoading ? null : signInDrive,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Ionicons.logoGoogle,
                                  size: 20, color: Colors.white),
                              const SizedBox(width: 8),
                              Text(
                                driveLoading
                                    ? 'Signing in...'
                                    : 'Sign in to Google Drive',
                                style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          footer: Container(
            decoration: const BoxDecoration(
              border: Border(
                  top: BorderSide(
                      color: Color.fromRGBO(255, 255, 255, 0.08))),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Row(children: [
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    side: const BorderSide(
                        color: Color.fromRGBO(255, 255, 255, 0.2)),
                    backgroundColor:
                        const Color.fromRGBO(255, 255, 255, 0.05),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: restoring ? null : () => Navigator.pop(ctx),
                  child: Text('Skip',
                      style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: Material(
                    color: selected == null || restoring
                        ? const Color(0xFFCCCCCC)
                        : AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: selected == null || restoring ? null : restore,
                      child: Center(
                        child: restoring
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Ionicons.download,
                                      size: 20, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('Restore Data',
                                      style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    ),
  );
  return result;
}

class _BackupOption {
  final String id, title, description, type;
  final IconData icon;
  final bool available;
  const _BackupOption({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.type,
    required this.available,
  });
}

Widget _optionCard(_BackupOption o, bool selected, bool restoring,
    {required VoidCallback onTap}) {
  final disabled = !o.available || restoring;
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? const Color.fromRGBO(76, 175, 80, 0.1)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
              width: selected ? 2 : 1),
        ),
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: o.available ? AppColors.primary : const Color(0xFF9E9E9E),
                shape: BoxShape.circle,
              ),
              child: Icon(o.icon, size: 24, color: Colors.white),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(o.title,
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: disabled ? const Color(0xFF999999) : AppColors.text)),
                  const SizedBox(height: 4),
                  Text(o.description,
                      style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: disabled
                              ? const Color(0xFF999999)
                              : AppColors.textSecondary)),
                  if (o.type == 'google_drive' && !o.available)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                          'Sign in to Google Drive to access backups',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFFF9800),
                              fontStyle: FontStyle.italic)),
                    ),
                ],
              ),
            ),
            if (selected)
              const Icon(Ionicons.checkmarkCircle,
                  size: 24, color: AppColors.primary),
          ]),
        ),
      ),
    ),
  );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
