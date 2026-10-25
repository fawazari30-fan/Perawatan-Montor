import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../schedule/domain/entities/maintenance_schedule.dart';
import '../../../schedule/presentation/controllers/schedule_controller.dart';
import '../../domain/entities/motorcycle.dart';
import '../controllers/motorcycle_controller.dart';

class AddMotorcyclePage extends ConsumerStatefulWidget {
  const AddMotorcyclePage({this.motorcycle, super.key});

  final Motorcycle? motorcycle;

  @override
  ConsumerState<AddMotorcyclePage> createState() => _AddMotorcyclePageState();
}

class _AddMotorcyclePageState extends ConsumerState<AddMotorcyclePage> {
  final _formKey = GlobalKey<FormState>();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final _plate = TextEditingController();
  final _color = TextEditingController();
  final _odometer = TextEditingController();
  final _correctionReason = TextEditingController();
  final _imagePicker = ImagePicker();
  XFile? _selectedPhoto;
  bool _removePhoto = false;
  MotorcycleType _type = MotorcycleType.matic;
  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditing => widget.motorcycle != null;

  @override
  void initState() {
    super.initState();
    final motor = widget.motorcycle;
    _brand.text = motor?.brand ?? '';
    _model.text = motor?.model ?? '';
    _year.text = (motor?.year ?? DateTime.now().year).toString();
    _plate.text = motor?.plateNumber ?? '';
    _color.text = motor?.color ?? '';
    _odometer.text = (motor?.odometerKm ?? 0).toString();
    _type = motor?.type ?? MotorcycleType.matic;
  }

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _year.dispose();
    _plate.dispose();
    _color.dispose();
    _odometer.dispose();
    _correctionReason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final original = widget.motorcycle;
    final km = int.parse(_odometer.text);
    final reason = _correctionReason.text.trim();
    if (original != null && km < original.odometerKm && reason.isEmpty) {
      setState(
        () => _errorMessage =
            'Masukkan alasan jika odometer dikoreksi menjadi lebih rendah.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    Uint8List? photoBytes;
    if (_selectedPhoto != null) {
      try {
        photoBytes = await FlutterImageCompress.compressWithList(
          await _selectedPhoto!.readAsBytes(),
          minWidth: 1280,
          minHeight: 1280,
          quality: 80,
          format: CompressFormat.jpeg,
        );
        if (photoBytes.lengthInBytes > 1048576) {
          throw const FormatException();
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _isSaving = false;
            _errorMessage = 'Foto gagal dikompres hingga batas 1 MB. Pilih foto yang lebih kecil.';
          });
        }
        return;
      }
    }

    final controller = ref.read(motorcycleListControllerProvider.notifier);
    final result = original == null
        ? await controller.addMotorcycle(
            brand: _brand.text.trim(),
            model: _model.text.trim(),
            type: _type,
            year: int.parse(_year.text),
            plateNumber: _plate.text.trim().toUpperCase(),
            color: _color.text.trim().isEmpty ? null : _color.text.trim(),
            odometerKm: km,
          )
        : await controller.editMotorcycle(
            original: original,
            brand: _brand.text.trim(),
            model: _model.text.trim(),
            type: _type,
            year: int.parse(_year.text),
            plateNumber: _plate.text.trim().toUpperCase(),
            color: _color.text.trim().isEmpty ? null : _color.text.trim(),
            odometerKm: km,
            correctionReason: reason.isEmpty ? null : reason,
          );

    if (!mounted) return;
    final errorMessage = result.match(
      (failure) => failure.message,
      (_) => null,
    );
    if (errorMessage != null) {
      setState(() {
        _isSaving = false;
        _errorMessage = errorMessage;
      });
      return;
    }
    final motorcycle = result.match((_) => null, (value) => value);
    if (motorcycle == null) return;
    if (photoBytes != null || _removePhoto) {
      final photoResult = await controller.updateMotorcyclePhoto(
        motorcycle: motorcycle,
        imageBytes: photoBytes,
        removePhoto: _removePhoto,
      );
      final photoError = photoResult.match(
        (failure) => failure.message,
        (_) => null,
      );
      if (photoError != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(photoError)));
      }
    }
    if (original == null) await _offerStandardSchedules(motorcycle);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _pickPhoto() async {
    try {
      final photo = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
        requestFullMetadata: false,
      );
      if (photo != null && mounted) {
        setState(() {
          _selectedPhoto = photo;
          _removePhoto = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Foto tidak dapat dibuka. Periksa izin galeri.',
        );
      }
    }
  }

  Future<void> _offerStandardSchedules(Motorcycle motorcycle) async {
    final create = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tambahkan jadwal standar?'),
        content: const Text(
          'Kita bisa menyiapkan jadwal oli, rem, aki, ban, filter udara, dan servis berkala. Jadwal dapat diubah kapan saja.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Nanti saja'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tambahkan'),
          ),
        ],
      ),
    );
    if (create != true || !mounted) return;

    var failed = false;
    for (final type in MaintenanceType.defaults.where(
      (item) => item.code != 'other',
    )) {
      if (type.defaultIntervalKm == null && type.defaultIntervalDays == null) {
        continue;
      }
      final result = await ref
          .read(scheduleListControllerProvider.notifier)
          .createSchedule(
            typeCode: type.code,
            title: type.name,
            intervalKm: type.defaultIntervalKm,
            intervalDays: type.defaultIntervalDays,
            lastDoneKm: motorcycle.odometerKm,
            lastDoneDate: DateTime.now(),
          );
      if (result.isLeft()) failed = true;
    }
    if (failed && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sebagian jadwal belum tersimpan. Anda dapat menambahkannya dari menu Jadwal.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit motor' : 'Tambah motor')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Text(
                _isEditing ? 'Perbarui informasi motor' : 'Informasi motor',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Data ini membantu kami menyiapkan pemantauan dan pengingat yang sesuai.',
                style: TextStyle(color: AppColors.muted, height: 1.5),
              ),
              const SizedBox(height: 22),
              _label('Foto motor (opsional)'),
              Center(
                child: Column(
                  children: [
                    _photoPreview(),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickPhoto,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(
                            widget.motorcycle?.photoPath == null
                                ? 'Pilih foto'
                                : 'Ganti foto',
                          ),
                        ),
                        if (_selectedPhoto != null ||
                            (widget.motorcycle?.photoPath != null &&
                                !_removePhoto))
                          TextButton.icon(
                            onPressed: () => setState(() {
                              _selectedPhoto = null;
                              _removePhoto = true;
                            }),
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Hapus foto'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _label('Merek'),
              TextFormField(
                controller: _brand,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Contoh: Yamaha'),
                validator: (value) => _required(value, 'Merek'),
              ),
              const SizedBox(height: 16),
              _label('Model'),
              TextFormField(
                controller: _model,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Contoh: NMAX'),
                validator: (value) => _required(value, 'Model'),
              ),
              const SizedBox(height: 16),
              _label('Jenis motor'),
              DropdownButtonFormField<MotorcycleType>(
                initialValue: _type,
                decoration: const InputDecoration(),
                items: MotorcycleType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _type = value);
                },
              ),
              const SizedBox(height: 16),
              _label('Tahun'),
              TextFormField(
                controller: _year,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: '2024'),
                validator: (value) {
                  final year = int.tryParse(value ?? '');
                  final maxYear = DateTime.now().year + 1;
                  if (year == null || year < 1980 || year > maxYear) {
                    return 'Masukkan tahun antara 1980 dan $maxYear.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _label('Nomor polisi'),
              TextFormField(
                controller: _plate,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'B 1234 XYZ'),
                validator: (value) => _required(value, 'Nomor polisi'),
              ),
              const SizedBox(height: 16),
              _label('Warna (opsional)'),
              TextFormField(
                controller: _color,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'Hitam'),
              ),
              const SizedBox(height: 16),
              _label('Odometer saat ini'),
              TextFormField(
                controller: _odometer,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Contoh: 12500',
                  suffixText: 'km',
                ),
                validator: (value) {
                  final km = int.tryParse(value ?? '');
                  if (km == null || km < 0) {
                    return 'Odometer harus berupa angka nol atau lebih.';
                  }
                  return null;
                },
              ),
              if (_isEditing) ...[
                const SizedBox(height: 16),
                _label('Alasan koreksi odometer (jika diturunkan)'),
                TextFormField(
                  controller: _correctionReason,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Contoh: salah input sebelumnya',
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (_errorMessage != null) ...[
                _ErrorBanner(message: _errorMessage!),
                const SizedBox(height: 16),
              ],
              ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_isEditing ? 'Simpan perubahan' : 'Simpan motor'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoPreview() {
    final selected = _selectedPhoto;
    if (selected != null) {
      return FutureBuilder<Uint8List>(
        future: selected.readAsBytes(),
        builder: (context, snapshot) => ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: snapshot.hasData
              ? Image.memory(
                  snapshot.data!,
                  width: 132,
                  height: 132,
                  fit: BoxFit.cover,
                )
              : const SizedBox(
                  width: 132,
                  height: 132,
                  child: Center(child: CircularProgressIndicator()),
                ),
        ),
      );
    }
    final path = widget.motorcycle?.photoPath;
    if (path != null && !_removePhoto) {
      return FutureBuilder<String>(
        future: Supabase.instance.client.storage
            .from('motorcycle-photos')
            .createSignedUrl(path, 3600),
        builder: (context, snapshot) => ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: snapshot.hasData
              ? Image.network(
                  snapshot.data!,
                  width: 132,
                  height: 132,
                  fit: BoxFit.cover,
                )
              : Container(
                  width: 132,
                  height: 132,
                  color: AppColors.paleBlue,
                  child: const Icon(Icons.two_wheeler_rounded, size: 42),
                ),
        ),
      );
    }
    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        color: AppColors.paleBlue,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(
        Icons.two_wheeler_rounded,
        color: AppColors.blue,
        size: 48,
      ),
    );
  }

  String? _required(String? value, String label) {
    if (value == null || value.trim().isEmpty) return '$label wajib diisi.';
    return null;
  }

  Widget _label(String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      value,
      style: const TextStyle(
        color: AppColors.navy,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEEE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(message, style: const TextStyle(color: Color(0xFF8C3232))),
    );
  }
}
