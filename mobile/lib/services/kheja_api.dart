import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';

/// Every read and write the app performs.
///
/// Authorization is not implemented here — it lives in Row Level Security on
/// the database, exactly as it does for the web app. These methods simply ask
/// for what the user should be able to see; Postgres decides what comes back.
class KhejaApi {
  KhejaApi(this._client);

  final SupabaseClient _client;

  static const _listSelect = '''
    *,
    property_type:property_types ( id, slug, name, description ),
    location:locations ( id, slug, name, area, county, latitude, longitude ),
    images:property_images ( id, public_url, alt_text, is_cover, sort_order )
  ''';

  User? get currentUser => _client.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  // ---------------------------------------------------------------------------
  // Reference data
  // ---------------------------------------------------------------------------

  Future<List<PropertyType>> fetchPropertyTypes() async {
    final rows = await _client.from('property_types').select().order('sort_order');
    return rows.map<PropertyType>((r) => PropertyType.fromMap(r)).toList();
  }

  Future<List<KhejaLocation>> fetchLocations() async {
    final rows = await _client.from('locations').select().order('name');
    return rows.map<KhejaLocation>((r) => KhejaLocation.fromMap(r)).toList();
  }

  Future<List<Amenity>> fetchAmenities() async {
    final rows = await _client.from('amenities').select().order('sort_order');
    return rows.map<Amenity>((r) => Amenity.fromMap(r)).toList();
  }

  /// Cheapest and dearest published rent, used to bound the price slider.
  Future<({num min, num max})> fetchPriceBounds() async {
    final cheapest = await _client
        .from('properties')
        .select('price_amount')
        .eq('status', 'published')
        .order('price_amount', ascending: true)
        .limit(1)
        .maybeSingle();

    final dearest = await _client
        .from('properties')
        .select('price_amount')
        .eq('status', 'published')
        .order('price_amount', ascending: false)
        .limit(1)
        .maybeSingle();

    final min = (cheapest?['price_amount'] as num?) ?? 0;
    final max = (dearest?['price_amount'] as num?) ?? 100000;
    return (
      min: (min / 1000).floor() * 1000,
      max: ((max / 1000).ceil() * 1000).clamp(1000, double.infinity),
    );
  }

  // ---------------------------------------------------------------------------
  // Listings
  // ---------------------------------------------------------------------------

  /// The main search. Mirrors the web app's `getProperties` exactly, so both
  /// clients return the same results for the same filters.
  Future<List<Property>> fetchProperties({
    PropertyFilters filters = const PropertyFilters(),
    int page = 1,
    int perPage = 12,
  }) async {
    var query = _client.from('properties').select(_listSelect).eq('status', 'published');

    final text = filters.query?.trim();
    if (text != null && text.isNotEmpty) {
      // websearch handles quoted phrases and OR, and never throws on user input.
      query = query.textSearch('search_vector', text, config: 'english', type: TextSearchType.websearch);
    }

    if (filters.typeSlug != null) {
      final type = await _client
          .from('property_types')
          .select('id')
          .eq('slug', filters.typeSlug!)
          .maybeSingle();
      // An unknown slug must return nothing rather than everything.
      if (type == null) return const [];
      query = query.eq('property_type_id', type['id'] as String);
    }

    if (filters.locationSlug != null) {
      final location = await _client
          .from('locations')
          .select('id')
          .eq('slug', filters.locationSlug!)
          .maybeSingle();
      if (location == null) return const [];
      query = query.eq('location_id', location['id'] as String);
    }

    if (filters.minPrice != null) query = query.gte('price_amount', filters.minPrice!);
    if (filters.maxPrice != null) query = query.lte('price_amount', filters.maxPrice!);
    if (filters.bedrooms != null) query = query.gte('bedrooms', filters.bedrooms!);
    if (filters.furnished) query = query.eq('is_furnished', true);
    if (filters.premium) query = query.eq('is_premium', true);

    if (filters.amenitySlugs.isNotEmpty) {
      final ids = await _amenityMatchedPropertyIds(filters.amenitySlugs);
      if (ids.isEmpty) return const [];
      query = query.inFilter('id', ids);
    }

    final from = (page - 1) * perPage;
    final rows = await switch (filters.sort) {
      PropertySort.priceAsc => query.order('price_amount', ascending: true),
      PropertySort.priceDesc => query.order('price_amount', ascending: false),
      PropertySort.bedroomsDesc => query.order('bedrooms', ascending: false),
      PropertySort.popular => query.order('view_count', ascending: false),
      PropertySort.newest => query.order('published_at', ascending: false),
    }.range(from, from + perPage - 1);

    final favorites = await fetchFavoriteIds();
    return rows
        .map<Property>((r) =>
            Property.fromMap(r, isFavorited: favorites.contains(r['id'] as String)))
        .toList();
  }

  /// Properties carrying *every* requested amenity.
  Future<List<String>> _amenityMatchedPropertyIds(List<String> slugs) async {
    final amenityRows =
        await _client.from('amenities').select('id').inFilter('slug', slugs);
    final amenityIds = amenityRows.map<String>((r) => r['id'] as String).toList();
    if (amenityIds.length != slugs.length) return const [];

    final matches = await _client
        .from('property_amenities')
        .select('property_id, amenity_id')
        .inFilter('amenity_id', amenityIds);

    final counts = <String, int>{};
    for (final row in matches) {
      final id = row['property_id'] as String;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    return counts.entries
        .where((e) => e.value >= amenityIds.length)
        .map((e) => e.key)
        .toList();
  }

  Future<Property?> fetchPropertyBySlug(String slug) async {
    final row = await _client
        .from('properties')
        .select('$_listSelect, property_amenities ( amenities ( id, slug, name ) )')
        .eq('slug', slug)
        .maybeSingle();

    if (row == null) return null;

    // The owner comes from the public_profiles view, which omits phone and
    // email. PostgREST cannot embed a view via a foreign key, so this is a
    // separate primary-key lookup.
    Map<String, dynamic>? owner;
    try {
      owner = await _client
          .from('public_profiles')
          .select('id, full_name, avatar_url, is_verified')
          .eq('id', row['owner_id'] as String)
          .maybeSingle();
    } catch (_) {
      owner = null;
    }

    final favorites = await fetchFavoriteIds();
    return Property.fromMap(
      {...row, 'owner': owner},
      isFavorited: favorites.contains(row['id'] as String),
    );
  }

  Future<List<Property>> fetchSimilar(Property property, {int limit = 4}) async {
    final rows = await _client
        .from('properties')
        .select(_listSelect)
        .eq('status', 'published')
        .neq('id', property.id)
        .or('property_type_id.eq.${property.propertyType?.id ?? ''},'
            'location_id.eq.${property.location?.id ?? ''}')
        .order('published_at', ascending: false)
        .limit(limit);

    return rows.map<Property>((r) => Property.fromMap(r)).toList();
  }

  /// Analytics should never be able to break a page.
  Future<void> recordView(String propertyId) async {
    try {
      await _client.rpc('increment_property_views', params: {'p_property_id': propertyId});
    } catch (_) {
      // Ignored on purpose.
    }
  }

  // ---------------------------------------------------------------------------
  // Favourites — RLS pins every row to the signed-in user
  // ---------------------------------------------------------------------------

  Future<Set<String>> fetchFavoriteIds() async {
    final user = currentUser;
    if (user == null) return <String>{};
    try {
      final rows =
          await _client.from('favorites').select('property_id').eq('user_id', user.id);
      return rows.map<String>((r) => r['property_id'] as String).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<List<Property>> fetchFavorites() async {
    final user = currentUser;
    if (user == null) return const [];

    final rows = await _client
        .from('favorites')
        .select('created_at, property:properties ( $_listSelect )')
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    return rows
        .map((r) => r['property'])
        .whereType<Map<String, dynamic>>()
        .map<Property>((p) => Property.fromMap(p, isFavorited: true))
        .toList();
  }

  /// Returns the new saved state. Throws [NotSignedInException] when there is
  /// no session, so the UI can prompt for sign-in.
  Future<bool> toggleFavorite(String propertyId) async {
    final user = currentUser;
    if (user == null) throw const NotSignedInException();

    final existing = await _client
        .from('favorites')
        .select('property_id')
        .eq('user_id', user.id)
        .eq('property_id', propertyId)
        .maybeSingle();

    if (existing != null) {
      await _client
          .from('favorites')
          .delete()
          .eq('user_id', user.id)
          .eq('property_id', propertyId);
      return false;
    }

    await _client.from('favorites').insert({
      'user_id': user.id,
      'property_id': propertyId,
    });
    return true;
  }

  // ---------------------------------------------------------------------------
  // Inquiries — guests may insert, but nobody but the owner and sender can read
  // ---------------------------------------------------------------------------

  Future<void> sendInquiry({
    required String propertyId,
    required String name,
    required String message,
    String? email,
    String? phone,
  }) async {
    await _client.from('inquiries').insert({
      'property_id': propertyId,
      'sender_id': currentUser?.id,
      'name': name,
      'message': message,
      'email': (email?.trim().isEmpty ?? true) ? null : email!.trim(),
      'phone': (phone?.trim().isEmpty ?? true) ? null : phone!.trim(),
    });
  }

  Future<List<Inquiry>> fetchInquiriesForOwner() async {
    final rows = await _client
        .from('inquiries')
        .select('*, property:properties ( id, title, slug )')
        .order('created_at', ascending: false);
    return rows.map<Inquiry>((r) => Inquiry.fromMap(r)).toList();
  }

  Future<void> updateInquiryStatus(String inquiryId, String status) async {
    await _client.from('inquiries').update({'status': status}).eq('id', inquiryId);
  }

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  Future<Profile?> fetchProfile() async {
    final user = currentUser;
    if (user == null) return null;
    final row =
        await _client.from('profiles').select().eq('id', user.id).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }

  Future<void> updateProfile({
    required String fullName,
    String? phone,
    String? bio,
    String? role,
  }) async {
    final user = currentUser;
    if (user == null) throw const NotSignedInException();

    await _client.from('profiles').update({
      'full_name': fullName,
      'phone': (phone?.trim().isEmpty ?? true) ? null : phone!.trim(),
      'bio': (bio?.trim().isEmpty ?? true) ? null : bio!.trim(),
      if (role != null) 'role': role,
    }).eq('id', user.id);
  }

  // ---------------------------------------------------------------------------
  // Landlord listings
  // ---------------------------------------------------------------------------

  Future<List<Property>> fetchMyProperties() async {
    final user = currentUser;
    if (user == null) return const [];
    final rows = await _client
        .from('properties')
        .select(_listSelect)
        .eq('owner_id', user.id)
        .order('created_at', ascending: false);
    return rows.map<Property>((r) => Property.fromMap(r)).toList();
  }

  Future<void> setPropertyStatus(String propertyId, String status) async {
    final user = currentUser;
    if (user == null) throw const NotSignedInException();
    await _client
        .from('properties')
        .update({'status': status})
        .eq('id', propertyId)
        .eq('owner_id', user.id);
  }

  Future<void> deleteProperty(String propertyId) async {
    final user = currentUser;
    if (user == null) throw const NotSignedInException();
    await _client
        .from('properties')
        .delete()
        .eq('id', propertyId)
        .eq('owner_id', user.id);
  }

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  Future<AuthResponse> signIn({required String email, required String password}) =>
      _client.auth.signInWithPassword(email: email.trim(), password: password);

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    String? phone,
    String role = 'seeker',
  }) =>
      _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          'full_name': fullName.trim(),
          if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
          'role': role,
        },
      );

  Future<void> signOut() => _client.auth.signOut();

  Future<void> resetPassword(String email) =>
      _client.auth.resetPasswordForEmail(email.trim());
}

class NotSignedInException implements Exception {
  const NotSignedInException();
  @override
  String toString() => 'Sign in to continue.';
}

/// Turns a Supabase error into something worth showing a person.
String describeError(Object error) {
  if (error is NotSignedInException) return 'Sign in to continue.';

  if (error is AuthException) {
    final message = error.message.toLowerCase();
    if (message.contains('invalid login credentials')) {
      return 'That email and password do not match.';
    }
    if (message.contains('email not confirmed')) {
      return 'Please confirm your email first — check your inbox for the link.';
    }
    if (message.contains('already registered')) {
      return 'An account with that email already exists. Try signing in.';
    }
    if (message.contains('rate limit') || message.contains('too many')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return error.message;
  }

  if (error is PostgrestException) {
    // A row-level-security refusal is a permission problem, not a bug.
    if (error.code == '42501' || error.message.toLowerCase().contains('row-level')) {
      return 'You do not have permission to do that.';
    }
    return error.message;
  }

  return 'Something went wrong. Please try again.';
}
