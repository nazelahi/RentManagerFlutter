import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:rentmanager/services/update_service.dart';

void main() {
  group('UpdateService.compareVersions', () {
    test('detects newer and older dotted versions', () {
      expect(UpdateService.compareVersions('1.0.7', '1.0.6'), greaterThan(0));
      expect(UpdateService.compareVersions('1.0.6', '1.0.7'), lessThan(0));
      expect(UpdateService.compareVersions('v1.2.0', '1.2'), 0);
      expect(UpdateService.compareVersions('1.10.0', '1.9.9'), greaterThan(0));
    });
  });

  group('UpdateService.checkForUpdates', () {
    test('returns updateAvailable for a newer manifest version', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'version': '99.0.0',
            'build': 99,
            'releaseNotes': 'Big release',
            'downloads': {'macos': 'https://example.com/RentManager-99.dmg'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await UpdateService.checkForUpdates(
        client: client,
        overrideManifestUrl: 'https://example.com/update.json',
      );

      expect(result.status, UpdateCheckStatus.updateAvailable);
      expect(result.latestVersion, '99.0.0');
      expect(result.releaseNotes, 'Big release');
      expect(result.hasDownload, isTrue);
    });

    test('returns upToDate for the current version', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'version': resultVersion, 'build': 1}),
          200,
        );
      });

      final result = await UpdateService.checkForUpdates(
        client: client,
        overrideManifestUrl: 'https://example.com/update.json',
      );

      expect(result.status, UpdateCheckStatus.upToDate);
    });

    test('returns notConfigured without a manifest URL', () async {
      final result = await UpdateService.checkForUpdates(
        overrideManifestUrl: '',
      );
      expect(result.status, UpdateCheckStatus.notConfigured);
    });

    test('returns error for a non-200 response', () async {
      final client = MockClient((request) async => http.Response('nope', 503));
      final result = await UpdateService.checkForUpdates(
        client: client,
        overrideManifestUrl: 'https://example.com/update.json',
      );
      expect(result.status, UpdateCheckStatus.error);
      expect(result.error, contains('503'));
    });
  });
}

const resultVersion = '1.0.6';
