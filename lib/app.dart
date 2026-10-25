import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_page.dart';
import 'features/home/presentation/home_page.dart';
import 'features/notification/presentation/notification_page.dart';
import 'features/notification/data/push_notification_service.dart';
import 'features/onboarding/presentation/onboarding_page.dart';
import 'features/motorcycle/domain/entities/motorcycle.dart';
import 'features/motorcycle/presentation/pages/add_motorcycle_page.dart';
import 'features/profile/presentation/profile_page.dart';
import 'features/record/presentation/pages/service_record_page.dart';
import 'features/record/domain/entities/service_record.dart';
import 'features/schedule/presentation/pages/add_schedule_page.dart';
import 'features/schedule/domain/entities/maintenance_schedule.dart';
import 'features/schedule/presentation/pages/monitoring_page.dart';
import 'features/schedule/presentation/pages/schedule_page.dart';

final appRouterProvider = Provider.family<GoRouter, bool>((
  ref,
  showOnboarding,
) {
  final client = Supabase.instance.client;
  final refresh = ValueNotifier<int>(0);
  final subscription = client.auth.onAuthStateChange.listen(
    (state) {
      refresh.value++;
      if (state.session != null) {
        unawaited(PushNotificationService.registerCurrentDevice(client));
      }
    },
  );
  ref.onDispose(() {
    subscription.cancel();
    refresh.dispose();
  });

  return GoRouter(
    initialLocation: showOnboarding ? '/onboarding' : '/auth',
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = client.auth.currentSession != null;
      final onAuthPage = state.matchedLocation == '/auth';
      final onOnboardingPage = state.matchedLocation == '/onboarding';
      if (!signedIn && onOnboardingPage && showOnboarding) return null;
      if (signedIn && (onAuthPage || onOnboardingPage)) return '/home';
      if (!signedIn && !onAuthPage) return '/auth';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthPage(supabaseConfigured: true),
      ),
      GoRoute(path: '/home', builder: (context, state) => const HomePage()),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfilePage(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationPage(),
      ),
      GoRoute(
        path: '/motorcycles/new',
        builder: (context, state) => const AddMotorcyclePage(),
      ),
      GoRoute(
        path: '/motorcycles/:id/edit',
        builder: (context, state) =>
            AddMotorcyclePage(motorcycle: state.extra! as Motorcycle),
      ),
      GoRoute(
        path: '/schedules',
        builder: (context, state) => const SchedulePage(),
      ),
      GoRoute(
        path: '/schedules/new',
        builder: (context, state) => const AddSchedulePage(),
      ),
      GoRoute(
        path: '/schedules/:id/edit',
        builder: (context, state) =>
            AddSchedulePage(schedule: state.extra! as MaintenanceSchedule),
      ),
      GoRoute(
        path: '/monitoring',
        builder: (context, state) => const MonitoringPage(),
      ),
      GoRoute(
        path: '/records',
        builder: (context, state) => const ServiceRecordPage(),
      ),
      GoRoute(
        path: '/records/new',
        builder: (context, state) => AddServiceRecordPage(
          schedule: state.extra is MaintenanceSchedule
              ? state.extra! as MaintenanceSchedule
              : null,
        ),
      ),
      GoRoute(
        path: '/records/:id/edit',
        builder: (context, state) =>
            AddServiceRecordPage(record: state.extra! as ServiceRecord),
      ),
    ],
  );
});

class MotorCareApp extends ConsumerWidget {
  const MotorCareApp({
    required this.supabaseConfigured,
    this.shouldShowOnboarding = false,
    super.key,
  });

  final bool supabaseConfigured;
  final bool shouldShowOnboarding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!supabaseConfigured) {
      return MaterialApp(
        title: 'Rawat Motor',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const AuthPage(supabaseConfigured: false),
      );
    }

    return MaterialApp.router(
      title: 'Rawat Motor',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: ref.watch(appRouterProvider(shouldShowOnboarding)),
    );
  }
}

