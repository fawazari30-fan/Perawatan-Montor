import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../motorcycle/presentation/controllers/motorcycle_controller.dart';
import '../../domain/entities/maintenance_schedule.dart';
import '../controllers/schedule_controller.dart';

class AddSchedulePage extends ConsumerStatefulWidget {
  const AddSchedulePage({this.schedule, super.key});

  final MaintenanceSchedule? schedule;

  @override
  ConsumerState<AddSchedulePage> createState() => _AddSchedulePageState();
}

class _AddSchedulePageState extends ConsumerState<AddSchedulePage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _intervalKm = TextEditingController();
  final _intervalDays = TextEditingController();
  final _lastDoneKm = TextEditingController();
  MaintenanceType _type = MaintenanceType.defaults.first;
  DateTime _lastDoneDate = DateTime.now();
  bool _isSaving = false;
  String? _errorMessage;

  bool get _isEditing => widget.schedule != null;

  @override
  void initState() {
    super.initState();
    final schedule = widget.schedule;
    if (schedule != null) {
      _type = MaintenanceType.defaults.firstWhere(
        (type) => type.code == schedule.typeCode,
        orElse: () => MaintenanceType.defaults.first,
      );
      _title.text = schedule.title;
      _intervalKm.text = schedule.intervalKm?.toString() ?? '';
      _intervalDays.text = schedule.intervalDays?.toString() ?? '';
      _lastDoneKm.text = schedule.lastDoneKm.toString();
      _lastDoneDate = schedule.lastDoneDate ?? DateTime.now();
      return;
    }
    final activeId = ref.read(activeMotorcycleIdProvider);
    final motorcycles = ref.read(motorcycleListControllerProvider).valueOrNull;
    for (final motorcycle in motorcycles ?? const []) {
      if (motorcycle.id == activeId) {
        _lastDoneKm.text = motorcycle.odometerKm.toString();
        break;
      }
    }
    _intervalKm.text = _type.defaultIntervalKm?.toString() ?? '';
    _intervalDays.text = _type.defaultIntervalDays?.toString() ?? '';
  }

  @override
  void dispose() {
    _title.dispose();
    _intervalKm.dispose();
    _intervalDays.dispose();
    _lastDoneKm.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _lastDoneDate,
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
    );
    if (selected != null) setState(() => _lastDoneDate = selected);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final km = int.tryParse(_intervalKm.text);
    final days = int.tryParse(_intervalDays.text);
    if (km == null && days == null) {
      setState(
        () => _errorMessage = 'Isi interval kilometer atau interval hari.',
      );
      return;
    }
    final lastKm = int.tryParse(_lastDoneKm.text);
    if (lastKm == null || lastKm < 0) {
      setState(() => _errorMessage = 'Masukkan odometer servis terakhir.');
      return;
    }
    final activeId = ref.read(activeMotorcycleIdProvider);
    final motorcycles = ref.read(motorcycleListControllerProvider).valueOrNull;
    final activeMotorcycle = motorcycles
        ?.where((motorcycle) => motorcycle.id == activeId)
        .firstOrNull;
    if (activeMotorcycle != null && lastKm > activeMotorcycle.odometerKm) {
      setState(
        () => _errorMessage =
            'Odometer servis terakhir tidak boleh melebihi odometer motor.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });
    final controller = ref.read(scheduleListControllerProvider.notifier);
    final result = _isEditing
        ? await controller.updateSchedule(
            id: widget.schedule!.id,
            typeCode: _type.code,
            title: _title.text.trim().isEmpty ? _type.name : _title.text.trim(),
            intervalKm: km,
            intervalDays: days,
            lastDoneKm: lastKm,
            lastDoneDate: _lastDoneDate,
          )
        : await controller.createSchedule(
            typeCode: _type.code,
            title: _title.text.trim().isEmpty ? _type.name : _title.text.trim(),
            intervalKm: km,
            intervalDays: days,
            lastDoneKm: lastKm,
            lastDoneDate: _lastDoneDate,
          );
    if (!mounted) return;
    result.match(
      (failure) => setState(() => _errorMessage = failure.message),
      (_) => Navigator.of(context).pop(),
    );
    setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit jadwal' : 'Buat jadwal')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Atur pengingat perawatan',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            _label('Jenis perawatan'),
            DropdownButtonFormField<MaintenanceType>(
              initialValue: _type,
              items: MaintenanceType.defaults
                  .map(
                    (type) =>
                        DropdownMenuItem(value: type, child: Text(type.name)),
                  )
                  .toList(),
              onChanged: (type) {
                if (type == null) return;
                setState(() {
                  _type = type;
                  _intervalKm.text = type.defaultIntervalKm?.toString() ?? '';
                  _intervalDays.text =
                      type.defaultIntervalDays?.toString() ?? '';
                });
              },
            ),
            const SizedBox(height: 16),
            _label('Nama jadwal (opsional)'),
            TextFormField(
              controller: _title,
              decoration: InputDecoration(hintText: _type.name),
            ),
            const SizedBox(height: 16),
            _label('Interval kilometer (opsional)'),
            TextFormField(
              controller: _intervalKm,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '2000 km'),
              validator: _positiveOrEmpty,
            ),
            const SizedBox(height: 16),
            _label('Interval hari (opsional)'),
            TextFormField(
              controller: _intervalDays,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '60 hari'),
              validator: _positiveOrEmpty,
            ),
            const SizedBox(height: 16),
            _label('Odometer terakhir dilakukan'),
            TextFormField(
              controller: _lastDoneKm,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Contoh: 12000',
                suffixText: 'km',
              ),
            ),
            const SizedBox(height: 16),
            _label('Tanggal terakhir dilakukan'),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(
                '${_lastDoneDate.day.toString().padLeft(2, '0')}/'
                '${_lastDoneDate.month.toString().padLeft(2, '0')}/'
                '${_lastDoneDate.year}',
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Pengingat akan jatuh tempo saat interval kilometer atau hari tercapai lebih dulu.',
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                style: const TextStyle(color: Color(0xFF8C3232)),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(_isEditing ? 'Simpan perubahan' : 'Simpan jadwal'),
            ),
          ],
        ),
      ),
    );
  }

  String? _positiveOrEmpty(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final number = int.tryParse(value);
    if (number == null || number <= 0) return 'Interval harus lebih dari nol.';
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
