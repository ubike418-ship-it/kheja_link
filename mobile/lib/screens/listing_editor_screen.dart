import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../config/theme.dart';
import '../main.dart';
import '../models/models.dart';
import '../services/kheja_api.dart';
import '../widgets/property_card.dart';
import '../widgets/states.dart';

/// Where a landlord lists a property — or edits one.
///
/// Deliberately thorough. A tenant who can see the water arrangement, the
/// service charge, the parking and the house rules before they travel is a
/// tenant who turns up ready to sign, not one who wastes the landlord's
/// afternoon. The form is split into sections so it does not feel endless.
class ListingEditorScreen extends StatefulWidget {
  const ListingEditorScreen({super.key, this.propertyId});

  /// Null to create a new listing.
  final String? propertyId;

  @override
  State<ListingEditorScreen> createState() => _ListingEditorScreenState();
}

class _ListingEditorScreenState extends State<ListingEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  ListingDraft _draft = ListingDraft();
  List<PropertyType> _types = const [];
  List<KhejaLocation> _locations = const [];
  List<Amenity> _amenities = const [];

  bool _loading = true;
  bool _saving = false;
  bool _locating = false;
  String? _loadError;

  /// Uploads in flight, so the save button waits for them.
  int _uploading = 0;

  bool get _isEditing => widget.propertyId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final results = await Future.wait([
        khejaApi.fetchPropertyTypes(),
        khejaApi.fetchLocations(),
        khejaApi.fetchAmenities(),
        if (_isEditing) khejaApi.fetchListingForEdit(widget.propertyId!),
        khejaApi.fetchProfile(),
      ]);

      if (!mounted) return;

      final profile = results.last as Profile?;
      ListingDraft draft;

      if (_isEditing) {
        final loaded = results[3] as ListingDraft?;
        if (loaded == null) {
          setState(() {
            _loading = false;
            _loadError = 'That listing could not be found.';
          });
          return;
        }
        draft = loaded;
      } else {
        // Sensible defaults from the landlord's own account.
        draft = ListingDraft()
          ..landlordName = profile?.fullName ?? ''
          ..contactPhone = profile?.phone ?? ''
          ..contactWhatsapp = profile?.phone ?? '';
      }

      setState(() {
        _types = results[0] as List<PropertyType>;
        _locations = results[1] as List<KhejaLocation>;
        _amenities = results[2] as List<Amenity>;
        _draft = draft;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = describeError(error);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Media
  // ---------------------------------------------------------------------------

  Future<void> _addPhotos(ImageSource source) async {
    try {
      final picked = source == ImageSource.camera
          ? [await _picker.pickImage(source: source, imageQuality: 82, maxWidth: 2000)]
          : await _picker.pickMultiImage(imageQuality: 82, maxWidth: 2000);

      final files = picked.whereType<XFile>().toList();
      if (files.isEmpty) return;

      final room = 15 - _draft.photoUrls.length;
      if (room <= 0) {
        if (mounted) showKhejaSnack(context, 'Up to 15 photos per listing.');
        return;
      }

      setState(() => _uploading += files.take(room).length);

      for (final file in files.take(room)) {
        try {
          final url = await khejaApi.uploadPropertyPhoto(File(file.path));
          if (!mounted) return;
          setState(() => _draft.photoUrls = [..._draft.photoUrls, url]);
        } catch (error) {
          if (mounted) showKhejaSnack(context, describeError(error), isError: true);
        } finally {
          if (mounted) setState(() => _uploading--);
        }
      }
    } catch (error) {
      if (mounted) {
        showKhejaSnack(context, 'Could not open photos. Check the app permission.',
            isError: true);
      }
    }
  }

  Future<void> _addVideo(ImageSource source) async {
    try {
      final file = await _picker.pickVideo(
        source: source,
        maxDuration: const Duration(minutes: 3),
      );
      if (file == null) return;

      if (_draft.videoUrls.length >= 3) {
        if (mounted) showKhejaSnack(context, 'Up to 3 videos per listing.');
        return;
      }

      setState(() => _uploading++);
      if (mounted) {
        showKhejaSnack(context, 'Uploading video — this can take a minute on mobile data.');
      }

      try {
        final url = await khejaApi.uploadPropertyVideo(File(file.path));
        if (!mounted) return;
        setState(() => _draft.videoUrls = [..._draft.videoUrls, url]);
        showKhejaSnack(context, 'Video added.');
      } catch (error) {
        if (mounted) showKhejaSnack(context, describeError(error), isError: true);
      } finally {
        if (mounted) setState(() => _uploading--);
      }
    } catch (_) {
      if (mounted) {
        showKhejaSnack(context, 'Could not open videos. Check the app permission.',
            isError: true);
      }
    }
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          showKhejaSnack(context, 'Turn on location on your phone first.', isError: true);
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          showKhejaSnack(
            context,
            'Location is off for Kheja_Link. Allow it in Settings to pin the house.',
            isError: true,
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 20));

      if (!mounted) return;
      setState(() {
        _draft.latitude = position.latitude;
        _draft.longitude = position.longitude;
      });
      showKhejaSnack(context, 'Pinned. Only paying tenants can see the exact spot.');
    } catch (_) {
      if (mounted) {
        showKhejaSnack(context, 'Could not get your location. Try again outside.',
            isError: true);
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> _save({required bool publish}) async {
    if (_uploading > 0) {
      showKhejaSnack(context, 'Wait for the uploads to finish first.');
      return;
    }

    _draft.status = publish ? 'published' : 'draft';

    // Drafts can have gaps; a published listing cannot.
    if (publish) {
      if (!(_formKey.currentState?.validate() ?? false)) {
        showKhejaSnack(context, 'Some fields need attention.', isError: true);
        return;
      }
      final missing = _draft.missingForPublish();
      if (missing.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KhejaRadius.lg),
            ),
            title: const Text('Almost ready'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add these before publishing:'),
                const SizedBox(height: 12),
                for (final item in missing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, size: 6, color: KhejaColors.amber),
                        const SizedBox(width: 10),
                        Expanded(child: Text(item)),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
    } else {
      _formKey.currentState?.save();
      if (_draft.title.trim().length < 6 ||
          _draft.propertyTypeId == null ||
          _draft.locationId == null ||
          (_draft.priceAmount ?? 0) <= 0) {
        showKhejaSnack(
          context,
          'Even a draft needs a title, type, area and rent.',
          isError: true,
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await khejaApi.updateProperty(widget.propertyId!, _draft);
      } else {
        await khejaApi.createProperty(_draft);
      }
      if (!mounted) return;
      showKhejaSnack(
        context,
        publish
            ? 'Published. Tenants can see it now.'
            : 'Saved as a draft. Only you can see it.',
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showKhejaSnack(context, describeError(error), isError: true);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(_isEditing ? 'Edit listing' : 'List a property')),
        body: const Center(child: CircularProgressIndicator(color: KhejaColors.emerald)),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_isEditing ? 'Edit listing' : 'List a property')),
        body: KhejaErrorState(message: _loadError!, onRetry: _load),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit listing' : 'List a property'),
        actions: [
          if (_uploading > 0)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: KhejaColors.emerald),
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
          children: [
            _intro(),

            // ---- Photos and video -------------------------------------------
            _Section(
              icon: Icons.photo_library_rounded,
              title: 'Photos and video',
              subtitle: 'The first photo is the cover. Clear, bright photos of every '
                  'room get far more views.',
              child: _mediaSection(),
            ),

            // ---- Basics -----------------------------------------------------
            _Section(
              icon: Icons.home_work_rounded,
              title: 'The basics',
              child: Column(
                children: [
                  _text(
                    label: 'Listing title',
                    hint: 'e.g. Spacious 2 bedroom in Makutano',
                    initial: _draft.title,
                    onSaved: (v) => _draft.title = v,
                    validator: (v) => v.trim().length < 6
                        ? 'Give it a clear title of at least 6 characters'
                        : null,
                  ),
                  _dropdown<String>(
                    label: 'Property type',
                    value: _draft.propertyTypeId,
                    items: {for (final t in _types) t.id: t.name},
                    onChanged: (v) => setState(() => _draft.propertyTypeId = v),
                  ),
                  _dropdown<String>(
                    label: 'Area',
                    value: _draft.locationId,
                    items: {for (final l in _locations) l.id: l.name},
                    onChanged: (v) => setState(() => _draft.locationId = v),
                  ),
                  _text(
                    label: 'Street or estate',
                    hint: 'e.g. Off Meru-Maua Road, near the stage',
                    initial: _draft.addressLine,
                    onSaved: (v) => _draft.addressLine = v,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _text(
                          label: 'Building name',
                          hint: 'e.g. Summit Heights',
                          initial: _draft.buildingName,
                          onSaved: (v) => _draft.buildingName = v,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 104,
                        child: _number(
                          label: 'Floor',
                          initial: _draft.floorNumber,
                          onSaved: (v) => _draft.floorNumber = v?.toInt(),
                        ),
                      ),
                    ],
                  ),
                  _text(
                    label: 'Description',
                    hint: 'What is it like to live here? Mention the light, the '
                        'neighbours, the view, recent renovations.',
                    initial: _draft.description,
                    maxLines: 6,
                    onSaved: (v) => _draft.description = v,
                    validator: (v) => v.trim().isNotEmpty && v.trim().length < 30
                        ? 'Write at least 30 characters so tenants know what to expect'
                        : null,
                  ),
                  _text(
                    label: 'What is nearby',
                    hint: 'Matatu stage, schools, market, hospital, church…',
                    initial: _draft.nearby,
                    maxLines: 3,
                    onSaved: (v) => _draft.nearby = v,
                  ),
                ],
              ),
            ),

            // ---- Rent and terms ----------------------------------------------
            _Section(
              icon: Icons.payments_rounded,
              title: 'Rent and terms',
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _number(
                          label: 'Rent (KSh)',
                          initial: _draft.priceAmount,
                          required: true,
                          onSaved: (v) => _draft.priceAmount = v,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: _dropdown<String>(
                          label: 'Per',
                          value: _draft.pricePeriod,
                          items: const {'month': 'Month', 'year': 'Year'},
                          onChanged: (v) =>
                              setState(() => _draft.pricePeriod = v ?? 'month'),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _number(
                          label: 'Deposit (months)',
                          initial: _draft.depositMonths,
                          onSaved: (v) => _draft.depositMonths = v?.toInt() ?? 1,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _number(
                          label: 'Service charge (KSh)',
                          initial: _draft.serviceCharge,
                          onSaved: (v) => _draft.serviceCharge = v,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: _number(
                          label: 'Minimum lease (months)',
                          initial: _draft.minLeaseMonths,
                          onSaved: (v) => _draft.minLeaseMonths = v?.toInt(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _number(
                          label: 'Notice (months)',
                          initial: _draft.noticeMonths,
                          onSaved: (v) => _draft.noticeMonths = v?.toInt(),
                        ),
                      ),
                    ],
                  ),
                  _datePicker(),
                ],
              ),
            ),

            // ---- The home ---------------------------------------------------
            _Section(
              icon: Icons.bed_rounded,
              title: 'The home',
              child: Column(
                children: [
                  _stepperRow('Bedrooms', _draft.bedrooms,
                      (v) => setState(() => _draft.bedrooms = v)),
                  _stepperRow('Bathrooms', _draft.bathrooms,
                      (v) => setState(() => _draft.bathrooms = v)),
                  _stepperRow('Parking spaces', _draft.parkingSpaces,
                      (v) => setState(() => _draft.parkingSpaces = v)),
                  const SizedBox(height: 8),
                  _number(
                    label: 'Size (sqft)',
                    initial: _draft.sizeSqft,
                    onSaved: (v) => _draft.sizeSqft = v?.toInt(),
                  ),
                  _switch('Furnished', _draft.isFurnished,
                      (v) => setState(() => _draft.isFurnished = v)),
                  _switch('Balcony', _draft.hasBalcony,
                      (v) => setState(() => _draft.hasBalcony = v)),
                  _switch('Gated compound', _draft.isGated,
                      (v) => setState(() => _draft.isGated = v)),
                  _switch('Internet ready', _draft.internetReady,
                      (v) => setState(() => _draft.internetReady = v)),
                  _switch('Pets allowed', _draft.petsAllowed,
                      (v) => setState(() => _draft.petsAllowed = v)),
                  _switch('List as premium', _draft.isPremium,
                      (v) => setState(() => _draft.isPremium = v)),
                ],
              ),
            ),

            // ---- Utilities --------------------------------------------------
            _Section(
              icon: Icons.water_drop_rounded,
              title: 'Water and electricity',
              subtitle: 'The first thing tenants ask about in Meru. Be specific.',
              child: Column(
                children: [
                  _dropdown<String>(
                    label: 'Water',
                    value: _draft.waterBilling,
                    items: const {
                      'included': 'Included in rent',
                      'metered': 'Metered, billed separately',
                      'flat_rate': 'Flat monthly rate',
                      'borehole': 'Borehole supply',
                      'none': 'Tenant arranges own',
                    },
                    onChanged: (v) => setState(() => _draft.waterBilling = v),
                  ),
                  _text(
                    label: 'Water notes',
                    hint: 'e.g. County water Mon-Thu, 5,000L tank as backup',
                    initial: _draft.waterNotes,
                    onSaved: (v) => _draft.waterNotes = v,
                  ),
                  _dropdown<String>(
                    label: 'Electricity',
                    value: _draft.electricityBilling,
                    items: const {
                      'prepaid_token': 'Prepaid tokens',
                      'postpaid': 'Postpaid, billed monthly',
                      'included': 'Included in rent',
                      'shared_meter': 'Shared meter',
                    },
                    onChanged: (v) => setState(() => _draft.electricityBilling = v),
                  ),
                ],
              ),
            ),

            // ---- Amenities --------------------------------------------------
            if (_amenities.isNotEmpty)
              _Section(
                icon: Icons.checklist_rounded,
                title: 'Amenities',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final a in _amenities)
                      FilterChip(
                        label: Text(a.name),
                        selected: _draft.amenityIds.contains(a.id),
                        selectedColor: KhejaColors.emerald.withValues(alpha: 0.18),
                        checkmarkColor: KhejaColors.emerald,
                        onSelected: (on) => setState(() {
                          _draft.amenityIds = on
                              ? [..._draft.amenityIds, a.id]
                              : _draft.amenityIds.where((x) => x != a.id).toList();
                        }),
                      ),
                  ],
                ),
              ),

            // ---- Safety and rules -------------------------------------------
            _Section(
              icon: Icons.gavel_rounded,
              title: 'Security and house rules',
              child: Column(
                children: [
                  _text(
                    label: 'Security',
                    hint: 'e.g. 24-hour guard, CCTV, gate locks at 11pm',
                    initial: _draft.securityDetails,
                    maxLines: 3,
                    onSaved: (v) => _draft.securityDetails = v,
                  ),
                  _text(
                    label: 'House rules',
                    hint: 'One per line. e.g. No loud music after 10pm',
                    initial: _draft.houseRules,
                    maxLines: 5,
                    onSaved: (v) => _draft.houseRules = v,
                  ),
                ],
              ),
            ),

            // ---- Contact ----------------------------------------------------
            _Section(
              icon: Icons.contact_phone_rounded,
              title: 'Contact details',
              subtitle: 'Hidden from tenants until they pay the KSh 150 unlock, '
                  'which filters out time-wasters.',
              child: Column(
                children: [
                  _text(
                    label: 'Landlord name shown to tenants',
                    hint: 'e.g. Mr. Mwiti',
                    initial: _draft.landlordName,
                    onSaved: (v) => _draft.landlordName = v,
                  ),
                  _text(
                    label: 'Landlord phone',
                    hint: '+254 712 345 678',
                    initial: _draft.contactPhone,
                    keyboard: TextInputType.phone,
                    onSaved: (v) => _draft.contactPhone = v,
                    validator: _phoneValidator(required: true),
                  ),
                  _text(
                    label: 'WhatsApp number',
                    hint: 'Leave blank if the same as above',
                    initial: _draft.contactWhatsapp,
                    keyboard: TextInputType.phone,
                    onSaved: (v) => _draft.contactWhatsapp = v,
                    validator: _phoneValidator(required: false),
                  ),
                  _text(
                    label: 'Caretaker name',
                    hint: 'e.g. John, on site',
                    initial: _draft.caretakerName,
                    onSaved: (v) => _draft.caretakerName = v,
                  ),
                  _text(
                    label: 'Caretaker phone',
                    hint: '+254 7…',
                    initial: _draft.caretakerPhone,
                    keyboard: TextInputType.phone,
                    onSaved: (v) => _draft.caretakerPhone = v,
                    validator: _phoneValidator(required: false),
                  ),
                ],
              ),
            ),

            // ---- Location pin -----------------------------------------------
            _Section(
              icon: Icons.push_pin_rounded,
              title: 'Exact location',
              subtitle: 'Stand at the house and tap the button. Only tenants who '
                  'unlock the listing see this pin.',
              child: _locationSection(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _saveBar(),
    );
  }

  Widget _intro() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: KhejaColors.emerald.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(KhejaRadius.lg),
          border: Border.all(color: KhejaColors.emerald.withValues(alpha: 0.28)),
        ),
        child: const Row(
          children: [
            Icon(Icons.lightbulb_rounded, size: 20, color: KhejaColors.emerald),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'The more you fill in, the fewer wasted viewings. Save a draft any '
                'time and finish later.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_draft.photoUrls.isNotEmpty)
          SizedBox(
            height: 104,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: _draft.photoUrls.length,
              onReorder: (from, to) => setState(() {
                final list = [..._draft.photoUrls];
                if (to > from) to -= 1;
                list.insert(to, list.removeAt(from));
                _draft.photoUrls = list;
              }),
              itemBuilder: (context, i) {
                final url = _draft.photoUrls[i];
                return ReorderableDragStartListener(
                  key: ValueKey(url),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(KhejaRadius.md),
                          child: SizedBox(
                            width: 104,
                            height: 104,
                            child: PropertyImageView(url: url, width: 240),
                          ),
                        ),
                        if (i == 0)
                          Positioned(
                            left: 6,
                            top: 6,
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: KhejaColors.emerald,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('COVER',
                                  style: kEyebrowStyle.copyWith(
                                      color: Colors.white, fontSize: 8)),
                            ),
                          ),
                        Positioned(
                          right: 4,
                          top: 4,
                          child: _removeButton(() => setState(() {
                                _draft.photoUrls =
                                    _draft.photoUrls.where((u) => u != url).toList();
                              })),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        if (_draft.photoUrls.length > 1)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Press and drag a photo to reorder.',
              style: TextStyle(fontSize: 11, color: KhejaColors.zinc400),
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _addPhotos(ImageSource.gallery),
                icon: const Icon(Icons.add_photo_alternate_rounded, size: 19),
                label: const Text('Gallery'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _addPhotos(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_rounded, size: 19),
                label: const Text('Camera'),
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),
        Text('VIDEO TOURS', style: kEyebrowStyle.copyWith(color: KhejaColors.zinc400)),
        const SizedBox(height: 8),
        for (var i = 0; i < _draft.videoUrls.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(KhejaRadius.md),
                border: Border.all(color: Theme.of(context).colorScheme.outline),
              ),
              child: Row(
                children: [
                  const Icon(Icons.play_circle_fill_rounded,
                      size: 28, color: KhejaColors.emerald),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Video tour ${i + 1}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  _removeButton(() => setState(() {
                        final list = [..._draft.videoUrls]..removeAt(i);
                        _draft.videoUrls = list;
                      })),
                ],
              ),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _addVideo(ImageSource.gallery),
                icon: const Icon(Icons.video_library_rounded, size: 19),
                label: const Text('Choose video'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _addVideo(ImageSource.camera),
                icon: const Icon(Icons.videocam_rounded, size: 19),
                label: const Text('Record'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Up to 3 videos, 60 MB each. Walk slowly through every room.',
          style: TextStyle(fontSize: 11, color: KhejaColors.zinc400),
        ),
      ],
    );
  }

  Widget _locationSection() {
    final pinned = _draft.latitude != null && _draft.longitude != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (pinned)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: KhejaColors.emerald.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(KhejaRadius.md),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: KhejaColors.emerald),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_draft.latitude!.toStringAsFixed(5)}, '
                    '${_draft.longitude!.toStringAsFixed(5)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _locating ? null : _useCurrentLocation,
            style: FilledButton.styleFrom(backgroundColor: KhejaColors.emerald),
            icon: _locating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.my_location_rounded, size: 19),
            label: Text(pinned ? 'Update pin to where I am' : 'Pin where I am standing'),
          ),
        ),
      ],
    );
  }

  Widget _saveBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _saving ? null : () => _save(publish: false),
                child: const Text('Save draft'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _saving ? null : () => _save(publish: true),
                style: FilledButton.styleFrom(backgroundColor: KhejaColors.emerald),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_isEditing ? 'Save and publish' : 'Publish listing'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- field builders -------------------------------------------------------

  Widget _removeButton(VoidCallback onTap) => Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(5),
            child: Icon(Icons.close_rounded, size: 15, color: Colors.white),
          ),
        ),
      );

  String? Function(String) _phoneValidator({required bool required}) => (v) {
        final text = v.trim();
        if (text.isEmpty) return required ? 'Tenants need a number to call' : null;
        return text.replaceAll(RegExp(r'\D'), '').length >= 9
            ? null
            : 'Enter a valid phone number';
      };

  Widget _text({
    required String label,
    required String initial,
    required void Function(String) onSaved,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboard,
    String? Function(String)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        initialValue: initial,
        maxLines: maxLines,
        keyboardType: keyboard ?? (maxLines > 1 ? TextInputType.multiline : null),
        textCapitalization:
            keyboard == null ? TextCapitalization.sentences : TextCapitalization.none,
        decoration: InputDecoration(labelText: label, hintText: hint),
        onChanged: onSaved,
        onSaved: (v) => onSaved(v ?? ''),
        validator: validator == null ? null : (v) => validator(v ?? ''),
      ),
    );
  }

  Widget _number({
    required String label,
    required num? initial,
    required void Function(num?) onSaved,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        initialValue: initial == null ? '' : _plain(initial),
        keyboardType: const TextInputType.numberWithOptions(decimal: false),
        decoration: InputDecoration(labelText: label),
        onChanged: (v) => onSaved(num.tryParse(v.replaceAll(',', '').trim())),
        onSaved: (v) => onSaved(num.tryParse((v ?? '').replaceAll(',', '').trim())),
        validator: (v) {
          final text = (v ?? '').replaceAll(',', '').trim();
          if (text.isEmpty) return required ? 'Required' : null;
          final n = num.tryParse(text);
          if (n == null) return 'Numbers only';
          if (n < 0) return 'Cannot be negative';
          return null;
        },
      ),
    );
  }

  static String _plain(num n) => n == n.roundToDouble() ? n.toInt().toString() : '$n';

  Widget _dropdown<T>({
    required String label,
    required T? value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<T>(
        initialValue: items.containsKey(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final e in items.entries)
            DropdownMenuItem<T>(value: e.key, child: Text(e.value)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      value: value,
      onChanged: onChanged,
      activeThumbColor: KhejaColors.emerald,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }

  Widget _stepperRow(String label, int value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton.outlined(
            onPressed: value > 0 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
          IconButton.outlined(
            onPressed: value < 50 ? () => onChanged(value + 1) : null,
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _datePicker() {
    final date = _draft.availableFrom;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: OutlinedButton.icon(
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date ?? DateTime.now(),
            firstDate: DateTime.now().subtract(const Duration(days: 30)),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (picked != null) setState(() => _draft.availableFrom = picked);
        },
        icon: const Icon(Icons.event_rounded, size: 19),
        label: Text(
          date == null
              ? 'Available from — choose a date'
              : 'Available from ${date.day}/${date.month}/${date.year}',
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(KhejaRadius.xl),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: KhejaColors.emerald),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: KhejaColors.zinc500,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
