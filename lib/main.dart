import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'features/schedule/data/local_schedule_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  final preferences = await SharedPreferences.getInstance();
  final shouldShowOnboarding =
      !(preferences.getBool('onboarding_completed') ?? false);

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await LocalScheduleNotifications.instance.initialize();
    try {
      await Firebase.initializeApp();
    } catch (_) {
      // Firebase configuration is optional for local-only development.
    }
  }

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  final configured = supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  if (configured) {
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  }

  runApp(
    ProviderScope(
      child: MotorCareApp(
        supabaseConfigured: configured,
        shouldShowOnboarding: shouldShowOnboarding,
      ),
    ),
  );
}
