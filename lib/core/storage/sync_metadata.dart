import 'dart:convert';

/// How long a deletion tombstone is retained before it can be pruned.
/// Devices that stay offline longer than this may resurrect deleted records.
const Duration kTombstoneRetention = Duration(days: 365);

/// Explicit modification-time fields. When present they are authoritative and
/// must not be beaten by a future due date or lease end date.
const List<String> kExplicitTimestampKeys = [
  'updatedAt',
  'modifiedAt',
  'lastModified',
];

/// Fallback fields used for legacy records that predate `updatedAt`.
const List<String> kLegacyTimestampKeys = [
  'completedAt',
  'paidDate',
  'depositDate',
  'uploadedDate',
  'createdAt',
  'date',
  'dueDate',
  'joinDate',
];

/// Returns the newest known modification time for a serialized record.
DateTime? recordUpdatedAt(dynamic raw) {
  if (raw is! Map) return null;

  DateTime? newestFor(List<String> keys) {
    DateTime? newest;
    for (final key in keys) {
      final value = raw[key];
      if (value is! String || value.isEmpty) continue;
      final parsed = DateTime.tryParse(value);
      if (parsed == null) continue;
      if (newest == null || parsed.isAfter(newest)) newest = parsed;
    }
    return newest;
  }

  return newestFor(kExplicitTimestampKeys) ?? newestFor(kLegacyTimestampKeys);
}

/// Parses tombstones stored either as the legacy `["id", ...]` list or the
/// newer `{"id": "deletedAtIso", ...}` map.
///
/// [legacyTime] is assigned to entries that carry no timestamp. Callers should
/// pass the remote snapshot time when reading a backup so old deletions are not
/// treated as if they happened today.
Map<String, DateTime> parseTombstones(dynamic raw, {DateTime? legacyTime}) {
  final fallback = legacyTime ?? DateTime.now();
  final out = <String, DateTime>{};
  if (raw == null) return out;

  dynamic decoded = raw;
  if (raw is String) {
    if (raw.isEmpty) return out;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return out;
    }
  }

  if (decoded is Map) {
    for (final entry in decoded.entries) {
      final id = entry.key.toString().trim();
      if (id.isEmpty || id == 'null') continue;
      final value = entry.value;
      final parsed = value is String ? DateTime.tryParse(value) : null;
      out[id] = parsed ?? fallback;
    }
    return out;
  }

  if (decoded is List) {
    for (final value in decoded) {
      final id = value.toString().trim();
      if (id.isEmpty || id == 'null') continue;
      out[id] = fallback;
    }
  }
  return out;
}

/// Serializes tombstones into the versioned map format.
Map<String, String> encodeTombstones(Map<String, DateTime> tombstones) => {
  for (final entry in tombstones.entries)
    entry.key: entry.value.toUtc().toIso8601String(),
};

/// Drops tombstones older than [kTombstoneRetention].
void pruneTombstones(Map<String, DateTime> tombstones, {DateTime? now}) {
  final cutoff = (now ?? DateTime.now()).subtract(kTombstoneRetention);
  tombstones.removeWhere((_, deletedAt) => deletedAt.isBefore(cutoff));
}
