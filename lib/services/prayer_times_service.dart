import 'dart:convert';
import 'package:http/http.dart' as http;

/// Port of `src/services/PrayerTimesService.ts` — Aladhan API with 24h cache.
class PrayerTimesService {
  static const _base = 'https://api.aladhan.com/v1/timings';
  static Map<String, dynamic>? _cache;
  static DateTime? _cacheAt;
  static String? _cacheKey;

  static Future<Map<String, dynamic>?> timings({
    required double lat, required double lng,
  }) async {
    final now = DateTime.now();
    final key = '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)},'
        '${now.year}-${now.month}-${now.day}';
    if (_cache != null &&
        _cacheAt != null &&
        _cacheKey == key &&
        now.difference(_cacheAt!).inHours < 24) {
      return _cache;
    }
    try {
      final d = '${now.day.toString().padLeft(2, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-${now.year}';
      final res = await http.get(
        Uri.parse('$_base/$d?latitude=$lat&longitude=$lng&method=2'));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        _cache = (body['data'] as Map<String, dynamic>)['timings'] as Map<String, dynamic>;
        _cacheAt = DateTime.now();
        _cacheKey = key;
        return _cache;
      }
    } catch (_) {}
    return null;
  }
}
