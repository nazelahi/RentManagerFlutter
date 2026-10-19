import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Handles physical media backup and restoration (avatars, receipt photos, document PDFs).
/// Encodes referenced local media files into a portable base64 dictionary `__media__`
/// on export and unpacks them back into persistent app storage on import/restore.
class AppMediaBackup {
  AppMediaBackup._();

  static const String mediaKey = '__media__';
  static const String mediaPrefix = '@media:';

  /// Returns the persistent directory where app media files are permanently stored.
  static Future<Directory> getMediaDir() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('${appDocDir.path}/app_media');
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }
      return mediaDir;
    } catch (_) {
      // Fallback for headless unit test environments
      final tmp = Directory('${Directory.systemTemp.path}/rentmanager_app_media');
      if (!tmp.existsSync()) tmp.createSync(recursive: true);
      return tmp;
    }
  }

  /// Copies a newly picked temporary file (from image_picker or file_picker cache)
  /// into the permanent `app_media` directory to prevent OS cache eviction.
  static Future<String> persistPickedFile(String tempPath, {String? category}) async {
    try {
      if (tempPath.startsWith('http://') || tempPath.startsWith('https://')) {
        return tempPath;
      }
      final file = File(tempPath);
      if (!await file.exists()) return tempPath;

      final mediaDir = await getMediaDir();
      // If the file is already inside app_media, no need to duplicate
      if (file.path.startsWith(mediaDir.path)) {
        return file.path;
      }

      final rawName = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : 'media';
      String ext = '';
      final dotIdx = rawName.lastIndexOf('.');
      if (dotIdx != -1 && dotIdx < rawName.length - 1) {
        final candidateExt = rawName.substring(dotIdx).toLowerCase();
        if (RegExp(r'^\.[a-zA-Z0-9]{1,6}$').hasMatch(candidateExt)) {
          ext = candidateExt;
        }
      }
      final cleanCat = (category != null && category.isNotEmpty) ? '${category}_' : 'media_';
      final hash = tempPath.hashCode.abs();
      final newName = '$cleanCat${DateTime.now().millisecondsSinceEpoch}_$hash$ext';
      final targetFile = File('${mediaDir.path}/$newName');

      await file.copy(targetFile.path);
      return targetFile.path;
    } catch (e) {
      debugPrint('Error persisting picked file: $e');
      return tempPath;
    }
  }

  /// Traverses exported app data map and embeds all referenced local files into a `__media__` dictionary.
  /// Also replaces local file paths with `@media:<fileName>` references so they can be re-mapped on restore.
  static Future<Map<String, dynamic>> packMedia(Map<String, dynamic> data) async {
    final out = Map<String, dynamic>.from(data);
    final mediaMap = <String, dynamic>{};
    final pathMapping = <String, String>{}; // originalPath -> mediaId

    Future<String?> processPath(String? path, {String? tag}) async {
      if (path == null || path.isEmpty) return null;
      if (path.startsWith('http://') || path.startsWith('https://')) return path;
      if (path.startsWith(mediaPrefix)) return path;

      if (pathMapping.containsKey(path)) {
        return '$mediaPrefix${pathMapping[path]}';
      }

      try {
        final f = File(path);
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          if (bytes.isNotEmpty) {
            final rawName = f.uri.pathSegments.isNotEmpty
                ? f.uri.pathSegments.last
                : 'file';
            String ext = '';
            final dotIdx = rawName.lastIndexOf('.');
            if (dotIdx != -1 && dotIdx < rawName.length - 1) {
              final candidateExt = rawName.substring(dotIdx).toLowerCase();
              if (RegExp(r'^\.[a-zA-Z0-9]{1,6}$').hasMatch(candidateExt)) {
                ext = candidateExt;
              }
            }
            final prefix = (tag != null && tag.isNotEmpty) ? '${tag}_' : 'media_';
            final pathHash = path.hashCode.abs();
            final mediaId = '$prefix${pathHash}_${bytes.length}$ext';
            mediaMap[mediaId] = {
              'originalPath': path,
              'fileName': mediaId,
              'size': bytes.length,
              'data': base64Encode(bytes),
            };
            pathMapping[path] = mediaId;
            return '$mediaPrefix$mediaId';
          }
        }
      } catch (e) {
        debugPrint('Media pack note for $path: $e');
      }
      return path;
    }

    // 1. Property Manager
    if (out['propertyManager'] is Map) {
      final pm = Map<String, dynamic>.from(out['propertyManager'] as Map);
      if (pm['avatar'] is String) {
        pm['avatar'] = await processPath(pm['avatar'] as String, tag: 'avatar_pm');
      }
      if (pm['propertyPictures'] is List) {
        final pics = <String>[];
        for (final p in pm['propertyPictures'] as List) {
          final processed = await processPath(p?.toString(), tag: 'prop_pic');
          if (processed != null) pics.add(processed);
        }
        pm['propertyPictures'] = pics;
      }
      out['propertyManager'] = pm;
    }

    // 2. Tenants
    if (out['tenants'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final tRaw in out['tenants'] as List) {
        if (tRaw is Map) {
          final t = Map<String, dynamic>.from(tRaw);
          if (t['avatar'] is String) {
            t['avatar'] = await processPath(t['avatar'] as String, tag: 'avatar_tenant');
          }
          if (t['documents'] is List) {
            final docs = <Map<String, dynamic>>[];
            for (final dRaw in t['documents'] as List) {
              if (dRaw is Map) {
                final d = Map<String, dynamic>.from(dRaw);
                if (d['uri'] is String) {
                  d['uri'] = await processPath(d['uri'] as String, tag: 'tenant_doc');
                }
                docs.add(d);
              }
            }
            t['documents'] = docs;
          }
          list.add(t);
        }
      }
      out['tenants'] = list;
    }

    // 2b. Banks (logos are local file paths)
    if (out['banks'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final bRaw in out['banks'] as List) {
        if (bRaw is Map) {
          final b = Map<String, dynamic>.from(bRaw);
          if (b['logo'] is String) {
            b['logo'] = await processPath(b['logo'] as String, tag: 'bank_logo');
          }
          list.add(b);
        }
      }
      out['banks'] = list;
    }

    // 3. Expenses
    if (out['expenses'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final eRaw in out['expenses'] as List) {
        if (eRaw is Map) {
          final e = Map<String, dynamic>.from(eRaw);
          if (e['receipt'] is String) {
            e['receipt'] = await processPath(e['receipt'] as String, tag: 'expense_receipt');
          }
          if (e['receiptFiles'] is List) {
            final rFiles = <String>[];
            for (final r in e['receiptFiles'] as List) {
              final processed = await processPath(r?.toString(), tag: 'expense_receipt');
              if (processed != null) rFiles.add(processed);
            }
            e['receiptFiles'] = rFiles;
          }
          list.add(e);
        }
      }
      out['expenses'] = list;
    }

    // 4. Documents (RentDoc)
    if (out['documents'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final dRaw in out['documents'] as List) {
        if (dRaw is Map) {
          final d = Map<String, dynamic>.from(dRaw);
          if (d['fileUri'] is String) {
            d['fileUri'] = await processPath(d['fileUri'] as String, tag: 'doc');
          }
          if (d['thumbnailUri'] is String) {
            d['thumbnailUri'] = await processPath(d['thumbnailUri'] as String, tag: 'doc_thumb');
          }
          list.add(d);
        }
      }
      out['documents'] = list;
    }

    // 5. Work Orders
    if (out['workOrders'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final wRaw in out['workOrders'] as List) {
        if (wRaw is Map) {
          final w = Map<String, dynamic>.from(wRaw);
          if (w['receipt'] is String) {
            w['receipt'] = await processPath(w['receipt'] as String, tag: 'wo_receipt');
          }
          list.add(w);
        }
      }
      out['workOrders'] = list;
    }

    // 6. Bank Deposits
    if (out['bankDeposits'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final bRaw in out['bankDeposits'] as List) {
        if (bRaw is Map) {
          final b = Map<String, dynamic>.from(bRaw);
          if (b['receiptImage'] is String) {
            b['receiptImage'] = await processPath(b['receiptImage'] as String, tag: 'bank_receipt');
          }
          list.add(b);
        }
      }
      out['bankDeposits'] = list;
    }

    // 7. Zakat
    if (out['zakat'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final zRaw in out['zakat'] as List) {
        if (zRaw is Map) {
          final z = Map<String, dynamic>.from(zRaw);
          if (z['receiptUri'] is String) {
            z['receiptUri'] = await processPath(z['receiptUri'] as String, tag: 'zakat_receipt');
          }
          list.add(z);
        }
      }
      out['zakat'] = list;
    }

    // 8. Recently Deleted Docs
    if (out['recentlyDeletedDocs'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final dRaw in out['recentlyDeletedDocs'] as List) {
        if (dRaw is Map) {
          final d = Map<String, dynamic>.from(dRaw);
          if (d['fileUri'] is String) {
            d['fileUri'] = await processPath(d['fileUri'] as String, tag: 'del_doc');
          }
          if (d['thumbnailUri'] is String) {
            d['thumbnailUri'] = await processPath(d['thumbnailUri'] as String, tag: 'del_doc_thumb');
          }
          list.add(d);
        }
      }
      out['recentlyDeletedDocs'] = list;
    }

    out[mediaKey] = mediaMap;
    out['__media_count__'] = mediaMap.length;
    out['__backup_format__'] = 'rm_with_media_v2';
    return out;
  }

  /// Unpacks all embedded media files from `data['__media__']` into the local `app_media`
  /// directory, and rewrites all path references in `data` to the newly restored local paths.
  static Future<Map<String, dynamic>> unpackMedia(Map<String, dynamic> data) async {
    final out = Map<String, dynamic>.from(data);
    final rawMedia = out[mediaKey];

    if (rawMedia is! Map || rawMedia.isEmpty) {
      return out;
    }

    final mediaDir = await getMediaDir();
    final tokenToLocalPath = <String, String>{};

    for (final entry in rawMedia.entries) {
      final mediaId = entry.key.toString();
      final item = entry.value;
      if (item is Map) {
        final b64 = item['data'] as String?;
        if (b64 != null && b64.isNotEmpty) {
          try {
            final bytes = base64Decode(b64);
            // Sanitize target filename so it never exceeds filesystem limits (max 80 chars)
            String diskName = mediaId;
            if (diskName.length > 80 || diskName.contains(RegExp(r'[/\\?%*:|"<>]'))) {
              String ext = '';
              final dotIdx = mediaId.lastIndexOf('.');
              if (dotIdx != -1 && dotIdx < mediaId.length - 1) {
                final candidateExt = mediaId.substring(dotIdx).toLowerCase();
                if (RegExp(r'^\.[a-zA-Z0-9]{1,6}$').hasMatch(candidateExt)) {
                  ext = candidateExt;
                }
              }
              final hash = mediaId.hashCode.abs();
              diskName = 'media_${hash}_${bytes.length}$ext';
            }

            final targetFile = File('${mediaDir.path}/$diskName');
            await targetFile.writeAsBytes(bytes);

            final localPath = targetFile.path;
            tokenToLocalPath['$mediaPrefix$mediaId'] = localPath;
            tokenToLocalPath[mediaId] = localPath;

            final orig = item['originalPath'] as String?;
            if (orig != null && orig.isNotEmpty) {
              tokenToLocalPath[orig] = localPath;
            }
          } catch (e) {
            debugPrint('Failed to unpack media $mediaId: $e');
          }
        }
      }
    }

    String? resolve(dynamic val) {
      if (val == null) return null;
      final str = val.toString();
      if (str.isEmpty) return str;
      return tokenToLocalPath[str] ?? str;
    }

    // 1. Property Manager
    if (out['propertyManager'] is Map) {
      final pm = Map<String, dynamic>.from(out['propertyManager'] as Map);
      if (pm['avatar'] != null) pm['avatar'] = resolve(pm['avatar']);
      if (pm['propertyPictures'] is List) {
        pm['propertyPictures'] = (pm['propertyPictures'] as List)
            .map((p) => resolve(p) ?? p.toString())
            .toList();
      }
      out['propertyManager'] = pm;
    }

    // 2. Tenants
    if (out['tenants'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final tRaw in out['tenants'] as List) {
        if (tRaw is Map) {
          final t = Map<String, dynamic>.from(tRaw);
          if (t['avatar'] != null) t['avatar'] = resolve(t['avatar']);
          if (t['documents'] is List) {
            final docs = <Map<String, dynamic>>[];
            for (final dRaw in t['documents'] as List) {
              if (dRaw is Map) {
                final d = Map<String, dynamic>.from(dRaw);
                if (d['uri'] != null) d['uri'] = resolve(d['uri']);
                docs.add(d);
              }
            }
            t['documents'] = docs;
          }
          list.add(t);
        }
      }
      out['tenants'] = list;
    }

    // 2b. Banks (logos are local file paths)
    if (out['banks'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final bRaw in out['banks'] as List) {
        if (bRaw is Map) {
          final b = Map<String, dynamic>.from(bRaw);
          if (b['logo'] != null) b['logo'] = resolve(b['logo']);
          list.add(b);
        }
      }
      out['banks'] = list;
    }

    // 3. Expenses
    if (out['expenses'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final eRaw in out['expenses'] as List) {
        if (eRaw is Map) {
          final e = Map<String, dynamic>.from(eRaw);
          if (e['receipt'] != null) e['receipt'] = resolve(e['receipt']);
          if (e['receiptFiles'] is List) {
            e['receiptFiles'] = (e['receiptFiles'] as List)
                .map((r) => resolve(r) ?? r.toString())
                .toList();
          }
          list.add(e);
        }
      }
      out['expenses'] = list;
    }

    // 4. Documents (RentDoc)
    if (out['documents'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final dRaw in out['documents'] as List) {
        if (dRaw is Map) {
          final d = Map<String, dynamic>.from(dRaw);
          if (d['fileUri'] != null) d['fileUri'] = resolve(d['fileUri']);
          if (d['thumbnailUri'] != null) d['thumbnailUri'] = resolve(d['thumbnailUri']);
          list.add(d);
        }
      }
      out['documents'] = list;
    }

    // 5. Work Orders
    if (out['workOrders'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final wRaw in out['workOrders'] as List) {
        if (wRaw is Map) {
          final w = Map<String, dynamic>.from(wRaw);
          if (w['receipt'] != null) w['receipt'] = resolve(w['receipt']);
          list.add(w);
        }
      }
      out['workOrders'] = list;
    }

    // 6. Bank Deposits
    if (out['bankDeposits'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final bRaw in out['bankDeposits'] as List) {
        if (bRaw is Map) {
          final b = Map<String, dynamic>.from(bRaw);
          if (b['receiptImage'] != null) b['receiptImage'] = resolve(b['receiptImage']);
          list.add(b);
        }
      }
      out['bankDeposits'] = list;
    }

    // 7. Zakat
    if (out['zakat'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final zRaw in out['zakat'] as List) {
        if (zRaw is Map) {
          final z = Map<String, dynamic>.from(zRaw);
          if (z['receiptUri'] != null) z['receiptUri'] = resolve(z['receiptUri']);
          list.add(z);
        }
      }
      out['zakat'] = list;
    }

    // 8. Recently Deleted Docs
    if (out['recentlyDeletedDocs'] is List) {
      final list = <Map<String, dynamic>>[];
      for (final dRaw in out['recentlyDeletedDocs'] as List) {
        if (dRaw is Map) {
          final d = Map<String, dynamic>.from(dRaw);
          if (d['fileUri'] != null) d['fileUri'] = resolve(d['fileUri']);
          if (d['thumbnailUri'] != null) d['thumbnailUri'] = resolve(d['thumbnailUri']);
          list.add(d);
        }
      }
      out['recentlyDeletedDocs'] = list;
    }

    // Remove raw base64 dictionary from root data so Hive box stays lean
    out.remove(mediaKey);
    return out;
  }
}
