import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PushNotificationService {
  PushNotificationService._();

  static StreamSubscription<String>? _tokenSubscription;
  static String? _registeredToken;

  static bool get _isSupportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> registerCurrentDevice(SupabaseClient client) async {
    final userId = client.auth.currentUser?.id;
    if (!_isSupportedPlatform || userId == null || Firebase.apps.isEmpty) {
      return;
    }
    try {
      await FirebaseMessaging.instance.requestPermission();
      await _tokenSubscription?.cancel();
      _tokenSubscription = FirebaseMessaging.instance.onRegistered.listen(
        (nextToken) => _saveToken(client, userId, nextToken),
      );
      await FirebaseMessaging.instance.register();
    } catch (_) {
      // Push is optional; local notifications continue to work without it.
    }
  }

  static Future<void> unregisterCurrentDevice(SupabaseClient client) async {
    final userId = client.auth.currentUser?.id;
    if (!_isSupportedPlatform || userId == null || Firebase.apps.isEmpty) {
      await stop();
      return;
    }
    try {
      final token = _registeredToken;
      if (token != null) {
        await client
            .from('device_tokens')
            .delete()
            .eq('user_id', userId)
            .eq('token', token);
      }
      await FirebaseMessaging.instance.unregister();
    } catch (_) {
      // Device token cleanup can be retried the next time the user signs in.
    }
    await stop();
  }

  static Future<void> stop() async {
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
    _registeredToken = null;
  }

  static Future<void> _saveToken(
    SupabaseClient client,
    String userId,
    String token,
  ) async {
    await client.from('device_tokens').upsert({
      'user_id': userId,
      'token': token,
      'platform': 'android',
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,token');
    _registeredToken = token;
  }
}
