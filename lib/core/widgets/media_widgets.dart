import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../storage/app_media_backup.dart';
import '../theme/app_colors.dart';
import 'common.dart';

/// Media picking — port of expo-image-picker + expo-document-picker +
/// imageCompression usage across tenant avatars, receipts, documents.
class MediaPicker {
  static final _images = ImagePicker();

  /// Picks multiple gallery images — ports handleMultiplePhotoUpload.
  static Future<List<String>> pickMultipleImages() async {
    final isDesktop =
        Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    if (isDesktop) {
      try {
        final files = await FilePicker.pickFiles(
          type: FileType.image,
          dialogTitle: 'Select Images / Photos',
        );
        final results = <String>[];
        for (final f in files) {
          if (f.path != null) {
            final saved = await AppMediaBackup.persistPickedFile(f.path!,
                category: 'photo');
            results.add(saved);
          }
        }
        return results;
      } catch (e) {
        debugPrint('FilePicker pickMultipleImages error: $e');
      }
    }
    try {
      final xs = await _images.pickMultiImage(
          maxWidth: 1600, imageQuality: 85);
      final results = <String>[];
      for (final x in xs) {
        final saved = await AppMediaBackup.persistPickedFile(x.path, category: 'photo');
        results.add(saved);
      }
      return results;
    } catch (_) {
      try {
        final files = await FilePicker.pickFiles(
          type: FileType.image,
          dialogTitle: 'Select Images / Photos',
        );
        final results = <String>[];
        for (final f in files) {
          if (f.path != null) {
            final saved = await AppMediaBackup.persistPickedFile(f.path!,
                category: 'photo');
            results.add(saved);
          }
        }
        return results;
      } catch (_) {}
      return [];
    }
  }

  static String fileSizeOf(String path) {
    try {
      final bytes = File(path).lengthSync();
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) {
        return '${(bytes / 1024).toStringAsFixed(1)} KB';
      }
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } catch (_) {
      return '—';
    }
  }

  /// Returns a local file path, or null if cancelled.
  static Future<String?> pickImage(BuildContext context) async {
    final isDesktop = !kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    if (isDesktop) {
      try {
        final f = await FilePicker.pickFile(
          type: FileType.image,
          dialogTitle: 'Select Profile Picture / Avatar',
        );
        if (f?.path != null) {
          return await AppMediaBackup.persistPickedFile(f!.path!,
              category: 'avatar');
        }
        return null;
      } catch (e) {
        debugPrint('FilePicker error: $e');
      }
    }

    if (!context.mounted) return null;

    final source = await showAdaptiveModalSheet<ImageSource>(
      context: context,
      builder: (ctx) => AppModalSheet(
        title: 'Select Photo Source',
        icon: Icons.photo_camera_outlined,
        iconColor: AppColors.primary,
        size: SheetSize.compact,
        scrollable: false,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        body: Column(
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera_outlined,
                  color: AppColors.iconSecondary),
              title: Text('Take photo',
                  style: TextStyle(
                      color: AppColors.text, fontWeight: FontWeight.w500)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
                  color: AppColors.iconSecondary),
              title: Text('Choose from gallery',
                  style: TextStyle(
                      color: AppColors.text, fontWeight: FontWeight.w500)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    try {
      final x = await _images.pickImage(
          source: source, maxWidth: 1280, imageQuality: 80);
      if (x == null) return null;
      return await AppMediaBackup.persistPickedFile(x.path, category: 'avatar');
    } catch (_) {
      try {
        final f = await FilePicker.pickFile(
          type: FileType.image,
          dialogTitle: 'Select Profile Picture / Avatar',
        );
        if (f?.path != null) {
          return await AppMediaBackup.persistPickedFile(f!.path!,
              category: 'avatar');
        }
      } catch (_) {}
      if (context.mounted) {
        showAppToast(
          context,
          'Unable to access camera or photos. Please check app permissions.',
          isError: true,
        );
      }
      return null;
    }
  }

  /// Returns (path, isPdf) for a document pick (camera/gallery/files).
  static Future<PickedDoc?> pickDocument(BuildContext context) async {
    final isDesktop = !kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    if (isDesktop) {
      try {
        final f = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const [
            'pdf',
            'jpg',
            'jpeg',
            'png',
            'doc',
            'docx'
          ],
          dialogTitle: 'Select Document (PDF, Image, Doc)',
        );
        if (f?.path == null) return null;
        final ext = (f!.extension ?? '').toLowerCase();
        final persistentPath = await AppMediaBackup.persistPickedFile(
          f.path!,
          category: 'doc',
        );
        return PickedDoc(
          path: persistentPath,
          name: f.name,
          isPdf: ext == 'pdf',
        );
      } catch (e) {
        debugPrint('Desktop pickDocument error: $e');
        if (context.mounted) {
          showAppToast(
            context,
            'Unable to select document. Please check permissions.',
            isError: true,
          );
        }
        return null;
      }
    }

    final choice = await showAdaptiveModalSheet<String>(
      context: context,
      builder: (ctx) => AppModalSheet(
        title: 'Select Document Source',
        icon: Icons.upload_file_outlined,
        iconColor: AppColors.primary,
        size: SheetSize.compact,
        scrollable: false,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
        body: Column(
          children: [
            ListTile(
              leading: Icon(Icons.photo_camera_outlined,
                  color: AppColors.iconSecondary),
              title: Text('Take photo',
                  style: TextStyle(
                      color: AppColors.text, fontWeight: FontWeight.w500)),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined,
                  color: AppColors.iconSecondary),
              title: Text('Photo from gallery',
                  style: TextStyle(
                      color: AppColors.text, fontWeight: FontWeight.w500)),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: Icon(Icons.picture_as_pdf,
                  color: AppColors.iconSecondary),
              title: Text('PDF / file',
                  style: TextStyle(
                      color: AppColors.text, fontWeight: FontWeight.w500)),
              onTap: () => Navigator.pop(ctx, 'file'),
            ),
          ],
        ),
      ),
    );
    if (choice == null) return null;
    try {
      if (choice == 'file') {
        final f = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const [
            'pdf',
            'jpg',
            'jpeg',
            'png',
            'doc',
            'docx'
          ],
        );
        if (f?.path == null) return null;
        final ext = (f!.extension ?? '').toLowerCase();
        final persistentPath = await AppMediaBackup.persistPickedFile(f.path!, category: 'doc');
        return PickedDoc(
            path: persistentPath, name: f.name, isPdf: ext == 'pdf');
      }
      final x = await _images.pickImage(
          source: choice == 'camera'
              ? ImageSource.camera
              : ImageSource.gallery,
          maxWidth: 1600,
          imageQuality: 85);
      if (x == null) return null;
      final persistentPath = await AppMediaBackup.persistPickedFile(x.path, category: 'doc_photo');
      return PickedDoc(
          path: persistentPath, name: x.name, isPdf: false);
    } catch (_) {
      if (context.mounted) {
        showAppToast(
          context,
          'Unable to select document or photo. Please check permissions.',
          isError: true,
        );
      }
      return null;
    }
  }
}

class PickedDoc {
  final String path;
  final String name;
  final bool isPdf;
  const PickedDoc(
      {required this.path, required this.name, required this.isPdf});
}

/// Opens a local file with the system viewer
/// (port of DocumentViewerModal file opening).
class MediaFiles {
  static Future<void> open(String path) async {
    try {
      if (path.startsWith('http')) return;
      final cleanPath =
          path.startsWith('file://') ? Uri.parse(path).toFilePath() : path;
      final f = File(cleanPath);
      if (await f.exists()) await OpenFilex.open(cleanPath);
    } catch (_) {}
  }

  /// Shares a local file (port of Sharing.shareAsync download/share bar).
  static Future<void> share(String path) async {
    try {
      if (path.startsWith('http')) return;
      final cleanPath =
          path.startsWith('file://') ? Uri.parse(path).toFilePath() : path;
      final f = File(cleanPath);
      if (await f.exists()) {
        await SharePlus.instance.share(ShareParams(files: [XFile(cleanPath)]));
      }
    } catch (_) {}
  }
}

/// Dark-themed date picker — port of CustomDatePicker/DatePickerModal.
Future<DateTime?> pickAppDate(
  BuildContext context, {
  DateTime? initial,
  DateTime? first,
  DateTime? last,
}) =>
    showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: first ?? DateTime(2000),
      lastDate: last ?? DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: AppColors.isDark
              ? const ColorScheme.dark(
                  primary: AppColors.primary,
                  surface: Color(0xFF0D2B2B),
                  onSurface: Colors.white,
                )
              : const ColorScheme.light(
                  primary: AppColors.primary,
                  surface: Colors.white,
                  onSurface: Color(0xFF142424),
                ),
          dialogTheme: DialogThemeData(
              backgroundColor: AppColors.sheetBackground),
        ),
        child: child!,
      ),
    );

/// Read-only date field row used inside bottom sheets.
class DateFieldRow extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  const DateFieldRow(
      {super.key,
      required this.label,
      required this.value,
      required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              InkWell(
                onTap: () async {
                  final d =
                      await pickAppDate(context, initial: value);
                  if (d != null) onChanged(d);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: AppColors.border),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 18,
                        color: AppColors.iconSecondary),
                    const SizedBox(width: 10),
                    Text(
                      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
                      style: TextStyle(
                          color: AppColors.text),
                    ),
                  ]),
                ),
              ),
            ]),
      );
}

/// Single attachment row with pick/remove — used for receipt fields.
class AttachmentRow extends StatelessWidget {
  final String label;
  final String? path;
  final VoidCallback onPick;
  final VoidCallback onClear;
  const AttachmentRow(
      {super.key,
      required this.label,
      required this.path,
      required this.onPick,
      required this.onClear});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(children: [
                  Icon(
                      path != null
                          ? Icons.attach_file
                          : Icons.attach_file_outlined,
                      color: AppColors.iconSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      path != null
                          ? path!.split('/').last
                          : 'No file attached',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: path != null
                              ? AppColors.text
                              : AppColors.textMuted,
                          fontSize: 13),
                    ),
                  ),
                  if (path != null)
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: AppColors.error),
                      onPressed: onClear,
                    ),
                  TextButton(
                      onPressed: onPick,
                      child: Text(path != null
                          ? 'Change'
                          : 'Attach')),
                ]),
              ),
            ]),
      );
}

/// Currency options — exact port of SettingsScreen currencyOptions.
class CurrencyOption {
  final String symbol;
  final String name;
  final String code;
  final String flag;
  const CurrencyOption(this.symbol, this.name, this.code, this.flag);
}

const kCurrencyOptions = [
  CurrencyOption('\$', 'US Dollar', 'USD', '🇺🇸'),
  CurrencyOption('€', 'Euro', 'EUR', '🇪🇺'),
  CurrencyOption('£', 'British Pound', 'GBP', '🇬🇧'),
  CurrencyOption('¥', 'Japanese Yen', 'JPY', '🇯🇵'),
  CurrencyOption('₹', 'Indian Rupee', 'INR', '🇮🇳'),
  CurrencyOption('₽', 'Russian Ruble', 'RUB', '🇷🇺'),
  CurrencyOption('₩', 'South Korean Won', 'KRW', '🇰🇷'),
  CurrencyOption('₪', 'Israeli Shekel', 'ILS', '🇮🇱'),
  CurrencyOption('₨', 'Pakistani Rupee', 'PKR', '🇵🇰'),
  CurrencyOption('৳', 'Bangladeshi Taka', 'BDT', '🇧🇩'),
];

Future<void> showCurrencySheet(
  BuildContext context, {
  required String current,
  required ValueChanged<String> onSelect,
}) {
  String q = '';
  return showAdaptiveModalSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        final list = kCurrencyOptions
            .where((c) =>
                q.isEmpty ||
                c.name.toLowerCase().contains(q.toLowerCase()) ||
                c.code.toLowerCase().contains(q.toLowerCase()) ||
                c.symbol.contains(q))
            .toList();
        return AppModalSheet(
          title: 'Select Currency',
          icon: Icons.payments_outlined,
          iconColor: const Color(0xFF4CAF50),
          size: SheetSize.standard,
          scrollable: false,
          body: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Search currencies...',
                  prefixIcon: Icon(Icons.search,
                      color: AppColors.iconSecondary),
                ),
                onChanged: (v) => setS(() => q = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: list.isEmpty
                    ? Center(
                        child: Text(
                            'No currencies found matching your search',
                            style: TextStyle(
                                color: AppColors.textSecondary)))
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final c = list[i];
                          final selected = c.symbol == current;
                          return ListTile(
                            leading: Text(c.flag,
                                style: const TextStyle(fontSize: 24)),
                            title: Text('${c.name} (${c.code})',
                                style: TextStyle(
                                    color: AppColors.text,
                                    fontWeight: FontWeight.w600)),
                            trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(c.symbol,
                                      style: TextStyle(
                                          fontSize: 18,
                                          color:
                                              AppColors.textSecondary)),
                                  if (selected)
                                    const Padding(
                                      padding:
                                          EdgeInsets.only(left: 8),
                                      child: Icon(Icons.check,
                                          color: AppColors.primary),
                                    ),
                                ]),
                            onTap: () {
                              onSelect(c.symbol);
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
