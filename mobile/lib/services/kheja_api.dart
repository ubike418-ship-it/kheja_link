import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/models.dart';
import 'network.dart';

/// Every read and write the app performs.
///
/// Authorization is not implemented here — it lives in Row Level Security on
/// the database, exactly as it does for the web app. These methods simply ask
/// for what the user should be able to see; Postgres decides what comes back.
class KhejaApi {
  KhejaApi(this._client);

  final SupabaseClient _client;

  /// Explicit, because contact_phone, contact_whatsapp, latitude and longitude
  /// are revoked from the API roles — they sit behind the KSh 150 unlock and
  /// come back only through get_property_contact(). '*' would be denied.
  static const _propertyColumns =
      'id, owner_id, title, slug, description, property_type_id, location_id, address_line, price_amount, price_currency, price_period, deposit_months, bedrooms, bathrooms, size_sqft, is_premium, is_furnished, status, available_from, view_count, published_at, created_at, updated_at, like_count, house_rules, building_name, floor_number, service_charge, water_billing, water_notes, electricity_billing, parking_spaces, pets_allowed, min_lease_months, notice_months, nearby, security_details, internet_ready, is_gated, has_balcony';

  static const _listSelect = '''
    $_propertyColumns,
    property_type:property_types ( id, slug, name, description ),
    location:locations ( id, slug, name, area, county, latitude, longitude ),
    images:property_images ( id, public_url, alt_text, is_cover, sort_order ),
    videos:property_videos ( id, public_url, thumbnail_url, caption, duration_seconds, sort_order )
  ''';

  User? get currentUser => _client.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  // ---------------------------------------------------------------------------
  // Reference data
  // ---------------------------------------------------------------------------

  Future<List<PropertyType>> fetchPropertyTypes() async {
    final rows = await KhejaNetwork.run(
        () => _client.from('property_types').select().order('sort_order'));
    return rows.map<PropertyType>((r) => PropertyType.fromMap(r)).toList();
  }

  Future<List<KhejaLocation>> fetchLocations() async {
    final rows = await KhejaNetwork.run(
        () => _client.from('locations').select().order('name'));
    return rows.map<KhejaLocation>((r) => KhejaLocation.fromMap(r)).toList();
  }

  Future<List<Amenity>> fetchAmenities() async {
    final rows = await KhejaNetwork.run(
        () => _client.from('amenities').select().order('sort_order'));
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
    final sorted = switch (filters.sort) {
      PropertySort.priceAsc => query.order('price_amount', ascending: true),
      PropertySort.priceDesc => query.order('price_amount', ascending: false),
      PropertySort.bedroomsDesc => query.order('bedrooms', ascending: false),
      PropertySort.popular => query.order('view_count', ascending: false),
      PropertySort.newest => query.order('published_at', ascending: false),
    };
    final rows =
        await KhejaNetwork.run(() => sorted.range(from, from + perPage - 1));

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
    final row = await KhejaNetwork.run(() => _client
        .from('properties')
        .select('$_listSelect, property_amenities ( amenities ( id, slug, name ) )')
        .eq('slug', slug)
        .maybeSingle());

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

  /// Resolves a property id to its slug, for opening a listing from a
  /// notification (which carries the id, not the slug).
  Future<String?> fetchPropertySlug(String propertyId) async {
    try {
      final row = await _client
          .from('properties')
          .select('slug')
          .eq('id', propertyId)
          .maybeSingle();
      return row?['slug'] as String?;
    } catch (_) {
      return null;
    }
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
  // Contact unlock — the KSh 150 purchase
  //
  // The phone number, WhatsApp number and exact map position are revoked from
  // the API roles entirely. They are not hidden by the UI; the database will
  // not send them. get_property_contact() returns them only to the owner or to
  // someone with a paid unlock.
  // ---------------------------------------------------------------------------

  Future<PropertyContact> fetchPropertyContact(String propertyId) async {
    try {
      final rows = await _client
          .rpc('get_property_contact', params: {'p_property_id': propertyId});
      if (rows is List && rows.isNotEmpty) {
        return PropertyContact.fromMap(Map<String, dynamic>.from(rows.first));
      }
      return PropertyContact.locked;
    } catch (_) {
      return PropertyContact.locked;
    }
  }

  Future<bool> hasUnlocked(String propertyId) async {
    if (!isSignedIn) return false;
    try {
      final row = await _client
          .from('contact_unlocks')
          .select('id')
          .eq('property_id', propertyId)
          .eq('status', 'paid')
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  /// Starts an unlock and returns its reference. The caller then sends the user
  /// to the payment page; the webhook flips the row to paid.
  Future<String> startContactUnlock(String propertyId) async {
    final user = currentUser;
    if (user == null) throw const NotSignedInException();

    final reference =
        'kl_${DateTime.now().millisecondsSinceEpoch}_${propertyId.substring(0, 8)}';

    await _client.from('contact_unlocks').insert({
      'user_id': user.id,
      'property_id': propertyId,
      'amount': kUnlockAmount,
      'currency': kUnlockCurrency,
      'status': 'pending',
      'provider': 'paystack',
      'provider_ref': reference,
    });

    return reference;
  }

  /// The listings this person has already paid to unlock.
  Future<Set<String>> fetchUnlockedPropertyIds() async {
    if (!isSignedIn) return <String>{};
    try {
      final rows = await _client
          .from('contact_unlocks')
          .select('property_id')
          .eq('status', 'paid');
      return rows.map<String>((r) => r['property_id'] as String).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  // ---------------------------------------------------------------------------
  // Notifications — in-app only
  // ---------------------------------------------------------------------------

  Future<List<KhejaNotification>> fetchNotifications({int limit = 60}) async {
    if (!isSignedIn) return const [];
    final rows = await _client
        .from('notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map<KhejaNotification>((r) => KhejaNotification.fromMap(r)).toList();
  }

  Future<int> fetchUnreadNotificationCount() async {
    if (!isSignedIn) return 0;
    try {
      final rows =
          await _client.from('notifications').select('id').eq('is_read', false);
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> markNotificationRead(String id) async {
    await _client.from('notifications').update({'is_read': true}).eq('id', id);
  }

  Future<void> markAllNotificationsRead() async {
    final user = currentUser;
    if (user == null) return;
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', user.id)
        .eq('is_read', false);
  }

  Future<void> deleteNotification(String id) async {
    await _client.from('notifications').delete().eq('id', id);
  }

  // ---------------------------------------------------------------------------
  // Partners — movers, internet, cleaning
  // ---------------------------------------------------------------------------

  Future<List<Partner>> fetchPartners() async {
    final rows = await _client
        .from('partners')
        .select()
        .eq('is_active', true)
        .order('category')
        .order('sort_order');
    return rows.map<Partner>((r) => Partner.fromMap(r)).toList();
  }

  // ---------------------------------------------------------------------------
  // Tenancies — booked, checked in, moved out
  // ---------------------------------------------------------------------------

  Future<List<Tenancy>> fetchMyTenancies() async {
    final user = currentUser;
    if (user == null) return const [];
    final rows = await _client
        .from('tenancies')
        .select('*, property:properties ( id, title, slug )')
        .eq('tenant_id', user.id)
        .order('created_at', ascending: false);
    return rows.map<Tenancy>((r) => Tenancy.fromMap(r)).toList();
  }

  /// Every tenancy across the signed-in landlord's listings. RLS keeps this to
  /// properties they own.
  Future<List<Tenancy>> fetchTenanciesForOwner() async {
    if (!isSignedIn) return const [];
    final rows = await _client
        .from('tenancies')
        .select('*, property:properties ( id, title, slug )')
        .order('created_at', ascending: false);
    return rows.map<Tenancy>((r) => Tenancy.fromMap(r)).toList();
  }

  Future<Tenancy?> fetchMyTenancyFor(String propertyId) async {
    final user = currentUser;
    if (user == null) return null;
    final row = await _client
        .from('tenancies')
        .select('*, property:properties ( id, title, slug )')
        .eq('property_id', propertyId)
        .eq('tenant_id', user.id)
        .inFilter('status', ['booked', 'checked_in'])
        .maybeSingle();
    return row == null ? null : Tenancy.fromMap(row);
  }

  Future<void> bookProperty(String propertyId, {String? note}) async {
    final user = currentUser;
    if (user == null) throw const NotSignedInException();
    await _client.from('tenancies').insert({
      'property_id': propertyId,
      'tenant_id': user.id,
      'status': 'booked',
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  Future<void> setTenancyStatus(String tenancyId, String status) async {
    final patch = <String, dynamic>{'status': status};
    if (status == 'checked_in') {
      patch['checked_in_at'] = DateTime.now().toUtc().toIso8601String();
    }
    if (status == 'moved_out') {
      patch['moved_out_at'] = DateTime.now().toUtc().toIso8601String();
    }
    await _client.from('tenancies').update(patch).eq('id', tenancyId);
  }

  // ---------------------------------------------------------------------------
  // Search suggestions
  // ---------------------------------------------------------------------------

  /// Areas, house types and listing titles matching what has been typed so far.
  /// Never throws — an empty list simply means no hints.
  Future<List<SearchSuggestion>> fetchSearchSuggestions(String term) async {
    final text = term.trim();
    if (text.length < 2) return const [];

    try {
      final results = await Future.wait([
        _client
            .from('locations')
            .select('name, slug')
            .ilike('name', '%$text%')
            .limit(4),
        _client
            .from('property_types')
            .select('name, slug')
            .ilike('name', '%$text%')
            .limit(4),
        _client
            .from('properties')
            .select('title, slug')
            .eq('status', 'published')
            .ilike('title', '%$text%')
            .limit(5),
      ]);

      final out = <SearchSuggestion>[];

      for (final row in results[0]) {
        out.add(SearchSuggestion(
          label: row['name'] as String,
          kind: SuggestionKind.location,
          value: row['slug'] as String,
        ));
      }
      for (final row in results[1]) {
        out.add(SearchSuggestion(
          label: row['name'] as String,
          kind: SuggestionKind.type,
          value: row['slug'] as String,
        ));
      }
      for (final row in results[2]) {
        out.add(SearchSuggestion(
          label: row['title'] as String,
          kind: SuggestionKind.property,
          value: row['slug'] as String,
        ));
      }

      return out;
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // Landlord: creating and editing listings from the app
  // ---------------------------------------------------------------------------

  static const _photoBucket = 'property-images';
  static const _videoBucket = 'property-videos';

  /// 60 MB — matches the bucket limit, so a too-large file is refused here with
  /// a clear message instead of failing halfway through an upload.
  static const maxVideoBytes = 60 * 1024 * 1024;
  static const maxPhotoBytes = 5 * 1024 * 1024;

  /// Uploads a photo into the landlord's own folder and returns its URL.
  /// Storage policy only allows writes under `<their user id>/`, so a user
  /// cannot place a file in someone else's folder.
  Future<String> uploadPropertyPhoto(File file) async {
    final user = currentUser;
    if (user == null) throw const NotSignedInException();

    final size = await file.length();
    if (size > maxPhotoBytes) {
      throw const UploadTooLargeException('Photos must be 5 MB or smaller.');
    }

    final ext = _extension(file.path, fallback: 'jpg');
    final path = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await KhejaNetwork.run(
      () => _client.storage.from(_photoBucket).upload(
            path,
            file,
            fileOptions: FileOptions(
              cacheControl: '31536000',
              contentType: _mimeFor(ext, isVideo: false),
            ),
          ),
      // Uploads are slow on mobile data; give them room.
      timeout: const Duration(minutes: 2),
      attempts: 2,
    );

    return _client.storage.from(_photoBucket).getPublicUrl(path);
  }

  /// Uploads a video tour and returns its URL.
  Future<String> uploadPropertyVideo(File file) async {
    final user = currentUser;
    if (user == null) throw const NotSignedInException();

    final size = await file.length();
    if (size > maxVideoBytes) {
      throw UploadTooLargeException(
        'That video is ${(size / 1024 / 1024).toStringAsFixed(0)} MB. Keep tours '
        'under 60 MB — a minute or two of walking through the house is plenty.',
      );
    }

    final ext = _extension(file.path, fallback: 'mp4');
    final path = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _client.storage.from(_videoBucket).upload(
          path,
          file,
          fileOptions: FileOptions(
            cacheControl: '31536000',
            contentType: _mimeFor(ext, isVideo: true),
          ),
        );

    return _client.storage.from(_videoBucket).getPublicUrl(path);
  }

  /// Creates a listing and everything attached to it. Returns the new id.
  Future<String> createProperty(ListingDraft draft) async {
    final user = currentUser;
    if (user == null) throw const NotSignedInException();

    final slugBase = draft.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final slug =
        '${slugBase.isEmpty ? 'listing' : slugBase}-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';

    final row = await KhejaNetwork.run(() => _client
        .from('properties')
        .insert({...draft.toRow(), 'owner_id': user.id, 'slug': slug})
        .select('id')
        .single());

    final id = row['id'] as String;
    await _syncListingMedia(id, draft);
    return id;
  }

  Future<void> updateProperty(String propertyId, ListingDraft draft) async {
    final user = currentUser;
    if (user == null) throw const NotSignedInException();

    await KhejaNetwork.run(() => _client
        .from('properties')
        .update(draft.toRow())
        .eq('id', propertyId)
        .eq('owner_id', user.id));

    await _syncListingMedia(propertyId, draft);
  }

  /// Replaces the photo, video and amenity sets so their order and cover stay
  /// exactly as the landlord arranged them.
  Future<void> _syncListingMedia(String propertyId, ListingDraft draft) async {
    await _client.from('property_images').delete().eq('property_id', propertyId);
    if (draft.photoUrls.isNotEmpty) {
      await _client.from('property_images').insert([
        for (var i = 0; i < draft.photoUrls.length; i++)
          {
            'property_id': propertyId,
            'public_url': draft.photoUrls[i],
            'storage_path': _storagePath(draft.photoUrls[i], _photoBucket),
            'is_cover': i == 0,
            'sort_order': i,
            'alt_text': draft.title,
          },
      ]);
    }

    await _client.from('property_videos').delete().eq('property_id', propertyId);
    if (draft.videoUrls.isNotEmpty) {
      await _client.from('property_videos').insert([
        for (var i = 0; i < draft.videoUrls.length; i++)
          {
            'property_id': propertyId,
            'public_url': draft.videoUrls[i],
            'storage_path': _storagePath(draft.videoUrls[i], _videoBucket),
            'sort_order': i,
          },
      ]);
    }

    await _client.from('property_amenities').delete().eq('property_id', propertyId);
    if (draft.amenityIds.isNotEmpty) {
      await _client.from('property_amenities').insert([
        for (final amenityId in draft.amenityIds)
          {'property_id': propertyId, 'amenity_id': amenityId},
      ]);
    }
  }

  /// Loads one of the landlord's own listings, including the private fields
  /// that only the owner and paying tenants may see, ready for editing.
  Future<ListingDraft?> fetchListingForEdit(String propertyId) async {
    final user = currentUser;
    if (user == null) return null;

    final row = await KhejaNetwork.run(() => _client
        .from('properties')
        .select('$_listSelect, property_amenities ( amenity_id )')
        .eq('id', propertyId)
        .eq('owner_id', user.id)
        .maybeSingle());
    if (row == null) return null;

    final property = Property.fromMap(row);

    Map<String, dynamic>? private;
    try {
      final rows = await _client
          .rpc('get_my_property_private', params: {'p_property_id': propertyId});
      if (rows is List && rows.isNotEmpty) {
        private = Map<String, dynamic>.from(rows.first);
      }
    } catch (_) {
      private = null;
    }

    final amenityIds = (row['property_amenities'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((a) => a['amenity_id'] as String)
        .toList();

    return ListingDraft.fromProperty(property, private: private, amenityIds: amenityIds);
  }

  static String _extension(String path, {required String fallback}) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return fallback;
    final ext = path.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{2,5}$').hasMatch(ext) ? ext : fallback;
  }

  static String _mimeFor(String ext, {required bool isVideo}) {
    if (isVideo) {
      return switch (ext) {
        'mov' => 'video/quicktime',
        '3gp' => 'video/3gpp',
        'webm' => 'video/webm',
        _ => 'video/mp4',
      };
    }
    return switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }

  /// Recovers the bucket-relative path from a public URL, if it is one of ours.
  static String? _storagePath(String url, String bucket) {
    final marker = '/storage/v1/object/public/$bucket/';
    final i = url.indexOf(marker);
    return i == -1 ? null : Uri.decodeComponent(url.substring(i + marker.length));
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
  if (error is UploadTooLargeException) return error.message;

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

  // A stalled or dropped mobile connection is the single most common failure
  // in the field, and it deserves its own words rather than a generic error.
  if (KhejaNetwork.isConnectionError(error)) {
    return 'No connection. Check your mobile data or WiFi and try again.';
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

class UploadTooLargeException implements Exception {
  const UploadTooLargeException(this.message);
  final String message;
  @override
  String toString() => message;
}
