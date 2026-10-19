import 'package:flutter/material.dart';

/// Global bus for `rentmanager://screen/...` links
/// (port of DeepLinkingService listener fan-out + screen routing).
class DeepLinkBus {
  static final ValueNotifier<String?> pending = ValueNotifier(null);
  static void request(String url) => pending.value = url;

  /// Maps `rentmanager://<screen>` to a bottom-tab index.
  /// Returns -1 for the settings overlay, null for unknown links.
  static int? tabIndexFor(String url) {
    final m = RegExp(r'^rentmanager://([^/?]+)').firstMatch(url);
    if (m == null) return null;
    switch (m.group(1)) {
      case 'overview':
        return 0;
      case 'tenants':
        return 1;
      case 'work':
        return 2;
      case 'documents':
        return 3;
      case 'reports':
        return 4;
      case 'zakat':
        return 5;
      case 'settings':
        return -1; // settings overlay
      default:
        return null;
    }
  }

  /// Builds a shareable link, mirroring DeepLinkingService.createDeepLink.
  static String create(String screen, [Map<String, String>? params]) {
    var url = 'rentmanager://$screen';
    if (params != null && params.isNotEmpty) {
      url += '?${params.entries.map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    }
    return url;
  }
}
