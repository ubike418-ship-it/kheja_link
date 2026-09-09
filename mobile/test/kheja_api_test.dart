import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kheja_link/models/models.dart';
import 'package:kheja_link/services/kheja_api.dart';
import 'package:supabase/supabase.dart';

/// Smoke tests for the data layer, run against the real Supabase project.
///
/// They use the anon key and only read public data, so they double as a check
/// that Row Level Security is doing its job: anything a signed-out visitor
/// should not see must come back empty rather than populated.
///
/// Credentials come from the environment so nothing is committed:
///
///   SUPABASE_URL=... SUPABASE_ANON_KEY=... flutter test
///
/// Without them the suite skips rather than fails, so CI stays green offline.
void main() {
  final url = Platform.environment['SUPABASE_URL'] ?? _fromEnvFile('SUPABASE_URL');
  final key =
      Platform.environment['SUPABASE_ANON_KEY'] ?? _fromEnvFile('SUPABASE_ANON_KEY');

  final configured = url != null && key != null;

  late KhejaApi api;

  setUpAll(() {
    if (configured) api = KhejaApi(SupabaseClient(url, key));
  });

  group('reference data', () {
    test('property types are seeded and ordered', () async {
      final types = await api.fetchPropertyTypes();
      expect(types, isNotEmpty);
      expect(types.map((t) => t.slug), contains('apartment'));
      expect(types.map((t) => t.slug), contains('bedsitter'));
    }, skip: configured ? null : 'Supabase credentials not set');

    test('Meru locations are seeded', () async {
      final locations = await api.fetchLocations();
      expect(locations.map((l) => l.name), contains('Makutano'));
      expect(locations.every((l) => l.county.isNotEmpty), isTrue);
    }, skip: configured ? null : 'Supabase credentials not set');

    test('price bounds are sane', () async {
      final bounds = await api.fetchPriceBounds();
      expect(bounds.min, lessThan(bounds.max));
    }, skip: configured ? null : 'Supabase credentials not set');
  });

  group('listings', () {
    test('published listings come back with their joins', () async {
      final properties = await api.fetchProperties();
      expect(properties, isNotEmpty);

      final first = properties.first;
      expect(first.status, 'published');
      expect(first.propertyType, isNotNull, reason: 'type join failed');
      expect(first.location, isNotNull, reason: 'location join failed');
      expect(first.priceAmount, greaterThan(0));
    }, skip: configured ? null : 'Supabase credentials not set');

    test('type filter narrows results', () async {
      final bedsitters = await api.fetchProperties(
        filters: const PropertyFilters(typeSlug: 'bedsitter'),
      );
      expect(bedsitters, isNotEmpty);
      expect(
        bedsitters.every((p) => p.propertyType?.slug == 'bedsitter'),
        isTrue,
      );
    }, skip: configured ? null : 'Supabase credentials not set');

    test('an unknown type slug returns nothing, not everything', () async {
      final results = await api.fetchProperties(
        filters: const PropertyFilters(typeSlug: 'not-a-real-type'),
      );
      expect(results, isEmpty);
    }, skip: configured ? null : 'Supabase credentials not set');

    test('price filter and ascending sort both apply', () async {
      final cheap = await api.fetchProperties(
        filters: const PropertyFilters(maxPrice: 15000, sort: PropertySort.priceAsc),
      );
      expect(cheap, isNotEmpty);
      expect(cheap.every((p) => p.priceAmount <= 15000), isTrue);

      final prices = cheap.map((p) => p.priceAmount).toList();
      final sorted = [...prices]..sort();
      expect(prices, equals(sorted), reason: 'results are not price-ascending');
    }, skip: configured ? null : 'Supabase credentials not set');

    test('full-text search matches on the title', () async {
      final results = await api.fetchProperties(
        filters: const PropertyFilters(query: 'bedsitter'),
      );
      expect(results, isNotEmpty);
    }, skip: configured ? null : 'Supabase credentials not set');

    test('detail lookup returns amenities and the public owner', () async {
      final list = await api.fetchProperties();
      final detail = await api.fetchPropertyBySlug(list.first.slug);

      expect(detail, isNotNull);
      expect(detail!.images, isNotEmpty);
      expect(detail.amenities, isNotEmpty);
      expect(detail.owner, isNotNull);
    }, skip: configured ? null : 'Supabase credentials not set');

    test('an unknown slug returns null rather than throwing', () async {
      expect(await api.fetchPropertyBySlug('nope-does-not-exist'), isNull);
    }, skip: configured ? null : 'Supabase credentials not set');
  });

  group('row level security, as a signed-out visitor', () {
    test('favourites are not readable', () async {
      expect(await api.fetchFavorites(), isEmpty);
      expect(await api.fetchFavoriteIds(), isEmpty);
    }, skip: configured ? null : 'Supabase credentials not set');

    test('inquiries are not readable', () async {
      // Whether this refuses or returns nothing, it must never leak rows.
      List<Inquiry> inquiries;
      try {
        inquiries = await api.fetchInquiriesForOwner();
      } on PostgrestException {
        inquiries = const [];
      }
      expect(inquiries, isEmpty);
    }, skip: configured ? null : 'Supabase credentials not set');

    test('saving a home without a session is refused', () async {
      final list = await api.fetchProperties();
      expect(
        () => api.toggleFavorite(list.first.id),
        throwsA(isA<NotSignedInException>()),
      );
    }, skip: configured ? null : 'Supabase credentials not set');
  });

  marketplaceTests(() => api, configured);

  group('formatting', () {
    test('rent reads the way the design specifies', () {
      expect(formatPrice(45000), 'KSh 45,000');
      expect(formatRent(45000, 'month'), 'KSh 45,000 / month');
    });

    test('size is null-safe', () {
      expect(formatSize(1800), '1,800 sqft');
      expect(formatSize(null), isNull);
      expect(formatSize(0), isNull);
    });
  });
}

/// Falls back to the local .env so `flutter test` works with no extra setup.
String? _fromEnvFile(String key) {
  final file = File('.env');
  if (!file.existsSync()) return null;
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final index = trimmed.indexOf('=');
    if (index == -1) continue;
    if (trimmed.substring(0, index).trim() == key) {
      return trimmed.substring(index + 1).trim();
    }
  }
  return null;
}

/// A second suite for the marketplace features added in the 1.1 release.
/// Same rules: real database, anon key, and the paywall must hold.
void marketplaceTests(KhejaApi Function() apiOf, bool configured) {
  final skip = configured ? null : 'Supabase credentials not set';

  group('partner directory', () {
    test('all three rails are populated', () async {
      final partners = await apiOf().fetchPartners();
      expect(partners, isNotEmpty);

      for (final category in ['movers', 'isp', 'cleaning']) {
        expect(
          partners.where((p) => p.category == category),
          isNotEmpty,
          reason: 'the $category rail is empty',
        );
      }
    }, skip: skip);

    test('our own mover is flagged, and third parties carry no logo', () async {
      final partners = await apiOf().fetchPartners();

      final ours = partners.where((p) => p.isOurs).toList();
      expect(ours, hasLength(1));
      expect(ours.first.name, 'Movement');

      // Reproducing another company's trademark would imply a partnership that
      // does not exist, so those tiles must stay logo-less until agreed.
      final thirdPartyLogos =
          partners.where((p) => !p.isOurs && p.logoUrl != null);
      expect(thirdPartyLogos, isEmpty);
    }, skip: skip);
  });

  group('the KSh 150 paywall', () {
    test('contact details are not readable while locked', () async {
      final list = await apiOf().fetchProperties();
      final contact = await apiOf().fetchPropertyContact(list.first.id);

      expect(contact.unlocked, isFalse);
      expect(contact.phone, isNull);
      expect(contact.whatsapp, isNull);
      expect(contact.latitude, isNull);
      expect(contact.longitude, isNull);
    }, skip: skip);

    test('the protected columns cannot be selected directly', () async {
      // The real guarantee: not that the UI hides them, but that the database
      // refuses to send them at all.
      for (final column in [
        'contact_phone',
        'contact_whatsapp',
        'latitude',
        'longitude',
      ]) {
        await expectLater(
          SupabaseClient(
            Platform.environment['SUPABASE_URL'] ?? _fromEnvFile('SUPABASE_URL')!,
            Platform.environment['SUPABASE_ANON_KEY'] ??
                _fromEnvFile('SUPABASE_ANON_KEY')!,
          ).from('properties').select(column).limit(1),
          throwsA(isA<PostgrestException>()),
          reason: '$column is readable by an anonymous caller',
        );
      }
    }, skip: skip);

    test('an unlock cannot be started without signing in', () async {
      final list = await apiOf().fetchProperties();
      expect(
        () => apiOf().startContactUnlock(list.first.id),
        throwsA(isA<NotSignedInException>()),
      );
    }, skip: skip);
  });

  group('listings', () {
    test('hostels are listed with photos', () async {
      final hostels = await apiOf().fetchProperties(
        filters: const PropertyFilters(typeSlug: 'hostel'),
      );
      expect(hostels, isNotEmpty);
      expect(hostels.every((h) => h.images.isNotEmpty), isTrue);
    }, skip: skip);

    test('every published listing has at least one photo', () async {
      final all = await apiOf().fetchProperties(perPage: 48);
      final missing = all.where((p) => p.images.isEmpty).map((p) => p.title);
      expect(missing, isEmpty, reason: 'listings with no photo: $missing');
    }, skip: skip);

    test('like counts come back on the card', () async {
      final all = await apiOf().fetchProperties();
      expect(all.every((p) => p.likeCount >= 0), isTrue);
    }, skip: skip);
  });

  group('search suggestions', () {
    test('an area is suggested from a partial word', () async {
      final hints = await apiOf().fetchSearchSuggestions('maku');
      expect(hints, isNotEmpty);
      expect(
        hints.any((h) => h.kind == SuggestionKind.location && h.label == 'Makutano'),
        isTrue,
      );
    }, skip: skip);

    test('a house type is suggested', () async {
      final hints = await apiOf().fetchSearchSuggestions('hostel');
      expect(hints.any((h) => h.kind == SuggestionKind.type), isTrue);
    }, skip: skip);

    test('a single character suggests nothing', () async {
      expect(await apiOf().fetchSearchSuggestions('a'), isEmpty);
    }, skip: skip);
  });

  group('notifications', () {
    test('a signed-out visitor sees none', () async {
      expect(await apiOf().fetchNotifications(), isEmpty);
      expect(await apiOf().fetchUnreadNotificationCount(), 0);
    }, skip: skip);
  });
}
