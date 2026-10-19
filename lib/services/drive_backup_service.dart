import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/models/models.dart';
import '../core/state/app_data.dart';
import '../core/storage/app_media_backup.dart';
import '../core/storage/app_storage.dart';
import 'data_merge_service.dart';

/// Lightweight representation of authenticated Google account information.
class GoogleAccountInfo {
  final String email;
  final String? displayName;

  const GoogleAccountInfo({required this.email, this.displayName});
}

/// Status of Google Drive background synchronization.
enum DriveSyncStatus { idle, syncing, synced, error }

/// Thrown when Drive changed between the pull/merge and the upload. Callers
/// retry the whole pull-merge-upload cycle instead of overwriting the edit.
class _RemoteChangedException implements Exception {
  final String? currentModifiedTime;
  const _RemoteChangedException(this.currentModifiedTime);
  @override
  String toString() =>
      'Remote backup changed during sync (modifiedTime: $currentModifiedTime)';
}

/// Service managing Google Drive backup, restore, auto sync, and native Google Sign-In.
/// Backups are saved to and restored from the `RentManager_Backups` folder in Google Drive.
class DriveBackupService {
  DriveBackupService._();

  static const String folderName = 'RentManager_Backups';
  static const String backupFileName = 'RentManager_Backup.json';
  static const String filePrefix = 'RentManager_Backup_';
  static const String _autoPrefix = 'RentManager_AutoBackup_';

  static final ValueNotifier<DriveSyncStatus> syncStatus =
      ValueNotifier<DriveSyncStatus>(DriveSyncStatus.idle);
  static final ValueNotifier<String?> lastSyncError = ValueNotifier<String?>(
    null,
  );
  static final ValueNotifier<bool> signedIn = ValueNotifier<bool>(false);

  static void _notifyAuthChanged() {
    signedIn.value = _currentUser != null;
  }

  static Timer? _debounceSyncTimer;

  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/userinfo.email',
    'https://www.googleapis.com/auth/userinfo.profile',
  ];

  static const String defaultClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '',
  );

  static const String desktopClientId = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_ID',
    defaultValue: '',
  );
  static const String desktopClientSecret = String.fromEnvironment(
    'GOOGLE_DESKTOP_CLIENT_SECRET',
    defaultValue: '',
  );

  static const String _spKeyPrefix = 'rm_drive_auth_';

  static bool _initialized = false;
  static GoogleSignInAccount? _mobileAccount;
  static auth.AutoRefreshingAuthClient? _desktopClient;
  static GoogleAccountInfo? _currentUser;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  /// Ensures Google Sign-In or Desktop Loopback OAuth is properly initialized.
  static Future<void> _ensureInit() async {
    if (_initialized) return;

    if (_isDesktop) {
      await _restoreDesktopCredentials();
      _initialized = true;
      return;
    }

    final clientId = const String.fromEnvironment(
      'GOOGLE_CLIENT_ID',
      defaultValue: defaultClientId,
    ).trim();

    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: clientId.isNotEmpty ? clientId : null,
      );

      GoogleSignIn.instance.authenticationEvents.listen(
        (event) {
          if (event is GoogleSignInAuthenticationEventSignIn) {
            _mobileAccount = event.user;
            _currentUser = GoogleAccountInfo(
              email: event.user.email,
              displayName: event.user.displayName,
            );
          } else if (event is GoogleSignInAuthenticationEventSignOut) {
            _mobileAccount = null;
            _currentUser = null;
          }
          _notifyAuthChanged();
        },
        onError: (err) {
          debugPrint('GoogleSignIn auth event error: $err');
        },
      );

      final user = await GoogleSignIn.instance
          .attemptLightweightAuthentication();
      _mobileAccount = user;
      _currentUser = user != null
          ? GoogleAccountInfo(email: user.email, displayName: user.displayName)
          : null;
      _notifyAuthChanged();
    } catch (e) {
      debugPrint('GoogleSignIn initialization note: $e');
    }

    _initialized = true;
  }

  /// Restores saved desktop OAuth credentials from SharedPreferences.
  static Future<void> _restoreDesktopCredentials() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final refresh = sp.getString('${_spKeyPrefix}refresh');
      if (refresh == null || refresh.isEmpty) return;

      final tokenData = sp.getString('${_spKeyPrefix}token') ?? '';
      final tokenType = sp.getString('${_spKeyPrefix}type') ?? 'Bearer';
      final expiryStr = sp.getString('${_spKeyPrefix}expiry');
      final expiry = expiryStr != null
          ? (DateTime.tryParse(expiryStr) ?? DateTime.now())
          : DateTime.now();
      final idToken = sp.getString('${_spKeyPrefix}id_token');
      final scopes = sp.getStringList('${_spKeyPrefix}scopes') ?? _scopes;
      final email = sp.getString('${_spKeyPrefix}email') ?? '';
      final name = sp.getString('${_spKeyPrefix}name');

      final creds = auth.AccessCredentials(
        auth.AccessToken(tokenType, tokenData, expiry),
        refresh,
        scopes,
        idToken: idToken,
      );

      final cId = auth.ClientId(desktopClientId, desktopClientSecret);
      _desktopClient = auth.autoRefreshingClient(cId, creds, http.Client());
      _currentUser = GoogleAccountInfo(email: email, displayName: name);
      _notifyAuthChanged();
    } catch (e) {
      debugPrint('Error restoring desktop credentials: $e');
    }
  }

  /// Persists desktop OAuth credentials to SharedPreferences.
  static Future<void> _persistDesktopCredentials(
    auth.AccessCredentials creds,
    String email,
    String? name,
  ) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('${_spKeyPrefix}token', creds.accessToken.data);
      await sp.setString('${_spKeyPrefix}type', creds.accessToken.type);
      await sp.setString(
        '${_spKeyPrefix}expiry',
        creds.accessToken.expiry.toIso8601String(),
      );
      if (creds.refreshToken != null) {
        await sp.setString('${_spKeyPrefix}refresh', creds.refreshToken!);
      }
      if (creds.idToken != null) {
        await sp.setString('${_spKeyPrefix}id_token', creds.idToken!);
      }
      await sp.setStringList('${_spKeyPrefix}scopes', creds.scopes);
      await sp.setString('${_spKeyPrefix}email', email);
      if (name != null) {
        await sp.setString('${_spKeyPrefix}name', name);
      }
    } catch (e) {
      debugPrint('Error persisting desktop credentials: $e');
    }
  }

  /// Clears persisted desktop OAuth credentials.
  static Future<void> _clearDesktopCredentials() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final keys = sp
          .getKeys()
          .where((k) => k.startsWith(_spKeyPrefix))
          .toList();
      for (final k in keys) {
        await sp.remove(k);
      }
    } catch (_) {}
    _desktopClient?.close();
    _desktopClient = null;
    _currentUser = null;
    _notifyAuthChanged();
  }

  /// Performs browser loopback OAuth flow on desktop platforms.
  static Future<GoogleAccountInfo?> _desktopSignIn() async {
    if (desktopClientId.isEmpty || desktopClientSecret.isEmpty) {
      throw StateError(
        'Google Desktop Client ID / Secret are not configured. '
        'Provide them via --dart-define=GOOGLE_DESKTOP_CLIENT_ID=... '
        'and --dart-define=GOOGLE_DESKTOP_CLIENT_SECRET=...',
      );
    }
    final cId = auth.ClientId(desktopClientId, desktopClientSecret);
    final client = await auth.clientViaUserConsent(cId, _scopes, (url) async {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    });

    _desktopClient = client;

    String email = '';
    String? name;
    try {
      final res = await client.get(
        Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        email = (data['email'] as String?) ?? '';
        name = data['name'] as String?;
      }
    } catch (e) {
      debugPrint('Error fetching userinfo: $e');
    }

    final accountInfo = GoogleAccountInfo(email: email, displayName: name);
    _currentUser = accountInfo;
    _notifyAuthChanged();
    await _persistDesktopCredentials(client.credentials, email, name);
    return accountInfo;
  }

  /// Whether Google Drive cloud backup is available.
  static bool get driveAvailable => true;

  /// Human-readable mode string.
  static String get driveMode => 'cloud+local';

  /// Currently signed-in Google account (if any).
  static GoogleAccountInfo? get currentUser => _currentUser;

  /// Whether a Google account is currently signed in.
  static bool get isSignedIn => _currentUser != null;

  /// Initiates Google Sign-In flow (Browser Loopback on Desktop, Native SDK on Mobile).
  static Future<GoogleAccountInfo?> signIn() async {
    await _ensureInit();

    if (_isDesktop) {
      try {
        return await _desktopSignIn();
      } catch (e) {
        debugPrint('Desktop loopback sign-in note: $e');
        if (e.toString().contains('UserConsentException') ||
            e.toString().contains('cancelled') ||
            e.toString().contains('access_denied')) {
          return null;
        }
        rethrow;
      }
    }

    try {
      var account =
          _mobileAccount ??
          await GoogleSignIn.instance.attemptLightweightAuthentication();

      account ??= await GoogleSignIn.instance.authenticate(scopeHint: _scopes);

      _mobileAccount = account;
      _currentUser = GoogleAccountInfo(
        email: account.email,
        displayName: account.displayName,
      );
      _notifyAuthChanged();

      await _authorizeDriveScopes(account);
      return _currentUser;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        debugPrint('Google Sign-In was cancelled by the user.');
        return null;
      }
      rethrow;
    }
  }

  /// Authorizes the required Google Drive scopes for the given account.
  static Future<GoogleSignInClientAuthorization> _authorizeDriveScopes(
    GoogleSignInAccount account,
  ) async {
    var authz = await account.authorizationClient.authorizationForScopes(
      _scopes,
    );
    authz ??= await account.authorizationClient.authorizeScopes(_scopes);
    return authz;
  }

  /// Signs out the current Google account.
  static Future<void> signOut() async {
    await _ensureInit();
    if (_isDesktop) {
      await _clearDesktopCredentials();
      return;
    }
    _mobileAccount = null;
    _currentUser = null;
    _notifyAuthChanged();
    await GoogleSignIn.instance.signOut();
  }

  /// Disconnects and revokes current account authorizations.
  static Future<void> disconnect() async {
    await _ensureInit();
    if (_isDesktop) {
      await _clearDesktopCredentials();
      return;
    }
    _mobileAccount = null;
    _currentUser = null;
    _notifyAuthChanged();
    await GoogleSignIn.instance.disconnect();
  }

  /// Builds an authenticated [drive.DriveApi] instance.
  static Future<drive.DriveApi> _getDriveApi() async {
    await _ensureInit();

    if (_isDesktop) {
      var client = _desktopClient;
      if (client == null) {
        final user = await signIn();
        if (user == null) {
          throw StateError('Sign-in was cancelled by the user.');
        }
        client = _desktopClient;
      }
      if (client == null) {
        throw StateError(
          'Failed to initialize authenticated Google Drive client.',
        );
      }
      return drive.DriveApi(client);
    }

    var account =
        _mobileAccount ??
        await GoogleSignIn.instance.attemptLightweightAuthentication();

    if (account == null) {
      final user = await signIn();
      if (user == null || _mobileAccount == null) {
        throw StateError('Sign-in was cancelled by the user.');
      }
      account = _mobileAccount!;
    }

    final authz = await _authorizeDriveScopes(account);

    final client = _GoogleAuthClient(
      token: authz.accessToken,
      onTokenExpired: () async {
        try {
          await account!.authorizationClient.clearAuthorizationToken(
            accessToken: authz.accessToken,
          );
        } catch (_) {}
      },
    );

    return drive.DriveApi(client);
  }

  /// Retrieves or creates the `RentManager_Backups` folder ID in Google Drive.
  static Future<String> _folderId(drive.DriveApi api) async {
    try {
      final found = await api.files.list(
        q: "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      if (found.files != null && found.files!.isNotEmpty) {
        return found.files!.first.id!;
      }
    } catch (e) {
      debugPrint('Drive list folders note: $e');
    }

    // Create folder if not found
    final folder = await api.files.create(
      drive.File(
        name: folderName,
        mimeType: 'application/vnd.google-apps.folder',
        description: 'RentManager Backups Folder',
      ),
      $fields: 'id',
    );
    return folder.id!;
  }

  /// Returns the current primary backup file and its modification timestamp.
  static Future<({String id, String? modifiedTime})?> _remotePrimaryFile(
    drive.DriveApi api,
  ) async {
    final parent = await _folderId(api);
    final prefix = filePrefix.replaceAll("'", "\\'");
    final autoPrefix = _autoPrefix.replaceAll("'", "\\'");
    final res = await api.files.list(
      q:
          "'$parent' in parents and trashed = false "
          "and mimeType != 'application/vnd.google-apps.folder' "
          "and (name = '$backupFileName' "
          "or name contains '$prefix' or name contains '$autoPrefix')",
      spaces: 'drive',
      orderBy: 'modifiedTime desc',
      pageSize: 50,
      $fields: 'files(id, name, modifiedTime)',
    );
    final files = res.files ?? const <drive.File>[];
    if (files.isEmpty) return null;
    final file = files.firstWhere(
      (f) => f.name == backupFileName,
      orElse: () => files.first,
    );
    if (file.id == null) return null;
    return (id: file.id!, modifiedTime: file.modifiedTime?.toIso8601String());
  }

  /// Uploads or replaces the backup in the `RentManager_Backups` folder.
  /// If a backup file already exists, updates it in-place instead of creating a new file.
  /// Any duplicate or legacy timestamped files in the folder are also cleaned up.
  static Future<void> _uploadChain = Future.value();
  static Future<void> _syncChain = Future.value();

  /// Serializes complete pull-merge-upload cycles so two sync triggers cannot
  /// interleave their reads and writes.
  static Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _syncChain = _syncChain.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// Serializes Drive writes. Two concurrent uploads used to both see "no
  /// backup file" and create duplicates, or overwrite a newer snapshot.
  static Future<UploadBackupResult> _uploadOrReplaceBackup(
    drive.DriveApi api,
    Map<String, dynamic> data, {
    required String description,
    String? expectedRemoteModifiedTime,
    bool verifyRemoteUnchanged = false,
  }) {
    final completer = Completer<UploadBackupResult>();
    _uploadChain = _uploadChain.then((_) async {
      try {
        completer.complete(
          await _uploadOrReplaceBackupImpl(
            api,
            data,
            description: description,
            expectedRemoteModifiedTime: expectedRemoteModifiedTime,
            verifyRemoteUnchanged: verifyRemoteUnchanged,
          ),
        );
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  static Future<UploadBackupResult> _uploadOrReplaceBackupImpl(
    drive.DriveApi api,
    Map<String, dynamic> data, {
    required String description,
    String? expectedRemoteModifiedTime,
    bool verifyRemoteUnchanged = false,
  }) async {
    final parent = await _folderId(api);
    final now = DateTime.now();
    final stamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(now);

    final jsonString = jsonEncode(data);
    final bytes = utf8.encode(jsonString);

    final media = drive.Media(Stream.value(bytes), bytes.length);

    // Look for existing backup file(s) in the folder
    drive.FileList? existingList;
    try {
      final prefix = filePrefix.replaceAll("'", "\\'");
      final autoPrefix = _autoPrefix.replaceAll("'", "\\'");
      existingList = await api.files.list(
        q:
            "'$parent' in parents and trashed = false "
            "and mimeType != 'application/vnd.google-apps.folder' "
            "and (name = '$backupFileName' "
            "or name contains '$prefix' or name contains '$autoPrefix')",
        spaces: 'drive',
        orderBy: 'modifiedTime desc',
        pageSize: 50,
        $fields: 'files(id, name, createdTime, modifiedTime)',
      );
    } catch (e) {
      debugPrint('Drive check existing files note: $e');
    }

    final existingFiles = existingList?.files ?? [];

    String resultName = backupFileName;
    String? resultModifiedTime;
    if (existingFiles.isNotEmpty) {
      // Pick the primary file to replace: prefer exact canonical name if present, else the latest file
      final primary = existingFiles.firstWhere(
        (f) => f.name == backupFileName,
        orElse: () => existingFiles.first,
      );

      if (verifyRemoteUnchanged) {
        final current = primary.modifiedTime?.toIso8601String();
        if (current != expectedRemoteModifiedTime) {
          throw _RemoteChangedException(current);
        }
      }

      final updateFile = drive.File(
        name: backupFileName,
        description: description,
      );

      final updated = await api.files.update(
        updateFile,
        primary.id!,
        uploadMedia: media,
        $fields: 'id, name, modifiedTime, size',
      );
      resultName = backupFileName;
      resultModifiedTime = updated.modifiedTime?.toIso8601String();

      // Keep a short rotation of older backups instead of deleting every file
      // in the folder. Only files matching our backup prefixes are eligible.
      final otherBackups = existingFiles
          .where(
            (f) =>
                f.id != null &&
                f.id != primary.id &&
                ((f.name ?? '').startsWith(filePrefix) ||
                    (f.name ?? '').startsWith(_autoPrefix)),
          )
          .toList();
      for (final extra in otherBackups.skip(4)) {
        try {
          await api.files.delete(extra.id!);
        } catch (_) {}
      }
    } else {
      if (verifyRemoteUnchanged && expectedRemoteModifiedTime != null) {
        throw const _RemoteChangedException(null);
      }
      // First-time backup: create a new file
      final newFile = drive.File(
        name: backupFileName,
        parents: [parent],
        mimeType: 'application/json',
        description: description,
      );

      final created = await api.files.create(
        newFile,
        uploadMedia: media,
        $fields: 'id, name, createdTime, modifiedTime, size',
      );
      resultName = backupFileName;
      resultModifiedTime = created.modifiedTime?.toIso8601String();
    }

    // Local redundancy: save copy in documents directory (keeps last 3 local snapshots)
    try {
      final dir = await getApplicationDocumentsDirectory();
      final localFile = File('${dir.path}/$_autoPrefix$stamp.json');
      await localFile.writeAsBytes(bytes);

      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.split('/').last.startsWith(_autoPrefix))
              .toList()
            ..sort((a, b) => b.path.compareTo(a.path));
      for (final extra in files.skip(3)) {
        try {
          await extra.delete();
        } catch (_) {}
      }
    } catch (err) {
      debugPrint('Local redundancy write note: $err');
    }

    return UploadBackupResult(
      fileName: resultName,
      modifiedTime: resultModifiedTime,
    );
  }

  /// Backs up the entire app data to Google Drive, replacing the existing backup
  /// in the `RentManager_Backups` folder.
  /// Returns the name of the backup file.
  static Future<String> backupNow(Map<String, dynamic> data) =>
      _serialized(() => _backupNowImpl(data));

  static Future<String> _backupNowImpl(Map<String, dynamic> initialData) async {
    final api = await _getDriveApi();
    final now = DateTime.now();
    final description =
        'RentManager Cloud Backup - ${DateFormat.yMMMd().add_jm().format(now)}';

    for (var attempt = 0; attempt < 2; attempt++) {
      // Capture the exact remote version we are merging against. The upload is
      // rejected if Drive changes again before our write lands.
      final remote = await _remotePrimaryFile(api);
      final expectedRemoteModifiedTime = remote?.modifiedTime;

      var outgoing = attempt == 0 ? initialData : await AppStorage.exportAll();

      // Pre-push merge: fold a remote backup that is newer than our last sync
      // into the outgoing snapshot, so a manual backup can't clobber records
      // edited on another device. Local storage self-heals on the next pull.
      if (!_pullGateBlocked) {
        outgoing =
            await _mergeRemoteIfNewerIntoExport(api, fallback: outgoing) ??
            outgoing;
      }

      try {
        final res = await _uploadOrReplaceBackup(
          api,
          outgoing,
          description: description,
          expectedRemoteModifiedTime: expectedRemoteModifiedTime,
          verifyRemoteUnchanged: true,
        );
        return res.fileName;
      } on _RemoteChangedException {
        if (attempt == 1) rethrow;
      }
    }
    throw StateError(
      'Backup could not be completed because Drive kept changing',
    );
  }

  /// If the remote backup was modified after our local [lastDriveSync],
  /// downloads it and 2-way merges it with the local export, returning the
  /// merged snapshot. Returns null when nothing newer exists, the pull gate
  /// is blocked, a sync is running, or the remote cannot be read.
  /// Does NOT modify local storage — the next periodic pull reconciles it.
  static Future<Map<String, dynamic>?> _mergeRemoteIfNewerIntoExport(
    drive.DriveApi api, {
    required Map<String, dynamic> fallback,
  }) async {
    try {
      final prefs = AppStorage.readJson(
        StorageKeys.preferences,
        AppPreferences.fromJson,
      );
      final localLastSync = DateTime.tryParse(prefs?.lastDriveSync ?? '');

      final remoteFile = await _remotePrimaryFile(api);
      final rTime = DateTime.tryParse(remoteFile?.modifiedTime ?? '');
      if (remoteFile?.id == null || rTime == null) return null;

      final isRemoteNewer =
          localLastSync == null ||
          rTime.isAfter(localLastSync.add(const Duration(seconds: 2)));
      if (!isRemoteNewer) return null;

      final remoteMap = await downloadSilently(remoteFile!.id, api: api);
      if (remoteMap == null) return null;

      final unpackedRemote = await AppMediaBackup.unpackMedia(remoteMap);
      final localData = await AppStorage.exportAll(includeMedia: false);
      return DataMergeService.merge(
        local: localData,
        remote: unpackedRemote,
        remoteSnapshotTime: rTime,
      ).mergedData;
    } catch (e) {
      debugPrint('BackupNow remote merge note: $e');
      return null;
    }
  }

  /// Lists all backup files in the `RentManager_Backups` folder on Google Drive.
  static Future<List<DriveBackupFile>> listBackups() async {
    final api = await _getDriveApi();
    final parent = await _folderId(api);

    final files = <drive.File>[];
    String? pageToken;
    do {
      final res = await api.files.list(
        q:
            "'$parent' in parents and trashed = false "
            "and mimeType != 'application/vnd.google-apps.folder' "
            "and (name = '$backupFileName' "
            "or name contains '$filePrefix' "
            "or name contains '$_autoPrefix')",
        spaces: 'drive',
        orderBy: 'modifiedTime desc',
        pageSize: 100,
        pageToken: pageToken,
        $fields: 'nextPageToken, files(id, name, createdTime, modifiedTime, size, description)',
      );
      files.addAll(res.files ?? []);
      pageToken = res.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);

    final email = _currentUser?.email ?? '';

    return files.map((f) {
      final sizeInt = int.tryParse(f.size ?? '');
      final formattedSize = sizeInt != null
          ? formatFileSize(sizeInt)
          : (f.size ?? '');

      final timestamp =
          (f.modifiedTime ?? f.createdTime)?.toIso8601String() ?? '';

      return DriveBackupFile(
        id: f.id ?? '',
        name: f.name ?? '',
        created: timestamp,
        size: formattedSize,
        accountEmail: email,
      );
    }).toList();
  }

  /// Downloads and parses a backup JSON from Google Drive by its file ID.
  static Future<Map<String, dynamic>?> download(String fileId) async {
    final api = await _getDriveApi();

    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }

    final raw = utf8.decode(bytes, allowMalformed: true);
    final decoded = jsonDecode(raw);

    if (decoded is! Map) {
      throw const FormatException('Backup file is not a valid JSON object');
    }

    return Map<String, dynamic>.from(decoded);
  }

  /// Deletes a backup file from Google Drive by its file ID.
  static Future<void> deleteBackup(String fileId) async {
    final api = await _getDriveApi();
    await api.files.delete(fileId);
  }

  /// Helper to format bytes into readable KB/MB format.
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  /// Formats an ISO string to a human-readable relative time (e.g., 'Just now', '5m ago', '2h ago').
  static String formatTimeAgo(String? iso) {
    if (iso == null || iso.isEmpty) return 'Never';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return 'Never';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat.MMMd().format(dt);
  }

  /// Attempts to get an authenticated DriveApi silently without showing an interactive dialog.
  /// Returns null if user is not signed in or scopes are not granted.
  static Future<drive.DriveApi?> getSilentDriveApi() async {
    await _ensureInit();

    if (_isDesktop) {
      final client = _desktopClient;
      return client != null ? drive.DriveApi(client) : null;
    }

    try {
      var account =
          _mobileAccount ??
          await GoogleSignIn.instance.attemptLightweightAuthentication();
      if (account == null) return null;
      _mobileAccount = account;
      _currentUser = GoogleAccountInfo(
        email: account.email,
        displayName: account.displayName,
      );
      _notifyAuthChanged();

      final clientAuthz =
          await account.authorizationClient.authorizationForScopes(_scopes) ??
          await account.authorizationClient.authorizeScopes(_scopes);

      final token = clientAuthz.accessToken;
      final client = _GoogleAuthClient(
        token: token,
        onTokenExpired: () async {
          try {
            await account.authorizationClient.clearAuthorizationToken(
              accessToken: token,
            );
          } catch (_) {}
        },
      );
      return drive.DriveApi(client);
    } catch (e) {
      debugPrint('Silent DriveApi note: $e');
      return null;
    }
  }

  static bool _isSyncing = false;
  static Timer? _periodicSyncTimer;

  /// Silently downloads and parses a backup JSON from Google Drive without prompting.
  static Future<Map<String, dynamic>?> downloadSilently(
    String fileId, {
    drive.DriveApi? api,
  }) async {
    final clientApi = api ?? await getSilentDriveApi();
    if (clientApi == null) return null;

    final media = await clientApi.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final bytes = <int>[];
    await for (final chunk in media.stream) {
      bytes.addAll(chunk);
    }

    final raw = utf8.decode(bytes, allowMalformed: true);
    final decoded = jsonDecode(raw);

    if (decoded is! Map) {
      throw const FormatException('Backup file is not a valid JSON object');
    }

    return Map<String, dynamic>.from(decoded);
  }

  /// Silently inspects Google Drive to see if a newer cloud snapshot exists.
  /// If remote is newer, downloads it, performs an intelligent 2-way entity merge,
  /// updates persistent storage and in-memory Riverpod state, and if local had changes,
  /// Blocks auto data pulls while the onboarding/setup wizard is active.
  /// Set by [AppData.resetApp] and cleared in [AppData.completeOnboarding].
  static bool _pullGateBlocked = false;
  static void setPullGate(bool blocked) => _pullGateBlocked = blocked;

  /// pushes the reconciled data back to Drive.
  static Future<bool> checkAndPullLatest(WidgetRef ref) =>
      _serialized(() => _checkAndPullLatestImpl(ref.read));

  /// Same as [checkAndPullLatest] but callable from Riverpod notifiers.
  static Future<bool> checkAndPullLatestForRef(Ref ref) =>
      _serialized(() => _checkAndPullLatestImpl(ref.read));

  static Future<bool> _checkAndPullLatestImpl(
    T Function<T>(ProviderListenable<T>) read,
  ) async {
    if (_pullGateBlocked) return false;
    if (_isSyncing) return false;
    await _ensureInit();
    if (!isSignedIn) return false;

    _isSyncing = true;
    try {
      final api = await getSilentDriveApi();
      if (api == null) return false;

      final remoteFile = await _remotePrimaryFile(api);
      final remoteTime = DateTime.tryParse(remoteFile?.modifiedTime ?? '');
      final remoteId = remoteFile?.id;
      if (remoteTime == null || remoteId == null) return false;

      final localLastSyncStr = read(appDataProvider).preferences.lastDriveSync;
      final localLastSync = DateTime.tryParse(localLastSyncStr ?? '');

      // Check if remote is newer than local last sync (with 2-second tolerance for clock skew)
      final isRemoteNewer =
          localLastSync == null ||
          remoteTime.isAfter(localLastSync.add(const Duration(seconds: 2)));

      if (!isRemoteNewer) return false;

      syncStatus.value = DriveSyncStatus.syncing;

      // 1. Download remote content
      final remoteMap = await downloadSilently(remoteId, api: api);
      if (remoteMap == null) {
        syncStatus.value = DriveSyncStatus.idle;
        return false;
      }

      // 2. Unpack remote media (avatars, receipts, PDFs)
      final unpackedRemote = await AppMediaBackup.unpackMedia(remoteMap);

      // 3. Export current local data
      final localData = await AppStorage.exportAll(includeMedia: false);

      // 4. Merge via 2-way Last-Write-Wins
      final mergeResult = DataMergeService.merge(
        local: localData,
        remote: unpackedRemote,
        remoteSnapshotTime: remoteTime,
      );

      // 5. Persist merged data to storage
      await AppStorage.importAll(mergeResult.mergedData);

      // 6. Update preferences with new sync timestamp
      final syncTimestamp = remoteTime.toIso8601String();
      final updatedPrefs = read(appDataProvider).preferences
          .copyWith(lastDriveSync: syncTimestamp, driveAutoSync: true);
      await AppStorage.writeJson(
        StorageKeys.preferences,
        updatedPrefs.toJson(),
      );

      // 7. Synchronously refresh in-memory Riverpod state so UI updates instantly
      read(appDataProvider.notifier).reloadFromStorage();

      // 8. If local had independent newer changes, push the reconciled state back to Drive
      if (mergeResult.hasLocalNewerData) {
        final mergedFull = await AppStorage.exportAll();
        String? pushStamp;
        try {
          pushStamp = await autoSync(
            data: mergedFull,
            expectedRemoteModifiedTime: syncTimestamp,
            verifyRemoteUnchanged: true,
            throwOnRemoteChange: true,
          );
        } on _RemoteChangedException catch (e) {
          // Another device wrote between our pull and push. Leave the merged
          // local state intact; the next sync pulls and reconciles again.
          debugPrint('Push skipped: $e');
        }
        if (pushStamp != null) {
          // Advance lastDriveSync to the version we just uploaded, otherwise
          // the next periodic check sees remoteTime > lastDriveSync and
          // re-downloads our own file (self-redownload loop).
          final pushedPrefs = read(appDataProvider).preferences
              .copyWith(lastDriveSync: pushStamp, driveAutoSync: true);
          await AppStorage.writeJson(
            StorageKeys.preferences,
            pushedPrefs.toJson(),
          );
          read(appDataProvider.notifier).reloadFromStorage();
        }
        syncStatus.value = DriveSyncStatus.synced;
      } else {
        syncStatus.value = DriveSyncStatus.synced;
      }

      return true;
    } catch (e) {
      debugPrint('checkAndPullLatest error: $e');
      syncStatus.value = DriveSyncStatus.error;
      lastSyncError.value = '$e';
      return false;
    } finally {
      _isSyncing = false;
    }
  }

  /// Starts periodic background checking (every 45s) for cross-device sync.
  static void startPeriodicSync(WidgetRef ref) =>
      _startPeriodicSyncImpl(ref.read);

  /// Same as [startPeriodicSync] but callable from Riverpod notifiers
  /// (which expose [Ref] instead of [WidgetRef]).
  static void startPeriodicSyncForRef(Ref ref) =>
      _startPeriodicSyncImpl(ref.read);

  static void _startPeriodicSyncImpl(
    T Function<T>(ProviderListenable<T>) read,
  ) {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      try {
        if (_pullGateBlocked) return;
        if (!isSignedIn) return;
        if (!read(appDataProvider).preferences.driveAutoSync) return;
        await _serialized(() => _checkAndPullLatestImpl(read));
      } catch (e) {
        debugPrint('Periodic sync note: $e');
      }
    });
  }

  /// Stops the periodic sync timer.
  static void stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }

  static bool _hasPendingUpload = false;

  /// Invoked when the app is resumed or the desktop window regains focus.
  static Future<void> onAppResumed(WidgetRef ref) =>
      _serialized(() => _onAppResumedImpl(ref));

  static Future<void> _onAppResumedImpl(WidgetRef ref) async {
    if (_pullGateBlocked) return;
    if (!isSignedIn) return;
    final s = ref.read(appDataProvider);
    if (!s.preferences.driveAutoSync) return;

    // Check remote changes first
    await _checkAndPullLatestImpl(ref.read);
    // If an earlier upload failed while offline, push pending changes now
    if (_hasPendingUpload) {
      String? expected;
      try {
        final api = await getSilentDriveApi();
        if (api != null) {
          expected = (await _remotePrimaryFile(api))?.modifiedTime;
        }
      } catch (_) {
        expected = ref.read(appDataProvider).preferences.lastDriveSync;
      }
      final data = await AppStorage.exportAll();
      String? timestamp;
      try {
        timestamp = await autoSync(
          data: data,
          expectedRemoteModifiedTime: expected,
          verifyRemoteUnchanged: true,
          throwOnRemoteChange: true,
        );
      } on _RemoteChangedException {
        return;
      }
      if (timestamp != null) {
        _hasPendingUpload = false;
        final updatedPrefs = ref
            .read(appDataProvider)
            .preferences
            .copyWith(lastDriveSync: timestamp, driveAutoSync: true);
        await AppStorage.writeJson(
          StorageKeys.preferences,
          updatedPrefs.toJson(),
        );
        ref.read(appDataProvider.notifier).setPreferences(updatedPrefs);
      }
    }
  }

  /// Triggers a debounced auto sync after data changes.
  /// Debounces for 3 seconds to prevent spamming the Drive API during active typing/edits.
  /// Performs a pre-push check to prevent overwriting edits made simultaneously on another device.
  static void triggerDebouncedSync(
    AppDataState state, {
    required void Function(String timestamp) onSynced,
    void Function()? onRemoteMerged,
  }) {
    _debounceSyncTimer?.cancel();
    _debounceSyncTimer = Timer(const Duration(seconds: 3), () {
      _serialized(
        () => _runDebouncedSync(
          state,
          onSynced: onSynced,
          onRemoteMerged: onRemoteMerged,
        ),
      );
    });
  }

  static Future<void> _runDebouncedSync(
    AppDataState state, {
    required void Function(String timestamp) onSynced,
    void Function()? onRemoteMerged,
    int attempt = 0,
  }) async {
    try {
      final api = await getSilentDriveApi();
      if (api == null) {
        _hasPendingUpload = true;
        return;
      }

      final remote = await _remotePrimaryFile(api);
      final remoteStamp = remote?.modifiedTime;

      // Pre-push check: Did the other device update Drive in the meantime?
      try {
        final remoteTime = DateTime.tryParse(remoteStamp ?? '');
        final prefs =
            AppStorage.readJson(
              StorageKeys.preferences,
              AppPreferences.fromJson,
            ) ??
            state.preferences;
        final localLastSync = DateTime.tryParse(prefs.lastDriveSync ?? '');
        if (remote != null &&
            remoteTime != null &&
            (localLastSync == null ||
                remoteTime.isAfter(
                  localLastSync.add(const Duration(seconds: 2)),
                ))) {
          // Remote has newer items! Download & merge first so we don't clobber them!
          final remoteMap = await downloadSilently(remote.id, api: api);
          if (remoteMap != null) {
            final unpackedRemote = await AppMediaBackup.unpackMedia(remoteMap);
            final currentLocal = await AppStorage.exportAll(
              includeMedia: false,
            );
            final mergedResult = DataMergeService.merge(
              local: currentLocal,
              remote: unpackedRemote,
              remoteSnapshotTime: remoteTime,
            );
            await AppStorage.importAll(mergedResult.mergedData);
            // Refresh in-memory state from storage so the next local edit
            // doesn't rebuild lists from a stale snapshot and discard the
            // just-merged remote records.
            onRemoteMerged?.call();
          }
        }
      } catch (e) {
        debugPrint('Pre-push check note: $e');
      }

      final data = await AppStorage.exportAll();
      final timestamp = await autoSync(
        data: data,
        expectedRemoteModifiedTime: remoteStamp,
        verifyRemoteUnchanged: true,
        throwOnRemoteChange: true,
      );
      if (timestamp != null) {
        _hasPendingUpload = false;
        onSynced(timestamp);
      } else {
        _hasPendingUpload = true;
      }
    } on _RemoteChangedException {
      if (attempt < 2) {
        return _runDebouncedSync(
          state,
          onSynced: onSynced,
          onRemoteMerged: onRemoteMerged,
          attempt: attempt + 1,
        );
      }
      _hasPendingUpload = true;
    } catch (e) {
      debugPrint('Debounced sync error: $e');
      _hasPendingUpload = true;
    }
  }

  /// Performs background auto-sync of the app data to Google Drive.
  /// Replaces the previous cloud backup with the latest data snapshot.
  static Future<String?> autoSync({
    required Map<String, dynamic> data,
    int keepRecent = 1,
    String? expectedRemoteModifiedTime,
    bool verifyRemoteUnchanged = false,
    bool throwOnRemoteChange = false,
  }) async {
    syncStatus.value = DriveSyncStatus.syncing;
    lastSyncError.value = null;

    int attempts = 0;
    while (attempts < 2) {
      attempts++;
      try {
        final api = await getSilentDriveApi();
        if (api == null) {
          syncStatus.value = DriveSyncStatus.idle;
          return null;
        }

        final now = DateTime.now();
        final description =
            'RentManager Auto Cloud Sync - ${DateFormat.yMMMd().add_jm().format(now)}';
        final res = await _uploadOrReplaceBackup(
          api,
          data,
          description: description,
          expectedRemoteModifiedTime: expectedRemoteModifiedTime,
          verifyRemoteUnchanged: verifyRemoteUnchanged,
        );

        syncStatus.value = DriveSyncStatus.synced;
        return res.modifiedTime ?? res.fileName;
      } on _RemoteChangedException {
        syncStatus.value = DriveSyncStatus.idle;
        if (throwOnRemoteChange) rethrow;
        return null;
      } catch (e) {
        debugPrint('Auto sync attempt $attempts error: $e');
        final isTransient =
            e is http.ClientException ||
            e is SocketException ||
            e.toString().contains('Connection closed') ||
            e.toString().contains('reset by peer') ||
            e.toString().contains('Broken pipe');
        if (attempts < 2 && isTransient) {
          await Future.delayed(const Duration(milliseconds: 1500));
          continue;
        }
        syncStatus.value = DriveSyncStatus.error;
        lastSyncError.value = '$e';
        return null;
      }
    }
    return null;
  }

  /// Checks if Google Drive sync is due according to the user's schedule (daily/weekly/on_change).
  /// Runs silently in the background on app boot.
  static Future<String?> syncIfDue(WidgetRef ref) async {
    if (_pullGateBlocked) return null;
    await _ensureInit();
    if (!isSignedIn) return null;

    // Check and pull latest remote changes first
    await checkAndPullLatest(ref);

    final s = ref.read(appDataProvider);
    if (!s.preferences.driveAutoSync) return null;

    final lastStr = s.preferences.lastDriveSync;
    final last = DateTime.tryParse(lastStr ?? '');
    if (last != null) {
      final freq = s.preferences.driveSyncFrequency;
      final now = DateTime.now();
      if (freq == 'daily' && now.difference(last).inHours < 24) {
        return null;
      }
      if (freq == 'weekly' && now.difference(last).inDays < 7) {
        return null;
      }
    }

    return syncNow(ref);
  }

  /// Immediately syncs all app data to Google Drive (pulls latest first, then pushes)
  /// and updates lastDriveSync in preferences.
  static Future<String?> syncNow(WidgetRef ref) =>
      _serialized(() => _syncNowImpl(ref));

  static Future<String?> _syncNowImpl(WidgetRef ref, {int attempt = 0}) async {
    // 1. Pull and merge any remote changes first
    await _checkAndPullLatestImpl(ref.read);

    // 2. Read the actual remote timestamp (the backup may have been deleted
    // or replaced by a legacy file) and export the merged data. If Drive
    // changes before our write lands, retry the whole cycle instead of
    // overwriting the other device's edit.
    String? expected;
    try {
      final api = await getSilentDriveApi();
      if (api != null) {
        expected = (await _remotePrimaryFile(api))?.modifiedTime;
      }
    } catch (e) {
      debugPrint('Sync remote check note: $e');
      expected = ref.read(appDataProvider).preferences.lastDriveSync;
    }
    final data = await AppStorage.exportAll();
    String? timestamp;
    try {
      timestamp = await autoSync(
        data: data,
        expectedRemoteModifiedTime: expected,
        verifyRemoteUnchanged: true,
        throwOnRemoteChange: true,
      );
    } on _RemoteChangedException {
      if (attempt < 2) {
        return _syncNowImpl(ref, attempt: attempt + 1);
      }
      rethrow;
    }
    if (timestamp != null) {
      ref
          .read(appDataProvider.notifier)
          .setPreferences(
            ref
                .read(appDataProvider)
                .preferences
                .copyWith(lastDriveSync: timestamp, driveAutoSync: true),
          );
      await AppStorage.writeJson(
        StorageKeys.preferences,
        ref.read(appDataProvider).preferences.toJson(),
      );
    }
    return timestamp;
  }
}

/// Result of uploading a backup file to Google Drive.
class UploadBackupResult {
  final String fileName;
  final String? modifiedTime;
  const UploadBackupResult({required this.fileName, this.modifiedTime});
}

/// Represents a backup file item on Google Drive.
class DriveBackupFile {
  final String id;
  final String name;
  final String created;
  final String size;
  final String? accountEmail;

  const DriveBackupFile({
    required this.id,
    required this.name,
    required this.created,
    required this.size,
    this.accountEmail,
  });
}

/// Custom HTTP Client attaching Bearer tokens for Google Drive requests.
class _GoogleAuthClient extends http.BaseClient {
  final String token;
  final Future<void> Function()? onTokenExpired;
  final http.Client _inner = http.Client();

  _GoogleAuthClient({required this.token, this.onTokenExpired});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers['Authorization'] = 'Bearer $token';
    request.headers['X-Goog-AuthUser'] = '0';
    final response = await _inner.send(request);
    if (response.statusCode == 401 && onTokenExpired != null) {
      await onTokenExpired!();
    }
    return response;
  }

  @override
  void close() => _inner.close();
}
