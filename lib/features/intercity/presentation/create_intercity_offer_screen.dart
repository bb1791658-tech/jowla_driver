import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/maps/jowla_vector_map.dart';
import '../../../core/services/place_name_service.dart';
import '../../../core/services/road_route_service.dart';
import '../../home/application/driver_home_controller.dart';
import '../../rides/presentation/ride_formatters.dart';
import '../application/intercity_driver_controller.dart';
import '../domain/models/intercity_offer_draft.dart';
import '../domain/models/iraqi_governorate.dart';

enum _EditingPoint { pickup, dropoff }

class CreateIntercityOfferScreen extends ConsumerStatefulWidget {
  const CreateIntercityOfferScreen({super.key, this.offerId});

  final String? offerId;

  @override
  ConsumerState<CreateIntercityOfferScreen> createState() =>
      _CreateIntercityOfferScreenState();
}

class _CreateIntercityOfferScreenState
    extends ConsumerState<CreateIntercityOfferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _seatController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _mapController = JowlaMapController();
  var _editing = _EditingPoint.pickup;
  LatLng? _pickup;
  LatLng? _dropoff;
  String? _pickupAddress;
  String? _dropoffAddress;
  IraqiGovernorate? _origin;
  IraqiGovernorate? _destination;
  DateTime _departureAt = DateTime.now().add(const Duration(hours: 2));
  bool _resolvingPlace = false;
  bool _editingLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.offerId != null) {
        unawaited(_loadExisting(widget.offerId!));
        return;
      }
      final position = ref.read(driverHomeControllerProvider).lastPosition;
      if (position != null && mounted) {
        setState(() => _pickup = LatLng(position.latitude, position.longitude));
        unawaited(_resolvePoint(_EditingPoint.pickup, _pickup!));
      }
    });
  }

  @override
  void dispose() {
    _seatController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(intercityDriverControllerProvider);
    final center = _pickup ?? const LatLng(33.3152, 44.3661);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.offerId == null
              ? 'إنشاء رحلة بين المحافظات'
              : 'تعديل عرض الرحلة',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            Text(
              'حدّد نقطتين ثابتتين على الخريطة أو ابحث عنهما، ثم انشر الرحلة مباشرة.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            SegmentedButton<_EditingPoint>(
              segments: const [
                ButtonSegment(
                  value: _EditingPoint.pickup,
                  icon: Icon(Icons.trip_origin_rounded),
                  label: Text('نقطة التجمع'),
                ),
                ButtonSegment(
                  value: _EditingPoint.dropoff,
                  icon: Icon(Icons.location_on_rounded),
                  label: Text('نقطة الوصول'),
                ),
              ],
              selected: {_editing},
              onSelectionChanged: (value) =>
                  setState(() => _editing = value.first),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _resolvingPlace ? null : _searchPlace,
              icon: const Icon(Icons.search_rounded),
              label: Text(
                _editing == _EditingPoint.pickup
                    ? 'ابحث عن نقطة التجمع'
                    : 'ابحث عن نقطة الوصول',
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 280,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: JowlaVectorMap(
                  controller: _mapController,
                  initialCenter: center,
                  initialZoom: _pickup == null ? 6 : 13,
                  onTap: (point) => unawaited(_selectPoint(_editing, point)),
                  polylines: [
                    if (_pickup != null && _dropoff != null)
                      JowlaMapPolyline(
                        points: [_pickup!, _dropoff!],
                        width: 4,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                  ],
                  markers: [
                    if (_pickup != null)
                      JowlaMapMarker(
                        point: _pickup!,
                        size: const Size(42, 42),
                        child: const Icon(
                          Icons.trip_origin_rounded,
                          color: Color(0xFF017833),
                          size: 34,
                        ),
                      ),
                    if (_dropoff != null)
                      JowlaMapMarker(
                        point: _dropoff!,
                        size: const Size(46, 46),
                        child: const Icon(
                          Icons.location_on_rounded,
                          color: Color(0xFFD32F2F),
                          size: 38,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_resolvingPlace)
              const LinearProgressIndicator()
            else ...[
              const SizedBox(height: 8),
              _PointLabel(
                label: 'التجمع',
                value: _pickupAddress ?? 'لم تحدد النقطة',
              ),
              _PointLabel(
                label: 'الوصول',
                value: _dropoffAddress ?? 'لم تحدد النقطة',
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<IraqiGovernorate>(
              key: ValueKey('origin-${_origin?.code}'),
              initialValue: _origin,
              decoration: const InputDecoration(labelText: 'محافظة الانطلاق'),
              items: _governorateItems(),
              onChanged: (value) => setState(() => _origin = value),
              validator: (value) =>
                  value == null ? 'اختر محافظة الانطلاق' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<IraqiGovernorate>(
              key: ValueKey('destination-${_destination?.code}'),
              initialValue: _destination,
              decoration: const InputDecoration(labelText: 'محافظة الوصول'),
              items: _governorateItems(),
              onChanged: (value) => setState(() => _destination = value),
              validator: (value) {
                if (value == null) return 'اختر محافظة الوصول';
                if (value == _origin) return 'يجب اختيار محافظة مختلفة';
                return null;
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: const Text('موعد المغادرة'),
              subtitle: Text(
                DateFormat(
                  'EEEE d MMMM yyyy، h:mm a',
                  'ar_IQ',
                ).format(_departureAt),
              ),
              trailing: const Icon(Icons.edit_calendar_rounded),
              onTap: _pickDeparture,
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _seatController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'المقاعد المتاحة',
                      helperText: state.vehicleCapacity == null
                          ? 'لا توجد قيود سعة من الخادم'
                          : 'السعة المسجلة ${state.vehicleCapacity} (لا تمنع النشر)',
                    ),
                    validator: _validateSeats,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _priceController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'سعر المقعد',
                      suffixText: 'د.ع',
                      helperText: state.preview == null
                          ? 'اكتب السعر الذي تريده'
                          : '${formatIqd(state.preview!.minimumPriceDinars.toDouble())} – ${formatIqd(state.preview!.maximumPriceDinars.toDouble())}',
                    ),
                    validator: (value) => int.tryParse(value ?? '') == null
                        ? 'أدخل سعرًا صحيحًا'
                        : null,
                  ),
                ),
              ],
            ),
            if (state.error != null) ...[
              const SizedBox(height: 12),
              Material(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(state.error!),
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: state.isSubmitting ? null : _previewAndConfirm,
              icon: state.isSubmitting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: Text(
                widget.offerId == null ? 'نشر الرحلة الآن' : 'مراجعة التعديلات',
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<DropdownMenuItem<IraqiGovernorate>> _governorateItems() => [
    for (final item in IraqiGovernorate.values)
      DropdownMenuItem(value: item, child: Text(item.arabicName)),
  ];

  String? _validateSeats(String? value) {
    final seats = int.tryParse(value ?? '');
    if (seats == null || seats < 1) return 'عدد غير صالح';
    return null;
  }

  Future<void> _selectPoint(_EditingPoint point, LatLng value) async {
    var selected = value;
    try {
      final nearest = await ref
          .read(roadRouteServiceProvider)
          .nearest(value, maxDistanceMeters: 100);
      if (nearest != null && nearest.distanceMeters >= 8 && mounted) {
        final useRoad = await showModalBottomSheet<bool>(
          context: context,
          showDragHandle: true,
          builder: (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'وجدنا نقطة وصول أسهل',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'النقطة المقترحة على أقرب طريق صالح وتبعد '
                    '${nearest.distanceMeters.round()} مترًا عن اختيارك.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.alt_route_rounded),
                    label: const Text('استخدام النقطة المقترحة'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('الاحتفاظ باختياري'),
                  ),
                ],
              ),
            ),
          ),
        );
        if (useRoad == true) selected = nearest.point;
      }
    } catch (_) {
      // يبقى اختيار المستخدم صالحًا إذا كان OSRM غير متاح مؤقتًا.
    }
    if (!mounted) return;
    setState(() {
      if (point == _EditingPoint.pickup) {
        _pickup = selected;
        _pickupAddress = 'جار تحديد العنوان…';
      } else {
        _dropoff = selected;
        _dropoffAddress = 'جار تحديد العنوان…';
      }
    });
    unawaited(_resolvePoint(point, selected));
  }

  Future<void> _resolvePoint(_EditingPoint point, LatLng value) async {
    setState(() => _resolvingPlace = true);
    final name = await PlaceNameService.instance.nameFor(value);
    if (!mounted) return;
    final inferred = IraqiGovernorate.fromCodeOrName(name);
    setState(() {
      _resolvingPlace = false;
      if (point == _EditingPoint.pickup && _pickup == value) {
        _pickupAddress = name ?? 'نقطة تجمع محددة على الخريطة';
        _origin ??= inferred;
      } else if (point == _EditingPoint.dropoff && _dropoff == value) {
        _dropoffAddress = name ?? 'نقطة وصول محددة على الخريطة';
        _destination ??= inferred;
      }
    });
  }

  Future<void> _loadExisting(String offerId) async {
    await ref
        .read(intercityDriverControllerProvider.notifier)
        .loadOffer(offerId);
    if (!mounted || _editingLoaded) return;
    final offer = ref.read(intercityDriverControllerProvider).selectedOffer;
    if (offer == null || offer.id != offerId) return;
    _editingLoaded = true;
    setState(() {
      _pickup = offer.pickup;
      _dropoff = offer.dropoff;
      _pickupAddress = offer.pickupAddress;
      _dropoffAddress = offer.dropoffAddress;
      _origin = offer.originGovernorate;
      _destination = offer.destinationGovernorate;
      _departureAt = offer.departureAt;
      _seatController.text = '${offer.totalSeats}';
      _priceController.text = '${offer.pricePerSeatDinars}';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapController.move(offer.pickup, 8);
    });
  }

  Future<void> _searchPlace() async {
    final position = ref.read(driverHomeControllerProvider).lastPosition;
    final fallback = position == null
        ? null
        : LatLng(position.latitude, position.longitude);
    final near = _editing == _EditingPoint.pickup
        ? _pickup ?? fallback
        : _dropoff ?? fallback;
    final result = await showSearch<PlaceSearchResult?>(
      context: context,
      delegate: _PlaceSearchDelegate(near: near),
    );
    if (result == null || !mounted) return;
    setState(() {
      final inferred = IraqiGovernorate.fromCodeOrName(
        result.governorate ?? result.displayName,
      );
      if (_editing == _EditingPoint.pickup) {
        _pickup = result.point;
        _pickupAddress = result.displayName;
        _origin = inferred ?? _origin;
      } else {
        _dropoff = result.point;
        _dropoffAddress = result.displayName;
        _destination = inferred ?? _destination;
      }
    });
    _mapController.move(result.point, 13);
  }

  Future<void> _pickDeparture() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _departureAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_departureAt),
    );
    if (time == null) return;
    setState(() {
      _departureAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  IntercityOfferDraft? _draft() {
    if (!_formKey.currentState!.validate()) return null;
    if (_pickup == null || _dropoff == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حدد نقطتي التجمع والوصول.')),
      );
      return null;
    }
    return IntercityOfferDraft(
      originGovernorate: _origin!,
      destinationGovernorate: _destination!,
      pickup: _pickup!,
      dropoff: _dropoff!,
      pickupAddress: _pickupAddress ?? 'نقطة التجمع',
      dropoffAddress: _dropoffAddress ?? 'نقطة الوصول',
      departureAt: _departureAt,
      totalSeats: int.parse(_seatController.text),
      pricePerSeatDinars: int.parse(_priceController.text),
    );
  }

  Future<void> _previewAndConfirm() async {
    final draft = _draft();
    if (draft == null) return;
    final controller = ref.read(intercityDriverControllerProvider.notifier);
    if (widget.offerId == null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('نشر الرحلة'),
          content: Text(
            '${draft.originGovernorate.arabicName} ← ${draft.destinationGovernorate.arabicName}\n'
            '${draft.totalSeats} مقعد • ${formatIqd(draft.pricePerSeatDinars.toDouble())} للمقعد\n'
            'المغادرة: ${DateFormat('d/M/yyyy، h:mm a', 'ar_IQ').format(draft.departureAt)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('تعديل'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('نشر الرحلة'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final result = await controller.create(draft);
      if (result != null && mounted) {
        context.go('/intercity/offers/${result.id}');
      }
      return;
    }
    final preview = await controller.preview(draft);
    if (preview == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ملخص العرض'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${draft.originGovernorate.arabicName} ← ${draft.destinationGovernorate.arabicName}',
              ),
              Text('${draft.pickupAddress} ← ${draft.dropoffAddress}'),
              Text(
                'المغادرة: ${DateFormat('d/M/yyyy، h:mm a', 'ar_IQ').format(draft.departureAt)}',
              ),
              Text(
                'المسافة: ${(preview.distanceMeters / 1000).toStringAsFixed(1)} كم',
              ),
              Text('المدة: ${(preview.durationSeconds / 60).round()} دقيقة'),
              Text('المقاعد: ${draft.totalSeats}'),
              Text(
                'سعر المقعد: ${formatIqd(draft.pricePerSeatDinars.toDouble())}',
              ),
              Text(
                'المتوقع عند الامتلاء: ${preview.expectedGrossDinars == null ? 'يحدده الخادم عند النشر' : formatIqd(preview.expectedGrossDinars!.toDouble())}',
              ),
              const SizedBox(height: 8),
              Text('سياسة الإلغاء: ${preview.cancellationPolicy}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('تعديل'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              widget.offerId == null ? 'إرسال للنشر' : 'حفظ التعديلات',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final current = ref.read(intercityDriverControllerProvider).selectedOffer;
    final result = widget.offerId == null
        ? await controller.create(draft)
        : current == null
        ? null
        : await controller.update(draft, current);
    if (result != null && mounted) {
      context.go('/intercity/offers/${result.id}');
    }
  }
}

class _PointLabel extends StatelessWidget {
  const _PointLabel({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 64, child: Text(label)),
        Expanded(
          child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}

class _PlaceSearchDelegate extends SearchDelegate<PlaceSearchResult?> {
  _PlaceSearchDelegate({this.near})
    : super(searchFieldLabel: 'ابحث عن مكان داخل العراق');

  final LatLng? near;

  @override
  List<Widget>? buildActions(BuildContext context) => [
    IconButton(
      onPressed: () => query = '',
      icon: const Icon(Icons.clear_rounded),
    ),
  ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
    onPressed: () => close(context, null),
    icon: const Icon(Icons.arrow_forward_rounded),
  );

  @override
  Widget buildResults(BuildContext context) => _results();

  @override
  Widget buildSuggestions(BuildContext context) => _results();

  Widget _results() {
    if (query.trim().length < 2) {
      return const Center(child: Text('اكتب حرفين على الأقل.'));
    }
    return FutureBuilder<List<PlaceSearchResult>>(
      future: PlaceNameService.instance.search(query, near: near),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final values = snapshot.data ?? const [];
        if (values.isEmpty) return const Center(child: Text('لم نجد نتائج.'));
        return ListView.builder(
          itemCount: values.length,
          itemBuilder: (context, index) {
            final item = values[index];
            return ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(item.displayName),
              subtitle: item.governorate == null
                  ? null
                  : Text(item.governorate!),
              onTap: () => close(context, item),
            );
          },
        );
      },
    );
  }
}
