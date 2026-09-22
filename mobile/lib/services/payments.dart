import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';
import '../main.dart';
import '../models/models.dart';
import 'kheja_api.dart';

enum UnlockResultKind { unlocked, checkout, failed }

class UnlockResult {
  const UnlockResult._(this.kind, {this.checkoutUrl, this.message});

  final UnlockResultKind kind;
  final String? checkoutUrl;
  final String? message;

  const UnlockResult.unlocked() : this._(UnlockResultKind.unlocked);
  const UnlockResult.checkout(String url)
      : this._(UnlockResultKind.checkout, checkoutUrl: url);
  const UnlockResult.failed(String message)
      : this._(UnlockResultKind.failed, message: message);
}

enum HuntingPaymentKind { active, checkout, failed }

class HuntingPaymentResult {
  const HuntingPaymentResult._(this.kind, {this.checkoutUrl, this.message});

  final HuntingPaymentKind kind;
  final String? checkoutUrl;
  final String? message;

  const HuntingPaymentResult.active([String? message])
      : this._(HuntingPaymentKind.active, message: message);
  const HuntingPaymentResult.checkout(String url)
      : this._(HuntingPaymentKind.checkout, checkoutUrl: url);
  const HuntingPaymentResult.failed(String message)
      : this._(HuntingPaymentKind.failed, message: message);
}

/// Starting a KSh 150 contact unlock.
///
/// The app writes a pending row itself, then asks the Kheja_Link server to turn
/// that reference into a Paystack checkout URL. The secret key never leaves the
/// server, and only the Paystack webhook can mark an unlock paid — the app
/// cannot grant itself access no matter what it sends.
class KhejaPayments {
  const KhejaPayments._();

  /// Starts the house hunting fee.
  ///
  /// The database creates the pending payment and prices it from
  /// app_settings; the server turns that into a Paystack checkout. Nothing
  /// here can mark the fee paid — only the verified Paystack webhook can, so
  /// the app re-reads the service status when the tenant comes back.
  static Future<HuntingPaymentResult> startHuntingFee() async {
    final email = khejaApi.currentUser?.email;
    if (email == null || email.isEmpty) {
      return const HuntingPaymentResult.failed(
        'Your account has no email address, which the payment page needs.',
      );
    }

    final ({String reference, num amount, String currency})? started;
    try {
      started = await khejaApi.startHuntingPayment();
    } catch (error) {
      return HuntingPaymentResult.failed(describeError(error));
    }

    // The database says there is nothing to pay: already active.
    if (started == null) {
      return const HuntingPaymentResult.active('Your House Hunting service is already active.');
    }

    try {
      final response = await http
          .post(
            Uri.parse('${SupabaseConfig.siteUrl}/api/payments/initialize'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'reference': started.reference, 'email': email}),
          )
          .timeout(const Duration(seconds: 25));

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode != 200) {
        return HuntingPaymentResult.failed(
          (body['error'] as String?) ?? 'Could not start the payment.',
        );
      }

      if (body['mode'] == 'already_paid' || (body['mode'] == 'demo' && body['paid'] == true)) {
        return HuntingPaymentResult.active(body['message'] as String?);
      }

      final url = body['checkoutUrl'] as String?;
      if (url == null || url.isEmpty) {
        return const HuntingPaymentResult.failed('The payment page could not be opened.');
      }
      return HuntingPaymentResult.checkout(url);
    } catch (_) {
      return const HuntingPaymentResult.failed(
        'Could not reach the payment service. Check your connection and try again.',
      );
    }
  }

  static Future<UnlockResult> startUnlock(Property property) async {
    // Already paid for? Nothing to do.
    if (await khejaApi.hasUnlocked(property.id)) {
      return const UnlockResult.unlocked();
    }

    final email = khejaApi.currentUser?.email;
    if (email == null || email.isEmpty) {
      return const UnlockResult.failed(
        'Your account has no email address, which the payment page needs.',
      );
    }

    final String reference;
    try {
      reference = await khejaApi.startContactUnlock(property.id);
    } catch (error) {
      return UnlockResult.failed(
        error.toString().contains('duplicate')
            ? 'You already have a payment in progress for this home.'
            : 'Could not start the payment. Please try again.',
      );
    }

    try {
      final response = await http
          .post(
            Uri.parse('${SupabaseConfig.siteUrl}/api/payments/initialize'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'reference': reference,
              'email': email,
              'propertyTitle': property.title,
            }),
          )
          .timeout(const Duration(seconds: 25));

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode != 200) {
        return UnlockResult.failed(
          (body['error'] as String?) ?? 'Could not start the payment.',
        );
      }

      // Demo mode: the server confirmed it without charging anyone.
      if (body['mode'] == 'demo') {
        return body['unlocked'] == true
            ? const UnlockResult.unlocked()
            : const UnlockResult.failed('Could not complete the unlock.');
      }

      final url = body['checkoutUrl'] as String?;
      if (url == null || url.isEmpty) {
        return const UnlockResult.failed('The payment page could not be opened.');
      }
      return UnlockResult.checkout(url);
    } catch (_) {
      return const UnlockResult.failed(
        'Could not reach the payment service. Check your connection and try again.',
      );
    }
  }
}
