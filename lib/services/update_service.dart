import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/app_info.dart';

enum UpdateCheckStatus { upToDate, updateAvailable, notConfigured, error }

class UpdateCheckResult {
  final UpdateCheckStatus status;
  final String currentVersion;
  final String? latestVersion;
  final int currentBuild;
  final int? latestBuild;
  final String? releaseNotes;
  final String? downloadUrl;
  final String? error;

  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    required this.currentBuild,
    this.latestVersion,
    this.latestBuild,
    this.releaseNotes,
    this.downloadUrl,
    this.error,
  });

  bool get updateAvailable => status == UpdateCheckStatus.updateAvailable;
  bool get hasDownload => downloadUrl != null && downloadUrl!.isNotEmpty;
}

/// Checks a JSON update manifest for a newer release.
///
/// Configure the manifest URL at build time:
/// `flutter run --dart-define=UPDATE_MANIFEST_URL=https://example.com/update.json`
///
/// Expected JSON (extra fields are ignored):
/// {
///   "version": "1.0.7",
///   "build": 2,
///   "releaseNotes": "What's new...",
///   "downloadUrl": "https://example.com/RentManager-1.0.7.dmg",
///   "downloads": {"macos": "...", "windows": "...", "android": "..."}
/// }
class UpdateService {
  UpdateService._();

  static const String manifestUrl = String.fromEnvironment(
    'UPDATE_MANIFEST_URL',
  );

  static String get platformKey {
    if (kIsWeb) return 'web';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  static Future<UpdateCheckResult> checkForUpdates({
    http.Client? client,
    String? overrideManifestUrl,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final url = (overrideManifestUrl ?? manifestUrl).trim();
    final current = UpdateCheckResult(
      status: UpdateCheckStatus.notConfigured,
      currentVersion: kAppVersion,
      currentBuild: kAppBuildNumber,
    );

    if (url.isEmpty) return current;

    final ownedClient = client == null;
    final httpClient = client ?? http.Client();
    try {
      final response = await httpClient
          .get(
            Uri.parse(url),
            headers: const {
              'Accept': 'application/json',
              'Cache-Control': 'no-cache',
            },
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.error,
          currentVersion: kAppVersion,
          currentBuild: kAppBuildNumber,
          error: 'Update server returned HTTP ${response.statusCode}.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.error,
          currentVersion: kAppVersion,
          currentBuild: kAppBuildNumber,
          error: 'Update manifest is not a JSON object.',
        );
      }

      final manifest = Map<String, dynamic>.from(decoded);
      final latestVersion = '${manifest['version'] ?? ''}'.trim();
      if (latestVersion.isEmpty) {
        return UpdateCheckResult(
          status: UpdateCheckStatus.error,
          currentVersion: kAppVersion,
          currentBuild: kAppBuildNumber,
          error: 'Update manifest is missing a version.',
        );
      }

      final latestBuild = int.tryParse(
        '${manifest['build'] ?? ''}'.replaceAll('+', ''),
      );
      final comparison = compareVersions(latestVersion, kAppVersion);
      final isNewer =
          comparison > 0 ||
          (comparison == 0 &&
              latestBuild != null &&
              latestBuild > kAppBuildNumber);

      final downloads = manifest['downloads'];
      String? downloadUrl;
      if (downloads is Map) {
        final platformUrl = downloads[platformKey];
        if (platformUrl != null) downloadUrl = '$platformUrl'.trim();
      }
      downloadUrl ??= '${manifest['downloadUrl'] ?? ''}'.trim();
      if (downloadUrl.isEmpty) downloadUrl = null;

      final notes =
          '${manifest['releaseNotes'] ?? manifest['notes'] ?? manifest['changelog'] ?? ''}'
              .trim();

      return UpdateCheckResult(
        status: isNewer
            ? UpdateCheckStatus.updateAvailable
            : UpdateCheckStatus.upToDate,
        currentVersion: kAppVersion,
        currentBuild: kAppBuildNumber,
        latestVersion: latestVersion,
        latestBuild: latestBuild,
        releaseNotes: notes.isEmpty ? null : notes,
        downloadUrl: downloadUrl,
      );
    } catch (e) {
      return UpdateCheckResult(
        status: UpdateCheckStatus.error,
        currentVersion: kAppVersion,
        currentBuild: kAppBuildNumber,
        error: 'Could not reach the update server: $e',
      );
    } finally {
      if (ownedClient) httpClient.close();
    }
  }

  static Future<bool> openDownload(UpdateCheckResult result) async {
    final url = result.downloadUrl;
    if (url == null || url.isEmpty) return false;
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  /// Compares dotted versions. Returns >0 when [a] is newer than [b].
  static int compareVersions(String a, String b) {
    List<int> parts(String value) {
      final cleaned = value.trim().replaceFirst(RegExp(r'^[vV]'), '');
      final core = cleaned.split(RegExp(r'[-+]')).first;
      return core
          .split('.')
          .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();
    }

    final left = parts(a);
    final right = parts(b);
    final length = left.length > right.length ? left.length : right.length;
    for (var i = 0; i < length; i++) {
      final l = i < left.length ? left[i] : 0;
      final r = i < right.length ? right[i] : 0;
      if (l != r) return l.compareTo(r);
    }
    return 0;
  }
}
