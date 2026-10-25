import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../motorcycle/presentation/controllers/motorcycle_controller.dart';
import '../../domain/entities/service_record.dart';
import '../../../schedule/domain/entities/maintenance_schedule.dart';
import '../controllers/service_record_controller.dart';

class ServiceRecordPage extends ConsumerStatefulWidget {
  const ServiceRecordPage({super.key});

  @override
  ConsumerState<ServiceRecordPage> createState() => _ServiceRecordPageState();
}

class _ServiceRecordPageState extends ConsumerState<ServiceRecordPage> {
  final _search = TextEditingController();
  int? _year;
  String? _typeCode;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final records = ref.watch(serviceRecordListControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Riwayat servis')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/records/new'),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Catat servis'),
      ),
      body: records.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Riwayat servis belum dapat dimuat.'),
              TextButton(
                onPressed: () => ref
                    .read(serviceRecordListControllerProvider.notifier)
                    .refresh(),
                child: const Text('Coba lagi'),
              ),
            ],
          ),
        ),
        data: (items) => items.isEmpty
            ? const _EmptyRecords()
            : RefreshIndicator(
                onRefresh: () => ref
                    .read(serviceRecordListControllerProvider.notifier)
                    .refresh(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    Builder(
                      builder: (context) {
                        final years =
                            items
                                .map((item) => item.serviceDate.year)
                                .toSet()
                                .toList()
                              ..sort((a, b) => b.compareTo(a));
                        final query = _search.text.trim().toLowerCase();
                        final visible = items.where((record) {
                          final matchesYear =
                              _year == null || record.serviceDate.year == _year;
                          final matchesType =
                              _typeCode == null || record.typeCode == _typeCode;
                          final matchesText =
                              query.isEmpty ||
                              record.title.toLowerCase().contains(query) ||
                              (record.workshop?.toLowerCase().contains(query) ??
                                  false);
                          return matchesYear && matchesType && matchesText;
                        }).toList();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _search,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                labelText: 'Cari bengkel atau catatan',
                                prefixIcon: const Icon(Icons.search_rounded),
                                suffixIcon: _search.text.isEmpty
                                    ? null
                                    : IconButton(
                                        tooltip: 'Hapus pencarian',
                                        onPressed: () =>
                                            setState(_search.clear),
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<int?>(
                                    initialValue: _year,
                                    decoration: const InputDecoration(
                                      labelText: 'Tahun',
                                    ),
                                    items: [
                                      const DropdownMenuItem<int?>(
                                        value: null,
                                        child: Text('Semua tahun'),
                                      ),
                                      ...years.map(
                                        (year) => DropdownMenuItem<int?>(
                                          value: year,
                                          child: Text('$year'),
                                        ),
                                      ),
                                    ],
                                    onChanged: (value) =>
                                        setState(() => _year = value),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: DropdownButtonFormField<String?>(
                                    initialValue: _typeCode,
                                    decoration: const InputDecoration(
                                      labelText: 'Jenis',
                                    ),
                                    items: [
                                      const DropdownMenuItem<String?>(
                                        value: null,
                                        child: Text('Semua jenis'),
                                      ),
                                      ...MaintenanceType.defaults.map(
                                        (type) => DropdownMenuItem<String?>(
                                          value: type.code,
                                          child: Text(
                                            type.name,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                    onChanged: (value) =>
                                        setState(() => _typeCode = value),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _RecordSummary(records: visible),
                            const SizedBox(height: 20),
                            if (visible.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Tidak ada catatan yang cocok dengan filter.',
                                ),
                              )
                            else
                              for (final record in visible) ...[
                                _RecordCard(record: record),
                                const SizedBox(height: 10),
                              ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _RecordSummary extends StatelessWidget {
  const _RecordSummary({required this.records});

  final List<ServiceRecord> records;

  @override
  Widget build(BuildContext context) {
    final cost = records.fold<int>(0, (sum, item) => sum + item.cost);
    final money = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(cost);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${records.length} catatan servis',
                  style: const TextStyle(color: Color(0xFFD5E0F0)),
                ),
                const SizedBox(height: 3),
                Text(
                  money,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordCard extends ConsumerWidget {
  const _RecordCard({required this.record});

  final ServiceRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = DateFormat('d MMM yyyy', 'id_ID').format(record.serviceDate);
    final cost = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(record.cost);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.title,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(cost, style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                tooltip: 'Edit catatan servis',
                onPressed: () =>
                    context.push('/records/${record.id}/edit', extra: record),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Hapus catatan servis',
                onPressed: () => _confirmDelete(context, ref),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '$date  •  ${NumberFormat.decimalPattern('id_ID').format(record.odometerKm)} km',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          if (record.workshop != null) ...[
            const SizedBox(height: 5),
            Text(
              record.workshop!,
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
          if (record.notes != null) ...[
            const SizedBox(height: 8),
            Text(record.notes!, style: const TextStyle(height: 1.4)),
          ],
          if (record.receiptPaths.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: record.receiptPaths.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) =>
                    _ReceiptThumbnail(path: record.receiptPaths[index]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus catatan servis?'),
        content: const Text(
          'Catatan dan foto notanya akan dihapus. Jadwal terkait akan kembali ke titik sebelumnya.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(serviceRecordListControllerProvider.notifier)
        .deleteRecord(record.id);
    if (!context.mounted) return;
    result.match(
      (failure) =>
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(failure.message))),
      (_) => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catatan servis berhasil dihapus.')),
      ),
    );
  }
}

class _ReceiptThumbnail extends ConsumerWidget {
  const _ReceiptThumbnail({required this.path});

  final String path;
  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder<String>(
    future: ref
        .read(serviceRecordRepositoryProvider)
        .createReceiptSignedUrl(path),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Container(
          width: 76,
          height: 76,
          color: AppColors.paleBlue,
          child: const Icon(Icons.broken_image_outlined),
        );
      }
      if (!snapshot.hasData) {
        return const SizedBox(
          width: 76,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      return GestureDetector(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            child: InteractiveViewer(
              child: Image.network(snapshot.data!, fit: BoxFit.contain),
            ),
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            snapshot.data!,
            width: 76,
            height: 76,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              width: 76,
              height: 76,
              color: AppColors.paleBlue,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      );
    },
  );
}

class _EmptyRecords extends StatelessWidget {
  const _EmptyRecords();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.receipt_long_rounded,
            size: 52,
            color: AppColors.blue,
          ),
          const SizedBox(height: 16),
          const Text(
            'Belum ada riwayat servis',
            style: TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Catat servis untuk menyimpan tanggal, odometer, bengkel, dan biaya.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
        ],
      ),
    ),
  );
}

class AddServiceRecordPage extends ConsumerStatefulWidget {
  const AddServiceRecordPage({this.schedule, this.record, super.key});

  final MaintenanceSchedule? schedule;
  final ServiceRecord? record;

  @override
  ConsumerState<AddServiceRecordPage> createState() =>
      _AddServiceRecordPageState();
}

class _AddServiceRecordPageState extends ConsumerState<AddServiceRecordPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _odometer = TextEditingController();
  final _workshop = TextEditingController();
  final _cost = TextEditingController();
  final _notes = TextEditingController();
  final _picker = ImagePicker();
  final List<XFile> _receiptImages = [];
  late final List<String> _existingReceiptPaths;
  late MaintenanceType _type;
  late DateTime _serviceDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final schedule = widget.schedule;
    final record = widget.record;
    _existingReceiptPaths = [...?record?.receiptPaths];
    _type = MaintenanceType.defaults.firstWhere(
      (type) => type.code == (record?.typeCode ?? schedule?.typeCode),
      orElse: () => MaintenanceType.defaults.first,
    );
    _title.text = record?.title ?? schedule?.title ?? _type.name;
    _serviceDate = record?.serviceDate ?? DateTime.now();
    _workshop.text = record?.workshop ?? '';
    _cost.text = record?.cost.toString() ?? '';
    _notes.text = record?.notes ?? '';
    if (record != null) _odometer.text = record.odometerKm.toString();
    final activeId = ref.read(activeMotorcycleIdProvider);
    final motorcycles = ref.read(motorcycleListControllerProvider).valueOrNull;
    for (final motorcycle in motorcycles ?? const []) {
      if (motorcycle.id == activeId) {
        _odometer.text = motorcycle.odometerKm.toString();
        break;
      }
    }
    if (record == null && schedule != null) {
      _odometer.text = schedule.odometerKm.toString();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _odometer.dispose();
    _workshop.dispose();
    _cost.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _serviceDate,
      firstDate: DateTime(1980),
      lastDate: DateTime.now(),
    );
    if (value != null) setState(() => _serviceDate = value);
  }

  Future<void> _pickReceipts(ImageSource source) async {
    final remaining = 5 - _existingReceiptPaths.length - _receiptImages.length;
    if (remaining <= 0) return;
    try {
      final picked = source == ImageSource.camera
          ? await _picker.pickImage(
              source: source,
              maxWidth: 1280,
              maxHeight: 1280,
              imageQuality: 80,
              requestFullMetadata: false,
            )
          : null;
      final fromGallery = source == ImageSource.gallery
          ? await _picker.pickMultiImage(
              maxWidth: 1280,
              maxHeight: 1280,
              imageQuality: 80,
              limit: remaining,
              requestFullMetadata: false,
            )
          : <XFile>[];
      final selected = [...fromGallery, ?picked];
      if (selected.isNotEmpty && mounted) {
        setState(() => _receiptImages.addAll(selected.take(remaining)));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Foto tidak dapat dibuka. Periksa izin kamera atau galeri.',
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final compressedImages = <Uint8List>[];
    try {
      for (final image in _receiptImages) {
        final bytes = await FlutterImageCompress.compressWithList(
          await image.readAsBytes(),
          minWidth: 1280,
          minHeight: 1280,
          quality: 80,
          format: CompressFormat.jpeg,
        );
        if (bytes.lengthInBytes > 1048576) {
          throw const FormatException('Foto masih lebih dari 1 MB.');
        }
        compressedImages.add(bytes);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Foto gagal dikompres hingga batas 1 MB. Pilih foto yang lebih kecil.';
        });
      }
      return;
    }
    final notifier = ref.read(serviceRecordListControllerProvider.notifier);
    final record = widget.record;
    final typeCode = _type.code;
    final title = _title.text.trim();
    final serviceDate = _serviceDate;
    final odometerKm = int.parse(_odometer.text);
    final cost = int.tryParse(_cost.text.trim().replaceAll('.', '')) ?? 0;
    final workshop = _workshop.text.trim().isEmpty
        ? null
        : _workshop.text.trim();
    final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
    final result = record == null
        ? await notifier.createRecord(
            scheduleId: widget.schedule?.id,
            typeCode: typeCode,
            title: title,
            serviceDate: serviceDate,
            odometerKm: odometerKm,
            cost: cost,
            workshop: workshop,
            notes: notes,
            receiptImages: compressedImages,
          )
        : await notifier.updateRecord(
            record: record,
            typeCode: typeCode,
            title: title,
            serviceDate: serviceDate,
            odometerKm: odometerKm,
            cost: cost,
            workshop: workshop,
            notes: notes,
            existingReceiptPaths: _existingReceiptPaths,
            receiptImages: compressedImages,
          );
    if (!mounted) return;
    result.match(
      (failure) => setState(() {
        _saving = false;
        _error = failure.message;
      }),
      (_) => Navigator.of(context).pop(),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.record == null ? 'Catat servis' : 'Edit catatan servis',
      ),
    ),
    body: Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _label('Jenis perawatan'),
          DropdownButtonFormField<MaintenanceType>(
            initialValue: _type,
            items: MaintenanceType.defaults
                .map(
                  (type) =>
                      DropdownMenuItem(value: type, child: Text(type.name)),
                )
                .toList(),
            onChanged: widget.schedule == null
                ? (value) {
                    if (value == null) return;
                    final titleWasDefault = _title.text == _type.name;
                    setState(() {
                      _type = value;
                      if (titleWasDefault) _title.text = value.name;
                    });
                  }
                : null,
          ),
          const SizedBox(height: 16),
          _label('Nama servis'),
          TextFormField(
            controller: _title,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Nama servis wajib diisi.'
                : null,
          ),
          const SizedBox(height: 16),
          _label('Tanggal servis'),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_rounded),
            label: Text(
              DateFormat('d MMMM yyyy', 'id_ID').format(_serviceDate),
            ),
          ),
          const SizedBox(height: 16),
          _label('Odometer saat servis'),
          TextFormField(
            controller: _odometer,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(suffixText: 'km'),
            validator: (value) => int.tryParse(value ?? '') == null
                ? 'Masukkan odometer yang valid.'
                : null,
          ),
          const SizedBox(height: 16),
          _label('Bengkel (opsional)'),
          TextFormField(controller: _workshop),
          const SizedBox(height: 16),
          _label('Biaya servis (Rp)'),
          TextFormField(
            controller: _cost,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: '0 jika tidak ada biaya',
            ),
            validator: (value) {
              final raw = value?.trim() ?? '';
              final amount = raw.isEmpty
                  ? 0
                  : int.tryParse(raw.replaceAll('.', ''));
              if (amount == null || amount < 0) return 'Biaya tidak valid.';
              return null;
            },
          ),
          const SizedBox(height: 16),
          _label('Catatan (opsional)'),
          TextFormField(controller: _notes, maxLines: 3),
          const SizedBox(height: 16),
          _label('Foto nota (maksimal 5)'),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed:
                    _receiptImages.length + _existingReceiptPaths.length >= 5
                    ? null
                    : () => _pickReceipts(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Galeri'),
              ),
              OutlinedButton.icon(
                onPressed:
                    _receiptImages.length + _existingReceiptPaths.length >= 5
                    ? null
                    : () => _pickReceipts(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Kamera'),
              ),
            ],
          ),
          if (_existingReceiptPaths.isNotEmpty ||
              _receiptImages.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _existingReceiptPaths.length + _receiptImages.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  if (index < _existingReceiptPaths.length) {
                    return _ReceiptThumbnail(
                      path: _existingReceiptPaths[index],
                    );
                  }
                  final newIndex = index - _existingReceiptPaths.length;
                  return FutureBuilder<Uint8List>(
                    future: _receiptImages[newIndex].readAsBytes(),
                    builder: (context, snapshot) => Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: snapshot.hasData
                              ? Image.memory(
                                  snapshot.data!,
                                  width: 82,
                                  height: 82,
                                  fit: BoxFit.cover,
                                )
                              : const SizedBox(
                                  width: 82,
                                  height: 82,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                        ),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: IconButton.filledTonal(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(
                              () => _receiptImages.removeAt(newIndex),
                            ),
                            icon: const Icon(Icons.close_rounded, size: 17),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: const TextStyle(color: Color(0xFF8C3232))),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Simpan catatan'),
          ),
        ],
      ),
    ),
  );

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
