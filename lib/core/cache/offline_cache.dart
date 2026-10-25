import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class OfflineCache {
  const OfflineCache._();

  static String _key(String userId, String resource) =>
      'rawat_motor_cache:v1:$userId:$resource';

  static Future<void> saveRows(
    String userId,
    String resource,
    List<Map<String, dynamic>> rows,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final key = _key(userId, resource);
      await preferences.setString(key, jsonEncode(rows));
      await preferences.setString(
        '$key:synced_at',
        DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {
      // Cache failures must not hide a successful response from Supabase.
    }
  }

  static Future<List<Map<String, dynamic>>?> readRows(
    String userId,
    String resource,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final encoded = preferences.getString(_key(userId, resource));
      if (encoded == null) return null;
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return null;
      return decoded
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveValue(
    String userId,
    String resource,
    String value,
  ) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final key = _key(userId, resource);
      await preferences.setString(key, value);
      await preferences.setString(
        '$key:synced_at',
        DateTime.now().toUtc().toIso8601String(),
      );
    } catch (_) {}
  }

  static Future<String?> readValue(String userId, String resource) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_key(userId, resource));
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime?> lastSyncedAt(String userId, String resource) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final value = preferences.getString(
        '${_key(userId, resource)}:synced_at',
      );
      return value == null ? null : DateTime.tryParse(value)?.toLocal();
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearUser(String userId) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final prefix = 'rawat_motor_cache:v1:$userId:';
      for (final key in preferences.getKeys().where(
        (key) => key.startsWith(prefix),
      )) {
        await preferences.remove(key);
      }
    } catch (_) {}
  }
}
