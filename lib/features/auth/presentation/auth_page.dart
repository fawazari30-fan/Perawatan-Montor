import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import 'controllers/auth_controller.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({required this.supabaseConfigured, super.key});

  final bool supabaseConfigured;

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isRegistering = false;
  bool _acceptedTerms = false;
  bool _hidePassword = true;
  String? _localMessage;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isRegistering && !_acceptedTerms) {
      setState(
        () => _localMessage =
            'Setujui Syarat dan Kebijakan Privasi untuk melanjutkan.',
      );
      return;
    }
    if (!widget.supabaseConfigured) {
      setState(
        () => _localMessage = 'Konfigurasi Supabase belum diatur. Tambahkan URL dan anon key saat menjalankan aplikasi.',
      );
      return;
    }

    setState(() => _localMessage = null);
    final controller = ref.read(authControllerProvider.notifier);
    if (_isRegistering) {
      await controller.register(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
      );
    } else {
      await controller.signIn(
        email: _email.text.trim(),
        password: _password.text,
      );
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _email.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      setState(
        () => _localMessage = 'Masukkan email yang valid terlebih dahulu untuk menerima tautan reset.',
      );
      return;
    }
    if (!widget.supabaseConfigured) {
      setState(
        () => _localMessage = 'Konfigurasi Supabase belum diatur sehingga reset sandi belum tersedia.',
      );
      return;
    }

    setState(() => _localMessage = null);
    await ref.read(authControllerProvider.notifier).sendPasswordReset(email);
  }

  @override
  Widget build(BuildContext context) {
    final authState = widget.supabaseConfigured
        ? ref.watch(authControllerProvider)
        : const AuthState();
    final isRegistering = _isRegistering;
    final message = _localMessage ?? authState.message;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _BrandMark(),
                  const SizedBox(height: 36),
                  Text(
                    isRegistering
                        ? 'Mulai rawat motor lebih mudah'
                        : 'Selamat datang',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.7,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isRegistering
                        ? 'Buat akun untuk menyimpan jadwal dan riwayat servis motor Anda.'
                        : 'Pantau kondisi motor dan jangan lewatkan jadwal perawatannya.',
                    style: const TextStyle(color: AppColors.muted, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  if (!widget.supabaseConfigured) ...[
                    const _ConfigurationNotice(),
                    const SizedBox(height: 18),
                  ],
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isRegistering) ...[
                          const _FieldLabel('Nama lengkap'),
                          TextFormField(
                            controller: _name,
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.name],
                            decoration: const InputDecoration(
                              hintText: 'Nama Anda',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            validator: (value) {
                              if (_isRegistering &&
                                  (value?.trim().length ?? 0) < 2) {
                                return 'Masukkan nama lengkap Anda.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),
                          const _FieldLabel('Nomor telepon'),
                          TextFormField(
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [
                              AutofillHints.telephoneNumber,
                            ],
                            decoration: const InputDecoration(
                              hintText: '08xxxxxxxxxx',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                            validator: (value) {
                              if (_isRegistering &&
                                  (value
                                              ?.replaceAll(RegExp(r'\D'), '')
                                              .length ??
                                          0) <
                                      8) {
                                return 'Masukkan nomor telepon yang valid.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 18),
                        ],
                        const _FieldLabel('Email'),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            hintText: 'nama@email.com',
                            prefixIcon: Icon(Icons.mail_outline_rounded),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            if (!email.contains('@') || !email.contains('.')) {
                              return 'Masukkan alamat email yang valid.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        const _FieldLabel('Kata sandi'),
                        TextFormField(
                          controller: _password,
                          obscureText: _hidePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: [
                            isRegistering
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            hintText: isRegistering
                                ? 'Minimal 8 karakter'
                                : 'Masukkan kata sandi',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _hidePassword
                                  ? 'Tampilkan kata sandi'
                                  : 'Sembunyikan kata sandi',
                              onPressed: () => setState(
                                () => _hidePassword = !_hidePassword,
                              ),
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) {
                            final password = value ?? '';
                            if (password.length < 8) {
                              return 'Kata sandi minimal 8 karakter.';
                            }
                            if (isRegistering &&
                                (!RegExp(r'[A-Za-z]').hasMatch(password) ||
                                    !RegExp(r'[0-9]').hasMatch(password))) {
                              return 'Gunakan kombinasi huruf dan angka.';
                            }
                            return null;
                          },
                        ),
                        if (isRegistering) ...[
                          const SizedBox(height: 8),
                          CheckboxListTile(
                            value: _acceptedTerms,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text(
                              'Saya menyetujui Syarat dan Kebijakan Privasi.',
                              style: TextStyle(fontSize: 13, height: 1.35),
                            ),
                            onChanged: (value) =>
                                setState(() => _acceptedTerms = value ?? false),
                          ),
                        ] else
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: authState.isLoading
                                  ? null
                                  : _sendPasswordReset,
                              child: const Text('Lupa kata sandi?'),
                            ),
                          ),
                        if (message != null) ...[
                          const SizedBox(height: 10),
                          _MessageBanner(
                            message: message,
                            isError:
                                _localMessage != null || authState.hasError,
                          ),
                          const SizedBox(height: 16),
                        ],
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: authState.isLoading ? null : _submit,
                          child: authState.isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(isRegistering ? 'Buat akun' : 'Masuk'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          isRegistering
                              ? 'Sudah punya akun?'
                              : 'Belum punya akun?',
                          style: const TextStyle(color: AppColors.muted),
                        ),
                        TextButton(
                          onPressed: authState.isLoading
                              ? null
                              : () => setState(() {
                                  _isRegistering = !_isRegistering;
                                  _localMessage = null;
                                }),
                          child: Text(isRegistering ? 'Masuk' : 'Daftar'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Center(
                    child: Text(
                      'Data motor dan riwayat servis Anda tersimpan dengan aman.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.paleBlue,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.two_wheeler_rounded,
            color: AppColors.blue,
            size: 28,
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rawat Motor',
              style: TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            Text(
              'Perawatan lebih teratur',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConfigurationNotice extends StatelessWidget {
  const _ConfigurationNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5DF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF3D99C)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF9C6A00)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Mode tampilan aktif. Supabase belum dikonfigurasi, jadi autentikasi belum dapat diproses.',
              style: TextStyle(color: Color(0xFF705315), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.navy,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final foreground = isError ? const Color(0xFF8C3232) : AppColors.navy;
    final background = isError ? const Color(0xFFFFEEEE) : AppColors.paleBlue;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: TextStyle(color: foreground, height: 1.4)),
    );
  }
}
