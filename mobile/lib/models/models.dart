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
  });

  final String id;
  final String? fullName;
  final String? phone;
  final String? avatarUrl;
  final String role;
  final bool isVerified;
  final String? bio;

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
    this.viewCount = 0,
    this.likeCount = 0,
    this.houseRules,
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
  final int viewCount;

  /// How many people have saved this home. Public, so the card can show it.
  final int likeCount;

  /// Landlord's rules for the house, shown on the detail page.
  final String? houseRules;
  final DateTime? publishedAt;
  final DateTime? createdAt;

  final PropertyType? propertyType;
  final KhejaLocation? location;
  final List<PropertyImage> images;
  final List<Amenity> amenities;
  final PublicProfile? owner;

  bool isFavorited;

  String get typeName => propertyType?.name ?? 'Rental';
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
      viewCount: _int(map['view_count']),
      likeCount: _int(map['like_count']),
      houseRules: map['house_rules'] as String?,
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
    this.amenitySlugs = const [],
    this.furnished = false,
    this.premium = false,
    this.sort = PropertySort.newest,
  });

  final String? query;
  final String? typeSlug;
  final String? locationSlug;
  final num? minPrice;
  final num? maxPrice;
  final int? bedrooms;
  final List<String> amenitySlugs;
  final bool furnished;
  final bool premium;
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
      ].where((value) => value != null).length;

  PropertyFilters copyWith({
    Object? query = _sentinel,
    Object? typeSlug = _sentinel,
    Object? locationSlug = _sentinel,
    Object? minPrice = _sentinel,
    Object? maxPrice = _sentinel,
    Object? bedrooms = _sentinel,
    List<String>? amenitySlugs,
    bool? furnished,
    bool? premium,
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
      amenitySlugs: amenitySlugs ?? this.amenitySlugs,
      furnished: furnished ?? this.furnished,
      premium: premium ?? this.premium,
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

/// The landlord's contact details, once the KSh 150 unlock has been paid.
/// Everything is null while [unlocked] is false — the database does not send
/// the values at all, rather than the app hiding them.
class PropertyContact {
  const PropertyContact({
    required this.unlocked,
    this.phone,
    this.whatsapp,
    this.latitude,
    this.longitude,
  });

  final bool unlocked;
  final String? phone;
  final String? whatsapp;
  final double? latitude;
  final double? longitude;

  bool get hasMap => latitude != null && longitude != null;

  static const locked = PropertyContact(unlocked: false);

  factory PropertyContact.fromMap(Map<String, dynamic> map) => PropertyContact(
        unlocked: map['unlocked'] == true,
        phone: map['contact_phone'] as String?,
        whatsapp: map['contact_whatsapp'] as String?,
        latitude: map['latitude'] == null ? null : _num(map['latitude']).toDouble(),
        longitude: map['longitude'] == null ? null : _num(map['longitude']).toDouble(),
      );
}

/// A tenant's relationship with a house: booked, moved in, moved out.
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
  });

  final String id;
  final String propertyId;
  final String tenantId;
  final String status; // booked | checked_in | moved_out | cancelled
  final String? propertyTitle;
  final String? propertySlug;
  final String? tenantName;
  final DateTime? bookedAt;
  final DateTime? checkedInAt;
  final DateTime? movedOutAt;

  bool get isActive => status == 'booked' || status == 'checked_in';

  String get statusLabel => switch (status) {
        'booked' => 'Booked',
        'checked_in' => 'Living here',
        'moved_out' => 'Moved out',
        _ => 'Cancelled',
      };

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
    );
  }
}

/// What the KSh 150 unlock costs, in one place.
const kUnlockAmount = 150;
const kUnlockCurrency = 'KES';

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
