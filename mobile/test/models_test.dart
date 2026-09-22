import 'package:flutter_test/flutter_test.dart';
import 'package:kheja_link/models/models.dart';

/// Pure model logic for the 0012 features. No network needed.
void main() {
  Property property({String availability = 'available', DateTime? from, String status = 'published'}) =>
      Property.fromMap({
        'id': 'p1',
        'owner_id': 'o1',
        'title': 'Modern One Bedroom',
        'slug': 'modern-one-bedroom',
        'price_amount': 18000,
        'status': status,
        'availability': availability,
        'available_from': from?.toIso8601String().substring(0, 10),
      });

  group('availability', () {
    test('a free home has no label and can be requested', () {
      final p = property();
      expect(p.availabilityLabel, isNull);
      expect(p.isRequestable, isTrue);
    });

    test('an occupied home reads as occupied and cannot be requested', () {
      final p = property(availability: 'occupied');
      expect(p.availabilityLabel, 'Currently occupied');
      expect(p.isRequestable, isFalse);
    });

    test('a vacancy date reads as "Available from"', () {
      final p = property(availability: 'notice_given', from: DateTime(DateTime.now().year, 10, 15));
      expect(p.availabilityLabel, 'Available from 15 Oct');
      expect(p.isComingAvailable, isTrue);
      expect(p.isRequestable, isFalse);
    });

    test('a draft is never requestable', () {
      expect(property(status: 'draft').isRequestable, isFalse);
    });

    test('rows from before 0012 default to available', () {
      final p = Property.fromMap({
        'id': 'p', 'owner_id': 'o', 'title': 'Old listing', 'slug': 'old', 'price_amount': 5000,
      });
      expect(p.availability, 'available');
    });
  });

  group('business settings', () {
    test('defaults are the launch policy', () {
      const s = BusinessSettings();
      expect(s.huntingFee, 500);
      expect(s.listingIsFree, isTrue);
      expect(s.listingOfferEndsOn, isNull);
      expect(s.huntingFeeLabel, 'KSh 500');
    });

    test('settings from the database override the defaults', () {
      final s = BusinessSettings.fromMap({
        'hunting_fee': '750',
        'landlord_listing_fee': '200',
        'hunting_fee_unlocks_contacts': 'false',
        'landlord_listing_fee_offer_ends_on': '2026-12-31',
      });
      expect(s.huntingFee, 750);
      expect(s.listingIsFree, isFalse);
      expect(s.huntingUnlocksContacts, isFalse);
      expect(s.listingOfferEndsOn, DateTime(2026, 12, 31));
    });

    test('blank or junk values fall back safely', () {
      final s = BusinessSettings.fromMap({'hunting_fee': 'abc', 'landlord_listing_fee_offer_ends_on': ''});
      expect(s.huntingFee, 500);
      expect(s.listingOfferEndsOn, isNull);
    });

    test('the cache round-trips', () {
      final s = BusinessSettings.fromMap({'hunting_fee': '600'});
      expect(BusinessSettings.fromMap(s.toCache()).huntingFee, 600);
    });
  });

  group('house hunting service', () {
    test('only paid states count as active', () {
      expect(const HuntingService(status: 'service_active').isActive, isTrue);
      expect(const HuntingService(status: 'matched').isActive, isTrue);
      expect(const HuntingService(status: 'payment_pending').isActive, isFalse);
      expect(HuntingService.none.isActive, isFalse);
    });
  });

  group('requests', () {
    Tenancy t(String status) =>
        Tenancy.fromMap({'id': 't', 'property_id': 'p', 'tenant_id': 'u', 'status': status});

    test('open requests block a second one; closed ones do not', () {
      for (final s in ['booked', 'viewed', 'accepted', 'checked_in']) {
        expect(t(s).isActive, isTrue, reason: s);
      }
      for (final s in ['declined', 'cancelled', 'moved_out']) {
        expect(t(s).isActive, isFalse, reason: s);
      }
    });

    test('a tenant can withdraw until they move in', () {
      expect(t('booked').canWithdraw, isTrue);
      expect(t('accepted').canWithdraw, isTrue);
      expect(t('checked_in').canWithdraw, isFalse);
    });

    test('statuses read in plain words', () {
      expect(t('booked').statusLabel, 'Pending');
      expect(t('declined').statusLabel, 'Declined');
    });
  });

  group('alerts', () {
    test('a standing search summarises itself', () {
      final i = PropertyInterest.fromMap({
        'id': 'i',
        'bedrooms': 1,
        'max_price': 20000,
        'property_type': {'name': 'Apartment'},
        'location': {'name': 'Makutano'},
      });
      expect(i.isForProperty, isFalse);
      expect(i.summary, '1-bedroom Apartment, in Makutano, up to KSh 20,000');
    });
  });

  group('partners', () {
    test('MoveMate ships its logo with the app', () {
      final p = Partner.fromMap({
        'id': 'x', 'category': 'movers', 'slug': 'movemate-kenya', 'name': 'MoveMate Kenya',
      });
      expect(p.bundledLogoAsset, 'assets/branding/movemate-kenya.jpeg');
    });
  });
}
