import 'package:intl/intl.dart';

/// Dart mirrors of the Supabase schema. Kept deliberately close to the column
/// names so a row from PostgREST maps across without a translation layer.

final _numberFormat = NumberFormat.decimalPattern('en');

String formatPrice(num amount, [String currency = 'KES']) {
  const symbols = {'KES': 'KSh', 'USD': '\$'};
  final symbol = symbols[currency.trim()] ?? currency.trim();
  return '$symbol ${_numberFormat.format(amount)}';
}

String formatRent(num amount, String period, [String currency = 'KES']) =>
    '${formatPrice(amount, currency)} / $period';

String? formatSize(int? sqft) =>
    (sqft == null || sqft <= 0) ? null : '${_numberFormat.format(sqft)} sqft';

String formatRelativeDate(DateTime? date) {
  if (date == null) return '';
  final days = DateTime.now().difference(date).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  if (days < 30) return '${days ~/ 7} week${days < 14 ? '' : 's'} ago';
  if (days < 365) return '${days ~/ 30} month${days < 60 ? '' : 's'} ago';
  return DateFormat.yMMM().format(date);
}

/// "15 Oct", or "15 Oct 2027" when it is not this year.
String formatShortDate(DateTime date) => date.year == DateTime.now().year
    ? DateFormat('d MMM').format(date)
    : DateFormat('d MMM y').format(date);

DateTime? _date(dynamic value) =>
    value == null ? null : DateTime.tryParse(value.toString())?.toLocal();

int _int(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

num _num(dynamic value, [num fallback = 0]) {
  if (value is num) return value;
  return num.tryParse('$value') ?? fallback;
}

/// One row of `property_types`.
class PropertyType {
  const PropertyType({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
  });

  final String id;
  final String slug;
  final String name;
  final String? description;

  factory PropertyType.fromMap(Map<String, dynamic> map) => PropertyType(
        id: map['id'] as String,
        slug: map['slug'] as String,
        name: map['name'] as String,
        description: map['description'] as String?,
      );
}

/// One row of `locations`.
class KhejaLocation {
  const KhejaLocation({
    required this.id,
    required this.slug,
    required this.name,
    this.area,
    this.county = 'Meru',
    this.latitude,
    this.longitude,
  });

  final String id;
  final String slug;
  final String name;
  final String? area;
  final String county;
  final double? latitude;
  final double? longitude;

  /// "Makutano, Meru"
  String get display => county.isNotEmpty && county != name ? '$name, $county' : name;

  factory KhejaLocation.fromMap(Map<String, dynamic> map) => KhejaLocation(
        id: map['id'] as String,
        slug: map['slug'] as String,
        name: map['name'] as String,
        area: map['area'] as String?,
        county: (map['county'] as String?) ?? 'Meru',
        latitude: map['latitude'] == null ? null : _num(map['latitude']).toDouble(),
        longitude:
            map['longitude'] == null ? null : _num(map['longitude']).toDouble(),
      );
}

/// One row of `amenities`.
class Amenity {
  const Amenity({required this.id, required this.slug, required this.name});

  final String id;
  final String slug;
  final String name;

  factory Amenity.fromMap(Map<String, dynamic> map) => Amenity(
        id: map['id'] as String,
        slug: map['slug'] as String,
        name: map['name'] as String,
      );
}

/// One row of `property_images`.
class PropertyImage {
  const PropertyImage({
    required this.id,
    required this.url,
    this.altText,
    this.isCover = false,
    this.sortOrder = 0,
  });

  final String id;
  final String url;
  final String? altText;
  final bool isCover;
  final int sortOrder;

  factory PropertyImage.fromMap(Map<String, dynamic> map) => PropertyImage(
        id: map['id'] as String,
        url: map['public_url'] as String,
        altText: map['alt_text'] as String?,
        isCover: map['is_cover'] == true,
        sortOrder: _int(map['sort_order']),
      );
}

/// The landlord, as exposed by the `public_profiles` view — name and avatar
/// only. Phone and email are never selectable through it.
class PublicProfile {
  const PublicProfile({
    required this.id,
    this.fullName,
    this.avatarUrl,
    this.isVerified = false,
  });

  final String id;
  final String? fullName;
  final String? avatarUrl;
  final bool isVerified;

  factory PublicProfile.fromMap(Map<String, dynamic> map) => PublicProfile(
        id: map['id'] as String,
        fullName: map['full_name'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        isVerified: map['is_verified'] == true,
      );
}

/// The signed-in user's own `profiles` row.
class Profile {
  const Profile({
    required this.id,
    this.fullName,
    this.phone,
    this.avatarUrl,
    this.role = 'seeker',
    this.isVerified = false,
    this.bio,
    this.tenantOnboardedAt,
    this.landlordOnboardedAt,
  });

  final String id;
  final String? fullName;
  final String? phone;
  final String? avatarUrl;
  final String role;
  final bool isVerified;
  final String? bio;

  /// When this account finished (or skipped) each role's first-run tutorial.
  final DateTime? tenantOnboardedAt;
  final DateTime? landlordOnboardedAt;

  bool get isLandlord => role == 'landlord' || role == 'admin';

  String get firstName {
    final name = fullName?.trim();
    if (name == null || name.isEmpty) return 'there';
    return name.split(' ').first;
  }

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        fullName: map['full_name'] as String?,
        phone: map['phone'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        role: (map['role'] as String?) ?? 'seeker',
        isVerified: map['is_verified'] == true,
        bio: map['bio'] as String?,
        tenantOnboardedAt: _date(map['tenant_onboarded_at']),
        landlordOnboardedAt: _date(map['landlord_onboarded_at']),
      );
}

/// A listing, joined with its type, location and images.
class Property {
  Property({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.slug,
    this.description,
    this.addressLine,
    required this.priceAmount,
    this.priceCurrency = 'KES',
    this.pricePeriod = 'month',
    this.depositMonths = 1,
    this.bedrooms = 0,
    this.bathrooms = 0,
    this.sizeSqft,
    this.isPremium = false,
    this.isFurnished = false,
    this.status = 'published',
    this.availableFrom,
    this.availability = 'available',
    this.noticeDate,
    this.viewCount = 0,
    this.likeCount = 0,
    this.houseRules,
    this.buildingName,
    this.floorNumber,
    this.serviceCharge,
    this.waterBilling,
    this.waterNotes,
    this.electricityBilling,
    this.parkingSpaces = 0,
    this.petsAllowed = false,
    this.minLeaseMonths,
    this.noticeMonths,
    this.nearby,
    this.securityDetails,
    this.internetReady = false,
    this.isGated = false,
    this.hasBalcony = false,
    this.videos = const [],
    this.publishedAt,
    this.createdAt,
    this.propertyType,
    this.location,
    this.images = const [],
    this.amenities = const [],
    this.owner,
    this.isFavorited = false,
  });

  final String id;
  final String ownerId;
  final String title;
  final String slug;
  final String? description;
  final String? addressLine;
  final num priceAmount;
  final String priceCurrency;
  final String pricePeriod;
  final int depositMonths;
  final int bedrooms;
  final int bathrooms;
  final int? sizeSqft;
  final bool isPremium;
  final bool isFurnished;
  final String status;
  final DateTime? availableFrom;

  /// available | occupied | notice_given | unavailable. See 0012.
  final String availability;

  /// When the current tenant gave notice, if the landlord recorded it.
  final DateTime? noticeDate;
  final int viewCount;

  /// How many people have saved this home. Public, so the card can show it.
  final int likeCount;

  /// Landlord's rules for the house, shown on the detail page.
  final String? houseRules;

  final String? buildingName;
  final int? floorNumber;
  final num? serviceCharge;
  final String? waterBilling;
  final String? waterNotes;
  final String? electricityBilling;
  final int parkingSpaces;
  final bool petsAllowed;
  final int? minLeaseMonths;
  final int? noticeMonths;
  final String? nearby;
  final String? securityDetails;
  final bool internetReady;
  final bool isGated;
  final bool hasBalcony;

  /// Video tours, shown in the same swipeable gallery as the photos.
  final List<PropertyVideo> videos;
  final DateTime? publishedAt;
  final DateTime? createdAt;

  final PropertyType? propertyType;
  final KhejaLocation? location;
  final List<PropertyImage> images;
  final List<Amenity> amenities;
  final PublicProfile? owner;

  bool isFavorited;

  String get typeName => propertyType?.name ?? 'Rental';

  bool get isAvailableNow => availability == 'available';
  bool get isComingAvailable => availability == 'notice_given';

  /// Can a tenant request it today? Only a published home that is free now.
  bool get isRequestable => status == 'published' && isAvailableNow;

  /// "Available from 15 Oct", "Currently occupied"… Null when free now, so
  /// cards stay clean. Mirrors availabilityLabel() in the web app.
  String? get availabilityLabel => switch (availability) {
        'notice_given' => availableFrom == null
            ? 'Coming available'
            : 'Available from ${formatShortDate(availableFrom!)}',
        'occupied' => 'Currently occupied',
        'unavailable' => 'Temporarily unavailable',
        _ => null,
      };

  String? get waterLabel => switch (waterBilling) {
        'included' => 'Included in rent',
        'metered' => 'Metered, billed separately',
        'flat_rate' => 'Flat monthly rate',
        'borehole' => 'Borehole supply',
        'none' => 'Tenant arranges own',
        _ => null,
      };

  String? get electricityLabel => switch (electricityBilling) {
        'prepaid_token' => 'Prepaid tokens',
        'postpaid' => 'Postpaid, billed monthly',
        'included' => 'Included in rent',
        'shared_meter' => 'Shared meter',
        _ => null,
      };
  String get locationLabel => location?.display ?? 'Location on request';
  String get rentLabel => formatRent(priceAmount, pricePeriod, priceCurrency);
  String get priceLabel => formatPrice(priceAmount, priceCurrency);
  String? get coverUrl => images.isEmpty ? null : images.first.url;
  String? get sizeLabel => formatSize(sizeSqft);

  static List<PropertyImage> _images(dynamic raw) {
    if (raw is! List) return const [];
    final list = raw
        .whereType<Map<String, dynamic>>()
        .map(PropertyImage.fromMap)
        .toList()
      // The cover always leads; everything else follows its sort order.
      ..sort((a, b) {
        if (a.isCover != b.isCover) return a.isCover ? -1 : 1;
        return a.sortOrder.compareTo(b.sortOrder);
      });
    return list;
  }

  static List<PropertyVideo> _videos(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(PropertyVideo.fromMap)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  static List<Amenity> _amenities(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map((row) => row['amenities'])
        .whereType<Map<String, dynamic>>()
        .map(Amenity.fromMap)
        .toList();
  }

  factory Property.fromMap(Map<String, dynamic> map, {bool isFavorited = false}) {
    final type = map['property_type'];
    final loc = map['location'];
    final owner = map['owner'];

    return Property(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      title: map['title'] as String,
      slug: map['slug'] as String,
      description: map['description'] as String?,
      addressLine: map['address_line'] as String?,
      priceAmount: _num(map['price_amount']),
      priceCurrency: (map['price_currency'] as String?)?.trim() ?? 'KES',
      pricePeriod: (map['price_period'] as String?) ?? 'month',
      depositMonths: _int(map['deposit_months'], 1),
      bedrooms: _int(map['bedrooms']),
      bathrooms: _int(map['bathrooms']),
      sizeSqft: map['size_sqft'] == null ? null : _int(map['size_sqft']),
      isPremium: map['is_premium'] == true,
      isFurnished: map['is_furnished'] == true,
      status: (map['status'] as String?) ?? 'published',
      availableFrom: _date(map['available_from']),
      availability: (map['availability'] as String?) ?? 'available',
      noticeDate: _date(map['notice_date']),
      viewCount: _int(map['view_count']),
      likeCount: _int(map['like_count']),
      houseRules: map['house_rules'] as String?,
      buildingName: map['building_name'] as String?,
      floorNumber: map['floor_number'] == null ? null : _int(map['floor_number']),
      serviceCharge:
          map['service_charge'] == null ? null : _num(map['service_charge']),
      waterBilling: map['water_billing'] as String?,
      waterNotes: map['water_notes'] as String?,
      electricityBilling: map['electricity_billing'] as String?,
      parkingSpaces: _int(map['parking_spaces']),
      petsAllowed: map['pets_allowed'] == true,
      minLeaseMonths:
          map['min_lease_months'] == null ? null : _int(map['min_lease_months']),
      noticeMonths: map['notice_months'] == null ? null : _int(map['notice_months']),
      nearby: map['nearby'] as String?,
      securityDetails: map['security_details'] as String?,
      internetReady: map['internet_ready'] == true,
      isGated: map['is_gated'] == true,
      hasBalcony: map['has_balcony'] == true,
      videos: _videos(map['videos']),
      publishedAt: _date(map['published_at']),
      createdAt: _date(map['created_at']),
      propertyType: type is Map<String, dynamic> ? PropertyType.fromMap(type) : null,
      location: loc is Map<String, dynamic> ? KhejaLocation.fromMap(loc) : null,
      images: _images(map['images']),
      amenities: _amenities(map['property_amenities']),
      owner: owner is Map<String, dynamic> ? PublicProfile.fromMap(owner) : null,
      isFavorited: isFavorited,
    );
  }
}

/// One row of `inquiries`, joined with the listing it is about.
class Inquiry {
  const Inquiry({
    required this.id,
    required this.propertyId,
    required this.name,
    required this.message,
    this.email,
    this.phone,
    this.status = 'new',
    this.createdAt,
    this.propertyTitle,
    this.propertySlug,
  });

  final String id;
  final String propertyId;
  final String name;
  final String message;
  final String? email;
  final String? phone;
  final String status;
  final DateTime? createdAt;
  final String? propertyTitle;
  final String? propertySlug;

  factory Inquiry.fromMap(Map<String, dynamic> map) {
    final property = map['property'];
    return Inquiry(
      id: map['id'] as String,
      propertyId: map['property_id'] as String,
      name: map['name'] as String,
      message: map['message'] as String,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      status: (map['status'] as String?) ?? 'new',
      createdAt: _date(map['created_at']),
      propertyTitle:
          property is Map<String, dynamic> ? property['title'] as String? : null,
      propertySlug:
          property is Map<String, dynamic> ? property['slug'] as String? : null,
    );
  }
}

/// The filter set behind the search screen — the mobile equivalent of the
/// web app's URL query string.
class PropertyFilters {
  const PropertyFilters({
    this.query,
    this.typeSlug,
    this.locationSlug,
    this.minPrice,
    this.maxPrice,
    this.bedrooms,
    this.exactBedrooms = false,
    this.amenitySlugs = const [],
    this.furnished = false,
    this.premium = false,
    this.availableNowOnly = false,
    this.sort = PropertySort.newest,
  });

  final String? query;
  final String? typeSlug;
  final String? locationSlug;
  final num? minPrice;
  final num? maxPrice;
  final int? bedrooms;

  /// True for the "1 / 2 / 3 Bedroom" categories: exactly that many rather
  /// than "at least".
  final bool exactBedrooms;
  final List<String> amenitySlugs;
  final bool furnished;
  final bool premium;

  /// Hide homes that are occupied or only coming available.
  final bool availableNowOnly;
  final PropertySort sort;

  int get activeCount => [
        typeSlug,
        locationSlug,
        minPrice,
        maxPrice,
        bedrooms,
        amenitySlugs.isEmpty ? null : amenitySlugs,
        furnished ? true : null,
        premium ? true : null,
        availableNowOnly ? true : null,
      ].where((value) => value != null).length;

  PropertyFilters copyWith({
    Object? query = _sentinel,
    Object? typeSlug = _sentinel,
    Object? locationSlug = _sentinel,
    Object? minPrice = _sentinel,
    Object? maxPrice = _sentinel,
    Object? bedrooms = _sentinel,
    bool? exactBedrooms,
    List<String>? amenitySlugs,
    bool? furnished,
    bool? premium,
    bool? availableNowOnly,
    PropertySort? sort,
  }) {
    return PropertyFilters(
      query: query == _sentinel ? this.query : query as String?,
      typeSlug: typeSlug == _sentinel ? this.typeSlug : typeSlug as String?,
      locationSlug:
          locationSlug == _sentinel ? this.locationSlug : locationSlug as String?,
      minPrice: minPrice == _sentinel ? this.minPrice : minPrice as num?,
      maxPrice: maxPrice == _sentinel ? this.maxPrice : maxPrice as num?,
      bedrooms: bedrooms == _sentinel ? this.bedrooms : bedrooms as int?,
      exactBedrooms: exactBedrooms ?? this.exactBedrooms,
      amenitySlugs: amenitySlugs ?? this.amenitySlugs,
      furnished: furnished ?? this.furnished,
      premium: premium ?? this.premium,
      availableNowOnly: availableNowOnly ?? this.availableNowOnly,
      sort: sort ?? this.sort,
    );
  }

  static const _sentinel = Object();
}

enum PropertySort {
  newest('Newest first'),
  priceAsc('Price: low to high'),
  priceDesc('Price: high to low'),
  bedroomsDesc('Most bedrooms'),
  popular('Most viewed');

  const PropertySort(this.label);
  final String label;
}

// =============================================================================
// Marketplace additions: partners, notifications, unlocks, tenancies
// =============================================================================

/// A mover, internet provider or cleaning company shown under a listing.
///
/// [logoUrl] is null until a real agreement exists; the UI then draws a styled
/// name tile instead, so no third party's trademark is reproduced.
class Partner {
  const Partner({
    required this.id,
    required this.category,
    required this.slug,
    required this.name,
    this.tagline,
    this.logoUrl,
    this.brandColor = '#2563EB',
    this.phone,
    this.url,
    this.isOurs = false,
  });

  final String id;
  final String category; // movers | isp | cleaning
  final String slug;
  final String name;
  final String? tagline;
  final String? logoUrl;
  final String brandColor;
  final String? phone;
  final String? url;
  final bool isOurs;

  /// Partners whose logo ships inside the app, so the tile draws instantly and
  /// works with no data. Anyone else uses [logoUrl].
  static const _bundledLogos = {
    'movemate-kenya': 'assets/branding/movemate-kenya.jpeg',
  };

  String? get bundledLogoAsset => _bundledLogos[slug];

  /// "#2563EB" -> 0xFF2563EB, falling back to the brand blue.
  int get colorValue {
    final hex = brandColor.replaceAll('#', '').trim();
    if (hex.length != 6) return 0xFF2563EB;
    return int.tryParse('FF$hex', radix: 16) ?? 0xFF2563EB;
  }

  /// Initials for the styled tile, e.g. "Moving Solutions" -> "MS".
  String get initials {
    final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, 1).toUpperCase();
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  factory Partner.fromMap(Map<String, dynamic> map) => Partner(
        id: map['id'] as String,
        category: map['category'] as String,
        slug: map['slug'] as String,
        name: map['name'] as String,
        tagline: map['tagline'] as String?,
        logoUrl: map['logo_url'] as String?,
        brandColor: (map['brand_color'] as String?) ?? '#2563EB',
        phone: map['phone'] as String?,
        url: map['url'] as String?,
        isOurs: map['is_ours'] == true,
      );
}

/// An in-app notification. There is no push infrastructure — these are read
/// when the app is open.
class KhejaNotification {
  const KhejaNotification({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.propertyId,
    this.isRead = false,
    this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final String? body;
  final String? propertyId;
  final bool isRead;
  final DateTime? createdAt;

  factory KhejaNotification.fromMap(Map<String, dynamic> map) => KhejaNotification(
        id: map['id'] as String,
        type: (map['type'] as String?) ?? 'system',
        title: map['title'] as String,
        body: map['body'] as String?,
        propertyId: map['property_id'] as String?,
        isRead: map['is_read'] == true,
        createdAt: _date(map['created_at']),
      );
}

/// The landlord's contact details, once the listing's contact unlock has been
/// paid (or a House Hunting pass bought before 0015 covers it).
/// Everything is null while [unlocked] is false — the database does not send
/// the values at all, rather than the app hiding them.
class PropertyContact {
  const PropertyContact({
    required this.unlocked,
    this.unlockedUntil,
    this.addressLine,
    this.buildingName,
    this.landlordName,
    this.phone,
    this.whatsapp,
    this.caretakerName,
    this.caretakerPhone,
    this.managementName,
    this.managementPhone,
    this.latitude,
    this.longitude,
  });

  final bool unlocked;

  /// When the paid window closes (3 hours after payment). Null when there is
  /// no window: the owner, an admin, or a House Hunting pass.
  final DateTime? unlockedUntil;

  /// The exact location — part of what the unlock buys (0016).
  final String? addressLine;
  final String? buildingName;

  final String? landlordName;
  final String? phone;
  final String? whatsapp;
  final String? caretakerName;
  final String? caretakerPhone;

  /// Kheja_Link's own line, for when the landlord and caretaker cannot be
  /// reached. Released by the same unlock.
  final String? managementName;
  final String? managementPhone;

  final double? latitude;
  final double? longitude;

  bool get hasMap => latitude != null && longitude != null;

  static const locked = PropertyContact(unlocked: false);

  factory PropertyContact.fromMap(Map<String, dynamic> map) => PropertyContact(
        unlocked: map['unlocked'] == true,
        unlockedUntil: _date(map['unlocked_until'])?.toLocal(),
        addressLine: map['address_line'] as String?,
        buildingName: map['building_name'] as String?,
        landlordName: map['landlord_name'] as String?,
        phone: map['contact_phone'] as String?,
        whatsapp: map['contact_whatsapp'] as String?,
        caretakerName: map['caretaker_name'] as String?,
        caretakerPhone: map['caretaker_phone'] as String?,
        managementName: map['management_name'] as String?,
        managementPhone: map['management_phone'] as String?,
        latitude: map['latitude'] == null ? null : _num(map['latitude']).toDouble(),
        longitude: map['longitude'] == null ? null : _num(map['longitude']).toDouble(),
      );
}

/// A house request, and the tenancy it becomes.
///
///   booked      pending — sent, waiting for the landlord
///   viewed      the landlord has opened it
///   accepted    the landlord agreed; the tenant can move in
///   declined    the landlord said no
///   checked_in  the tenant moved in
///   moved_out   the tenancy ended
///   cancelled   withdrawn by the tenant
///
/// The database decides who may move a request where (tenancies_guard_transition
/// in 0012); the app only offers the moves that are allowed.
class Tenancy {
  const Tenancy({
    required this.id,
    required this.propertyId,
    required this.tenantId,
    required this.status,
    this.propertyTitle,
    this.propertySlug,
    this.tenantName,
    this.bookedAt,
    this.checkedInAt,
    this.movedOutAt,
    this.preferredMoveIn,
    this.note,
    this.landlordResponse,
    this.respondedAt,
  });

  final String id;
  final String propertyId;
  final String tenantId;
  final String status;
  final String? propertyTitle;
  final String? propertySlug;
  final String? tenantName;
  final DateTime? bookedAt;
  final DateTime? checkedInAt;
  final DateTime? movedOutAt;
  final DateTime? preferredMoveIn;
  final String? note;
  final String? landlordResponse;
  final DateTime? respondedAt;

  /// Still open, which blocks a second request for the same home.
  bool get isActive =>
      const {'booked', 'viewed', 'accepted', 'checked_in'}.contains(status);

  bool get isPending => status == 'booked' || status == 'viewed';
  bool get canWithdraw => const {'booked', 'viewed', 'accepted'}.contains(status);

  String get statusLabel => tenancyStatusLabel(status);

  factory Tenancy.fromMap(Map<String, dynamic> map) {
    final property = map['property'];
    final tenant = map['tenant'];
    return Tenancy(
      id: map['id'] as String,
      propertyId: map['property_id'] as String,
      tenantId: map['tenant_id'] as String,
      status: (map['status'] as String?) ?? 'booked',
      propertyTitle:
          property is Map<String, dynamic> ? property['title'] as String? : null,
      propertySlug:
          property is Map<String, dynamic> ? property['slug'] as String? : null,
      tenantName:
          tenant is Map<String, dynamic> ? tenant['full_name'] as String? : null,
      bookedAt: _date(map['booked_at']),
      checkedInAt: _date(map['checked_in_at']),
      movedOutAt: _date(map['moved_out_at']),
      preferredMoveIn: _date(map['preferred_move_in']),
      note: map['note'] as String?,
      landlordResponse: map['landlord_response'] as String?,
      respondedAt: _date(map['responded_at']),
    );
  }
}

String tenancyStatusLabel(String status) => switch (status) {
      'booked' => 'Pending',
      'viewed' => 'Viewed by landlord',
      'accepted' => 'Accepted',
      'declined' => 'Declined',
      'checked_in' => 'Living here',
      'moved_out' => 'Moved out',
      _ => 'Withdrawn',
    };

/// A request as the landlord sees it, from get_requests_for_owner(). The
/// tenant's phone number is only present once the landlord has accepted.
class OwnerRequest {
  const OwnerRequest({
    required this.id,
    required this.propertyId,
    required this.propertyTitle,
    required this.propertySlug,
    required this.tenantName,
    required this.status,
    this.propertyType,
    this.tenantPhone,
    this.note,
    this.preferredMoveIn,
    this.landlordResponse,
    this.bookedAt,
    this.respondedAt,
  });

  final String id;
  final String propertyId;
  final String propertyTitle;
  final String propertySlug;
  final String? propertyType;
  final String tenantName;
  final String? tenantPhone;
  final String status;
  final String? note;
  final DateTime? preferredMoveIn;
  final String? landlordResponse;
  final DateTime? bookedAt;
  final DateTime? respondedAt;

  bool get isOpen => status == 'booked' || status == 'viewed';
  String get statusLabel => tenancyStatusLabel(status);

  OwnerRequest withStatus(String next) => OwnerRequest(
        id: id,
        propertyId: propertyId,
        propertyTitle: propertyTitle,
        propertySlug: propertySlug,
        propertyType: propertyType,
        tenantName: tenantName,
        tenantPhone: tenantPhone,
        status: next,
        note: note,
        preferredMoveIn: preferredMoveIn,
        landlordResponse: landlordResponse,
        bookedAt: bookedAt,
        respondedAt: respondedAt,
      );

  factory OwnerRequest.fromMap(Map<String, dynamic> map) => OwnerRequest(
        id: map['id'] as String,
        propertyId: map['property_id'] as String,
        propertyTitle: (map['property_title'] as String?) ?? 'A listing',
        propertySlug: (map['property_slug'] as String?) ?? '',
        propertyType: map['property_type'] as String?,
        tenantName: (map['tenant_name'] as String?) ?? 'A tenant',
        tenantPhone: map['tenant_phone'] as String?,
        status: (map['status'] as String?) ?? 'booked',
        note: map['note'] as String?,
        preferredMoveIn: _date(map['preferred_move_in']),
        landlordResponse: map['landlord_response'] as String?,
        bookedAt: _date(map['booked_at']),
        respondedAt: _date(map['responded_at']),
      );
}

/// What a search suggestion points at.
enum SuggestionKind { location, type, property }

/// One row in the search-suggestion dropdown.
class SearchSuggestion {
  const SearchSuggestion({
    required this.label,
    required this.kind,
    required this.value,
  });

  final String label;
  final SuggestionKind kind;

  /// A slug: the location, the property type, or the listing itself.
  final String value;

  String get hint => switch (kind) {
        SuggestionKind.location => 'Area',
        SuggestionKind.type => 'House type',
        SuggestionKind.property => 'Listing',
      };
}

/// A video tour of a listing.
class PropertyVideo {
  const PropertyVideo({
    required this.id,
    required this.url,
    this.thumbnailUrl,
    this.caption,
    this.durationSeconds,
    this.sortOrder = 0,
  });

  final String id;
  final String url;
  final String? thumbnailUrl;
  final String? caption;
  final int? durationSeconds;
  final int sortOrder;

  factory PropertyVideo.fromMap(Map<String, dynamic> map) => PropertyVideo(
        id: map['id'] as String,
        url: map['public_url'] as String,
        thumbnailUrl: map['thumbnail_url'] as String?,
        caption: map['caption'] as String?,
        durationSeconds:
            map['duration_seconds'] == null ? null : _int(map['duration_seconds']),
        sortOrder: _int(map['sort_order']),
      );
}

/// One swipeable item in the gallery: a photo or a video.
class GalleryItem {
  const GalleryItem.photo(this.url) : isVideo = false, thumbnailUrl = null;
  const GalleryItem.video(this.url, {this.thumbnailUrl}) : isVideo = true;

  final String url;
  final bool isVideo;
  final String? thumbnailUrl;
}

/// Everything a landlord fills in when listing a property.
///
/// Kept as one mutable object so the editor can build it up across several
/// sections and hand it to the API in one go.
class ListingDraft {
  ListingDraft();

  // Basics
  String title = '';
  String description = '';
  String? propertyTypeId;
  String? locationId;
  String addressLine = '';
  String buildingName = '';
  int? floorNumber;
  String nearby = '';

  // Rent and terms
  num? priceAmount;
  String pricePeriod = 'month';
  int depositMonths = 1;
  num? serviceCharge;
  int? minLeaseMonths;
  int? noticeMonths;
  DateTime? availableFrom;

  // The home itself
  int bedrooms = 1;
  int bathrooms = 1;
  int? sizeSqft;
  int parkingSpaces = 0;
  bool isFurnished = false;
  bool petsAllowed = false;
  bool internetReady = false;
  bool isGated = false;
  bool hasBalcony = false;
  bool isPremium = false;

  // Utilities
  String? waterBilling;
  String waterNotes = '';
  String? electricityBilling;

  // Safety and rules
  String securityDetails = '';
  String houseRules = '';

  // People — private until a tenant pays to unlock
  String landlordName = '';
  String contactPhone = '';
  String contactWhatsapp = '';
  String caretakerName = '';
  String caretakerPhone = '';

  // Where exactly — also private until unlocked
  double? latitude;
  double? longitude;

  // Media, already uploaded to storage
  List<String> photoUrls = [];
  List<String> videoUrls = [];

  List<String> amenityIds = [];

  String status = 'published';

  static String? _blank(String value) {
    final t = value.trim();
    return t.isEmpty ? null : t;
  }

  /// The row sent to Postgres. Blank text becomes NULL rather than ''.
  Map<String, dynamic> toRow() => {
        'title': title.trim(),
        'description': _blank(description),
        'property_type_id': propertyTypeId,
        'location_id': locationId,
        'address_line': _blank(addressLine),
        'building_name': _blank(buildingName),
        'floor_number': floorNumber,
        'nearby': _blank(nearby),
        'price_amount': priceAmount,
        'price_currency': 'KES',
        'price_period': pricePeriod,
        'deposit_months': depositMonths,
        'service_charge': serviceCharge,
        'min_lease_months': minLeaseMonths,
        'notice_months': noticeMonths,
        'available_from': availableFrom?.toIso8601String().substring(0, 10),
        'bedrooms': bedrooms,
        'bathrooms': bathrooms,
        'size_sqft': sizeSqft,
        'parking_spaces': parkingSpaces,
        'is_furnished': isFurnished,
        'pets_allowed': petsAllowed,
        'internet_ready': internetReady,
        'is_gated': isGated,
        'has_balcony': hasBalcony,
        'is_premium': isPremium,
        'water_billing': waterBilling,
        'water_notes': _blank(waterNotes),
        'electricity_billing': electricityBilling,
        'security_details': _blank(securityDetails),
        'house_rules': _blank(houseRules),
        'landlord_name': _blank(landlordName),
        'contact_phone': _blank(contactPhone),
        'contact_whatsapp': _blank(contactWhatsapp),
        'caretaker_name': _blank(caretakerName),
        'caretaker_phone': _blank(caretakerPhone),
        'latitude': latitude,
        'longitude': longitude,
        'status': status,
      };

  /// What still needs filling in before this can be published. Empty means
  /// ready. Drafts may be saved with gaps; publishing may not.
  List<String> missingForPublish() => [
        if (title.trim().length < 6) 'A title of at least 6 characters',
        if (propertyTypeId == null) 'The property type',
        if (locationId == null) 'The area',
        if (priceAmount == null || priceAmount! <= 0) 'The rent',
        if (description.trim().length < 30) 'A description of at least 30 characters',
        if (contactPhone.trim().isEmpty) 'A contact phone number',
        if (photoUrls.isEmpty) 'At least one photo',
      ];

  factory ListingDraft.fromProperty(
    Property p, {
    Map<String, dynamic>? private,
    List<String> amenityIds = const [],
  }) {
    final d = ListingDraft()
      ..title = p.title
      ..description = p.description ?? ''
      ..propertyTypeId = p.propertyType?.id
      ..locationId = p.location?.id
      ..addressLine = ''
      ..buildingName = ''
      ..floorNumber = p.floorNumber
      ..nearby = p.nearby ?? ''
      ..priceAmount = p.priceAmount
      ..pricePeriod = p.pricePeriod
      ..depositMonths = p.depositMonths
      ..serviceCharge = p.serviceCharge
      ..minLeaseMonths = p.minLeaseMonths
      ..noticeMonths = p.noticeMonths
      ..availableFrom = p.availableFrom
      ..bedrooms = p.bedrooms
      ..bathrooms = p.bathrooms
      ..sizeSqft = p.sizeSqft
      ..parkingSpaces = p.parkingSpaces
      ..isFurnished = p.isFurnished
      ..petsAllowed = p.petsAllowed
      ..internetReady = p.internetReady
      ..isGated = p.isGated
      ..hasBalcony = p.hasBalcony
      ..isPremium = p.isPremium
      ..waterBilling = p.waterBilling
      ..waterNotes = p.waterNotes ?? ''
      ..electricityBilling = p.electricityBilling
      ..securityDetails = p.securityDetails ?? ''
      ..houseRules = p.houseRules ?? ''
      ..photoUrls = p.images.map((i) => i.url).toList()
      ..videoUrls = p.videos.map((v) => v.url).toList()
      ..amenityIds = [...amenityIds]
      ..status = p.status == 'pending' ? 'draft' : p.status;

    if (private != null) {
      d
        ..landlordName = (private['landlord_name'] as String?) ?? ''
        ..contactPhone = (private['contact_phone'] as String?) ?? ''
        ..contactWhatsapp = (private['contact_whatsapp'] as String?) ?? ''
        ..caretakerName = (private['caretaker_name'] as String?) ?? ''
        ..caretakerPhone = (private['caretaker_phone'] as String?) ?? ''
        ..addressLine = (private['address_line'] as String?) ?? ''
        ..buildingName = (private['building_name'] as String?) ?? ''
        ..latitude = private['latitude'] == null ? null : _num(private['latitude']).toDouble()
        ..longitude =
            private['longitude'] == null ? null : _num(private['longitude']).toDouble();
    }
    return d;
  }
}

// =============================================================================
// 0012: business settings, house hunting, interests, preferences
// =============================================================================

/// The business rules both apps read from app_settings, so a price or a
/// feature flag changes without a new build. The defaults match the migration
/// and are what the app shows before the first load, or with no data.
///
/// The prices here are for display. What M-Pesa actually charges is set by the
/// database from the same rows when the tenant taps "Unlock contact".
class BusinessSettings {
  const BusinessSettings({
    this.contactUnlockFee = 500,
    this.contactUnlockCurrency = 'KES',
    this.houseRefundAmount = 200,
    this.unlockHours = 3,
    this.landlordListingFee = 0,
    this.listingOfferLabel = 'Free Property Listing — Limited-Time Offer',
    this.listingOfferEndsOn,
  });

  /// One price to unlock any listing. Paying opens it for [unlockHours].
  final num contactUnlockFee;
  final String contactUnlockCurrency;

  /// Refunded to a tenant who paid for an unlock and then gives us a house.
  final num houseRefundAmount;

  /// How long a paid unlock stays open.
  final int unlockHours;

  final num landlordListingFee;
  final String listingOfferLabel;

  /// Only shown when an admin has actually set one.
  final DateTime? listingOfferEndsOn;

  bool get listingIsFree => landlordListingFee <= 0;
  bool get refundsEnabled => houseRefundAmount > 0 && houseRefundAmount < contactUnlockFee;
  String get unlockFeeLabel => formatPrice(contactUnlockFee, contactUnlockCurrency);
  String get refundLabel => formatPrice(houseRefundAmount, contactUnlockCurrency);

  Map<String, String> toCache() => {
        'contact_unlock_fee': '$contactUnlockFee',
        'contact_unlock_currency': contactUnlockCurrency,
        'house_refund_amount': '$houseRefundAmount',
        'contact_unlock_hours': '$unlockHours',
        'landlord_listing_fee': '$landlordListingFee',
        'landlord_listing_fee_offer_label': listingOfferLabel,
        'landlord_listing_fee_offer_ends_on':
            listingOfferEndsOn?.toIso8601String().substring(0, 10) ?? '',
      };

  factory BusinessSettings.fromMap(Map<String, String> m) {
    num? n(String k) => num.tryParse(m[k]?.trim() ?? '');
    String? t(String k) {
      final v = m[k]?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    const d = BusinessSettings();
    return BusinessSettings(
      contactUnlockFee: n('contact_unlock_fee') ?? d.contactUnlockFee,
      contactUnlockCurrency: t('contact_unlock_currency') ?? d.contactUnlockCurrency,
      houseRefundAmount: n('house_refund_amount') ?? d.houseRefundAmount,
      unlockHours: n('contact_unlock_hours')?.toInt() ?? d.unlockHours,
      landlordListingFee: n('landlord_listing_fee') ?? d.landlordListingFee,
      listingOfferLabel: t('landlord_listing_fee_offer_label') ?? d.listingOfferLabel,
      listingOfferEndsOn: DateTime.tryParse(t('landlord_listing_fee_offer_ends_on') ?? ''),
    );
  }
}

/// The House Hunting pass: no longer sold (0015), but a pass bought before
/// then keeps every listing unlocked while it is active.
/// unpaid → payment_pending → service_active → matched → completed.
class HuntingService {
  const HuntingService({this.status = 'unpaid', this.activatedAt, this.matchedPropertyId});

  final String status;
  final DateTime? activatedAt;
  final String? matchedPropertyId;

  static const none = HuntingService();

  bool get isActive => const {'paid', 'service_active', 'matched'}.contains(status);
  bool get isPending => status == 'payment_pending';
  bool get isCompleted => status == 'completed';

  String get label => switch (status) {
        'payment_pending' => 'Payment pending',
        'paid' || 'service_active' => 'Active',
        'matched' => 'Matched with a home',
        'completed' => 'Completed — you moved in',
        _ => 'Not started',
      };

  factory HuntingService.fromMap(Map<String, dynamic> map) => HuntingService(
        status: (map['status'] as String?) ?? 'unpaid',
        activatedAt: _date(map['activated_at']),
        matchedPropertyId: map['matched_property_id'] as String?,
      );
}

/// What start_contact_unlock() hands back: the checkout to pay, or nothing to
/// buy because the listing is already unlocked.
class UnlockCheckout {
  const UnlockCheckout({
    required this.reference,
    required this.amount,
    required this.currency,
    required this.alreadyUnlocked,
  });

  final String? reference;
  final num amount;
  final String currency;
  final bool alreadyUnlocked;

  String get amountLabel => formatPrice(amount, currency);

  factory UnlockCheckout.fromMap(Map<String, dynamic> map) => UnlockCheckout(
        reference: map['reference'] as String?,
        amount: (map['amount'] as num?) ?? 0,
        currency: ((map['currency'] as String?) ?? 'KES').trim(),
        alreadyUnlocked: map['already_unlocked'] == true,
      );
}

/// A house a tenant gave us, with the refund it earned, if any.
class HouseSubmission {
  const HouseSubmission({
    required this.id,
    required this.status,
    required this.createdAt,
    this.area,
    this.locationName,
    this.propertyTypeName,
    this.bedrooms,
    this.adminNote,
    this.refund,
  });

  final String id;

  /// pending, approved or rejected.
  final String status;
  final DateTime createdAt;
  final String? area;
  final String? locationName;
  final String? propertyTypeName;
  final int? bedrooms;
  final String? adminNote;
  final UnlockRefund? refund;

  String get title {
    final kind = [
      if (bedrooms != null) '$bedrooms-bedroom',
      propertyTypeName ?? 'House',
    ].join(' ');
    final where = [
      if (area != null && area!.trim().isNotEmpty) area!.trim(),
      if (locationName != null) locationName!,
    ].join(', ');
    return where.isEmpty ? kind : '$kind in $where';
  }

  String get statusLabel => switch (status) {
        'approved' => 'House approved',
        'rejected' => 'House not approved',
        _ => 'House under review',
      };

  factory HouseSubmission.fromMap(Map<String, dynamic> map) {
    final rawRefund = map['refund'];
    final refundMap = rawRefund is List
        ? (rawRefund.isEmpty ? null : rawRefund.first)
        : rawRefund;
    return HouseSubmission(
      id: map['id'] as String,
      status: (map['status'] as String?) ?? 'pending',
      createdAt: _date(map['created_at']) ?? DateTime.now(),
      area: map['area'] as String?,
      locationName: (map['location'] as Map?)?['name'] as String?,
      propertyTypeName: (map['property_type'] as Map?)?['name'] as String?,
      bedrooms: (map['bedrooms'] as num?)?.toInt(),
      adminNote: map['admin_note'] as String?,
      refund: refundMap is Map
          ? UnlockRefund.fromMap(Map<String, dynamic>.from(refundMap))
          : null,
    );
  }
}

/// pending (house under review) → approved (money owed) → paid; or rejected.
class UnlockRefund {
  const UnlockRefund({
    required this.id,
    required this.amount,
    required this.currency,
    required this.status,
    this.payoutReference,
    this.paidAt,
  });

  final String id;
  final num amount;
  final String currency;
  final String status;
  final String? payoutReference;
  final DateTime? paidAt;

  String get amountLabel => formatPrice(amount, currency);

  String get statusLabel => switch (status) {
        'approved' => 'Refund approved — on its way',
        'paid' => 'Refund paid',
        'rejected' => 'No refund',
        _ => 'Refund pending',
      };

  factory UnlockRefund.fromMap(Map<String, dynamic> map) => UnlockRefund(
        id: map['id'] as String,
        amount: (map['amount'] as num?) ?? 0,
        currency: ((map['currency'] as String?) ?? 'KES').trim(),
        status: (map['status'] as String?) ?? 'pending',
        payoutReference: map['payout_reference'] as String?,
        paidAt: _date(map['paid_at']),
      );
}

/// "Notify me": one exact home, or a standing search.
class PropertyInterest {
  const PropertyInterest({
    required this.id,
    this.propertyId,
    this.propertyTypeId,
    this.locationId,
    this.minPrice,
    this.maxPrice,
    this.bedrooms,
    this.availableWithinDays,
    this.status = 'active',
    this.createdAt,
    this.lastNotifiedAt,
    this.property,
    this.typeName,
    this.locationName,
  });

  final String id;
  final String? propertyId;
  final String? propertyTypeId;
  final String? locationId;
  final num? minPrice;
  final num? maxPrice;
  final int? bedrooms;
  final int? availableWithinDays;
  final String status;
  final DateTime? createdAt;
  final DateTime? lastNotifiedAt;
  final Property? property;
  final String? typeName;
  final String? locationName;

  bool get isForProperty => propertyId != null;
  bool get isActive => status == 'active';

  /// "1-bedroom Apartment in Makutano, up to KSh 20,000"
  String get summary {
    final what = [
      if (bedrooms != null) bedrooms == 0 ? 'Studio' : '$bedrooms-bedroom',
      typeName ?? (bedrooms == null ? 'Any home' : 'home'),
    ].join(' ');

    final parts = <String>[what];
    if (locationName != null) parts.add('in $locationName');
    if (minPrice != null && maxPrice != null) {
      parts.add('${formatPrice(minPrice!)}–${formatPrice(maxPrice!)}');
    } else if (maxPrice != null) {
      parts.add('up to ${formatPrice(maxPrice!)}');
    } else if (minPrice != null) {
      parts.add('from ${formatPrice(minPrice!)}');
    }
    if (availableWithinDays != null) parts.add('free within $availableWithinDays days');
    return parts.join(', ');
  }

  factory PropertyInterest.fromMap(Map<String, dynamic> map) {
    final property = map['property'];
    final type = map['property_type'];
    final location = map['location'];
    return PropertyInterest(
      id: map['id'] as String,
      propertyId: map['property_id'] as String?,
      propertyTypeId: map['property_type_id'] as String?,
      locationId: map['location_id'] as String?,
      minPrice: map['min_price'] == null ? null : _num(map['min_price']),
      maxPrice: map['max_price'] == null ? null : _num(map['max_price']),
      bedrooms: map['bedrooms'] == null ? null : _int(map['bedrooms']),
      availableWithinDays:
          map['available_within_days'] == null ? null : _int(map['available_within_days']),
      status: (map['status'] as String?) ?? 'active',
      createdAt: _date(map['created_at']),
      lastNotifiedAt: _date(map['last_notified_at']),
      property: property is Map<String, dynamic> ? Property.fromMap(property) : null,
      typeName: type is Map<String, dynamic> ? type['name'] as String? : null,
      locationName: location is Map<String, dynamic> ? location['name'] as String? : null,
    );
  }
}

/// Which kinds of notification a person wants. Everything is delivered in
/// the app's Inbox — Kheja_Link sends no email or SMS — so there is no channel
/// to choose, only what to hear about.
class NotificationPreferences {
  const NotificationPreferences({
    this.availabilityAlerts = true,
    this.requestUpdates = true,
  });

  final bool availabilityAlerts;
  final bool requestUpdates;

  NotificationPreferences copyWith({bool? availabilityAlerts, bool? requestUpdates}) =>
      NotificationPreferences(
        availabilityAlerts: availabilityAlerts ?? this.availabilityAlerts,
        requestUpdates: requestUpdates ?? this.requestUpdates,
      );

  Map<String, dynamic> toRow() => {
        'availability_alerts': availabilityAlerts,
        'request_updates': requestUpdates,
      };

  factory NotificationPreferences.fromMap(Map<String, dynamic> map) => NotificationPreferences(
        availabilityAlerts: map['availability_alerts'] != false,
        requestUpdates: map['request_updates'] != false,
      );
}

/// Someone waiting on, or saving, one of a landlord's homes. First name only.
class InterestedTenant {
  const InterestedTenant({required this.firstName, required this.kind, this.since});

  final String firstName;
  final String kind; // waiting | saved
  final DateTime? since;

  factory InterestedTenant.fromMap(Map<String, dynamic> map) => InterestedTenant(
        firstName: (map['first_name'] as String?) ?? 'A tenant',
        kind: (map['kind'] as String?) ?? 'saved',
        since: _date(map['since']),
      );
}
