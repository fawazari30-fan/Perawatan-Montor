import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/cache/offline_cache.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/controllers/auth_controller.dart';
import '../../schedule/data/local_schedule_notifications.dart';
import '../../schedule/presentation/controllers/schedule_controller.dart';
import '../../notification/data/push_notification_service.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  bool _savingNotificationSettings = false;
  bool _notificationsEnabled = true;
  bool _preferencesLoaded = false;
  int _remindDaysBefore = 3;
  int _remindHour = 7;
  int _remindKmBefore = 200;
  String? _message;
  bool _hasError = false;

  User get _user => Supabase.instance.client.auth.currentUser!;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
      text: _user.userMetadata?['full_name'] as String? ?? '',
    );
    _phone = TextEditingController(
      text: _user.userMetadata?['phone'] as String? ?? '',
    );
    _loadNotificationSettings();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(
          data: {'full_name': _name.text.trim(), 'phone': _phone.text.trim()},
        ),
      );
      await Supabase.instance.client.from('profiles').upsert({
        'id': _user.id,
        'full_name': _name.text.trim(),
        'phone': _phone.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _editing = false;
        _message = 'Profil berhasil diperbarui.';
        _hasError = false;
      });
    } on PostgrestException {
      if (!mounted) return;
      setState(() {
        _message = 'Profil belum tersimpan. Periksa koneksi dan coba lagi.';
        _hasError = true;
      });
    } on AuthException {
      if (!mounted) return;
      setState(() {
        _message = 'Profil belum tersimpan. Periksa koneksi dan coba lagi.';
        _hasError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _message = 'Profil belum tersimpan. Periksa koneksi dan coba lagi.';
        _hasError = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final row = await Supabase.instance.client
          .from('user_settings')
          .select(
            'push_enabled, remind_days_before, remind_hour, remind_km_before',
          )
          .eq('user_id', _user.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _notificationsEnabled = row?['push_enabled'] as bool? ?? true;
        _remindDaysBefore = row?['remind_days_before'] as int? ?? 3;
        _remindHour = row?['remind_hour'] as int? ?? 7;
        _remindKmBefore = row?['remind_km_before'] as int? ?? 200;
        _preferencesLoaded = true;
      });
      await _saveLocalNotificationSettings();
    } catch (_) {
      final local = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _notificationsEnabled =
              local.getBool(_notificationKey('enabled')) ?? true;
          _remindDaysBefore = local.getInt(_notificationKey('days')) ?? 3;
          _remindHour = local.getInt(_notificationKey('hour')) ?? 7;
          _remindKmBefore = local.getInt(_notificationKey('km')) ?? 200;
          _preferencesLoaded = true;
        });
      }
    }
  }

  Future<void> _saveNotificationSettings() async {
    setState(() => _savingNotificationSettings = true);
    try {
      await Supabase.instance.client.from('user_settings').upsert({
        'user_id': _user.id,
        'push_enabled': _notificationsEnabled,
        'remind_days_before': _remindDaysBefore,
        'remind_hour': _remindHour,
        'remind_km_before': _remindKmBefore,
      });
      await _saveLocalNotificationSettings();
      if (_notificationsEnabled) {
        await LocalScheduleNotifications.instance.requestPermission();
      }
      await ref
          .read(scheduleListControllerProvider.notifier)
          .syncNotifications();
      if (mounted) {
        setState(() {
          _message = 'Pengaturan pengingat berhasil disimpan.';
          _hasError = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Pengaturan pengingat belum tersimpan. Coba lagi.';
          _hasError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _savingNotificationSettings = false);
    }
  }

  String _notificationKey(String suffix) =>
      'rawat_motor_cache:v1:${_user.id}:notification_$suffix';

  Future<void> _saveLocalNotificationSettings() async {
    final local = await SharedPreferences.getInstance();
    await local.setBool(_notificationKey('enabled'), _notificationsEnabled);
    await local.setInt(_notificationKey('days'), _remindDaysBefore);
    await local.setInt(_notificationKey('hour'), _remindHour);
    await local.setInt(_notificationKey('km'), _remindKmBefore);
  }

  Future<void> _changePassword() async {
    final current = _currentPassword.text;
    final next = _newPassword.text;
    if (current.isEmpty) {
      setState(() {
        _message = 'Masukkan kata sandi saat ini.';
        _hasError = true;
      });
      return;
    }
    if (next.length < 8 ||
        !RegExp(r'[A-Za-z]').hasMatch(next) ||
        !RegExp(r'[0-9]').hasMatch(next)) {
      setState(() {
        _message = 'Kata sandi baru harus berisi minimal 8 karakter, huruf, dan angka.';
        _hasError = true;
      });
      return;
    }
    if (next != _confirmPassword.text) {
      setState(() {
        _message = 'Konfirmasi kata sandi baru tidak cocok.';
        _hasError = true;
      });
      return;
    }
    setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;
      await client.auth.signInWithPassword(
        email: _user.email!,
        password: current,
      );
      await client.auth.updateUser(UserAttributes(password: next));
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
      if (mounted) {
        setState(() {
          _message = 'Kata sandi berhasil diperbarui.';
          _hasError = false;
        });
      }
    } on AuthException {
      if (mounted) {
        setState(() {
          _message = 'Kata sandi saat ini tidak cocok atau pembaruan gagal.';
          _hasError = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = 'Kata sandi belum dapat diperbarui. Coba lagi.';
          _hasError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteAccount() async {
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus akun secara permanen?'),
        content: const Text(
          'Motor, jadwal, riwayat servis, dan foto milik akun ini akan dihapus. Tindakan ini tidak dapat dibatalkan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Lanjutkan'),
          ),
        ],
      ),
    );
    if (firstConfirm != true || !mounted) return;

    final confirmation = TextEditingController();
    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Konfirmasi kedua'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ketik HAPUS untuk menghapus akun.'),
              const SizedBox(height: 12),
              TextField(
                controller: confirmation,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(labelText: 'Ketik HAPUS'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: confirmation.text == 'HAPUS'
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('Hapus akun'),
            ),
          ],
        ),
      ),
    );
    confirmation.dispose();
    if (secondConfirm != true || !mounted) return;

    setState(() => _saving = true);
    try {
      await Supabase.instance.client.functions.invoke('delete-account');
      await LocalScheduleNotifications.instance.cancelAll();
      await PushNotificationService.unregisterCurrentDevice(
        Supabase.instance.client,
      );
      await OfflineCache.clearUser(_user.id);
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    } on FunctionException catch (error) {
      if (mounted) {
        setState(() {
          _message = error.details is Map && error.details['error'] is String
              ? error.details['error'] as String
              : 'Akun belum dapat dihapus. Coba lagi atau hubungi pengelola aplikasi.';
          _hasError = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message =
              'Akun belum dapat dihapus. Periksa koneksi lalu coba lagi.';
          _hasError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: const Text('Anda perlu masuk kembali untuk mengakses data.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await LocalScheduleNotifications.instance.cancelAll();
      await PushNotificationService.stop();
      await OfflineCache.clearUser(_user.id);
      await ref.read(authControllerProvider.notifier).signOut();
    }
  }

  Future<void> _showAbout() async {
    final package = await PackageInfo.fromPlatform();
    if (!mounted) return;
    showAboutDialog(
      context: context,
      applicationName: 'Rawat Motor',
      applicationVersion: '${package.version} (${package.buildNumber})',
      applicationIcon: const Icon(Icons.two_wheeler_rounded),
      children: const [
        Text('Aplikasi untuk memantau motor dan mengatur perawatan berkala.'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final verified = _user.emailConfirmedAt != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Profil dan pengaturan')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.paleBlue,
              child: Text(
                _name.text.trim().isEmpty
                    ? '?'
                    : _name.text.trim().characters.first.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.blue,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _name.text.trim().isEmpty ? 'Pengguna Rawat Motor' : _name.text,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              _user.email ?? '',
              style: const TextStyle(color: AppColors.muted),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Chip(
              avatar: Icon(
                verified
                    ? Icons.verified_rounded
                    : Icons.mark_email_unread_outlined,
                size: 18,
              ),
              label: Text(
                verified ? 'Email terverifikasi' : 'Email belum terverifikasi',
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_message != null) ...[
            _Message(message: _message!, isError: _hasError),
            const SizedBox(height: 12),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Informasi pribadi',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => setState(() {
                                  _editing = !_editing;
                                  _message = null;
                                }),
                          child: Text(_editing ? 'Batal' : 'Ubah'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _name,
                      enabled: _editing,
                      decoration: const InputDecoration(
                        labelText: 'Nama lengkap',
                      ),
                      validator: (value) => (value?.trim().length ?? 0) < 2
                          ? 'Nama minimal 2 karakter.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      enabled: _editing,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Nomor telepon',
                      ),
                    ),
                    if (_editing) ...[
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _saving ? null : _saveProfile,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Simpan profil'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Ubah kata sandi',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _currentPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Kata sandi saat ini',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _newPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Kata sandi baru',
                      helperText: 'Minimal 8 karakter, berisi huruf dan angka',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _confirmPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Ulangi kata sandi baru',
                    ),
                  ),
                  const SizedBox(height: 14),
                  OutlinedButton(
                    onPressed: _saving ? null : _changePassword,
                    child: const Text('Perbarui kata sandi'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Pengaturan pengingat',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _notificationsEnabled,
                    onChanged:
                        !_preferencesLoaded || _savingNotificationSettings
                        ? null
                        : (value) =>
                              setState(() => _notificationsEnabled = value),
                    title: const Text('Aktifkan notifikasi perawatan'),
                    subtitle: const Text(
                      'Pengingat lokal dapat berbunyi tanpa internet.',
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Jam pengingat'),
                    trailing: DropdownButton<int>(
                      value: _remindHour,
                      onChanged:
                          _notificationsEnabled && !_savingNotificationSettings
                          ? (value) => setState(() => _remindHour = value ?? 7)
                          : null,
                      items: List.generate(
                        24,
                        (hour) => DropdownMenuItem(
                          value: hour,
                          child: Text('${hour.toString().padLeft(2, '0')}:00'),
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pengingat sebelum jatuh tempo'),
                    trailing: DropdownButton<int>(
                      value: _remindDaysBefore,
                      onChanged:
                          _notificationsEnabled && !_savingNotificationSettings
                          ? (value) =>
                                setState(() => _remindDaysBefore = value ?? 3)
                          : null,
                      items: const [1, 3, 7]
                          .map(
                            (days) => DropdownMenuItem(
                              value: days,
                              child: Text('$days hari'),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pengingat berbasis odometer'),
                    trailing: DropdownButton<int>(
                      value: _remindKmBefore,
                      onChanged:
                          _notificationsEnabled && !_savingNotificationSettings
                          ? (value) =>
                                setState(() => _remindKmBefore = value ?? 200)
                          : null,
                      items: const [100, 200, 500]
                          .map(
                            (km) => DropdownMenuItem(
                              value: km,
                              child: Text('$km km'),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  FilledButton(
                    onPressed:
                        !_preferencesLoaded || _savingNotificationSettings
                        ? null
                        : _saveNotificationSettings,
                    child: _savingNotificationSettings
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Simpan pengaturan pengingat'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.help_outline_rounded),
                  title: const Text('Pusat bantuan'),
                  subtitle: const Text('Panduan dasar penggunaan aplikasi'),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Pusat bantuan'),
                      content: const Text(
                        'Tambahkan motor, buat jadwal perawatan, lalu catat servis setelah dilakukan. Odometer dapat diperbarui dari Beranda.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Mengerti'),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.policy_outlined),
                  title: const Text('Kebijakan privasi'),
                  subtitle: const Text('Data akun dan perawatan motor'),
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Kebijakan privasi'),
                      content: const Text(
                        'Data akun, motor, jadwal, dan catatan servis digunakan untuk menyediakan fitur Rawat Motor. Data disimpan pada proyek Supabase yang dikonfigurasi oleh pengelola aplikasi. Hubungi pengelola aplikasi untuk permintaan akses atau penghapusan data.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Tutup'),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline_rounded),
                  title: const Text('Tentang aplikasi'),
                  onTap: _showAbout,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _saving ? null : _deleteAccount,
            icon: const Icon(Icons.delete_forever_outlined, color: Colors.red),
            label: const Text(
              'Hapus akun dan seluruh data',
              style: TextStyle(color: Colors.red),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Keluar dari akun'),
          ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.message, required this.isError});
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: isError ? const Color(0xFFFFEEEE) : AppColors.paleBlue,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(message),
  );
}
