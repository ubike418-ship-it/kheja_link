import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';
import '../main.dart';

/// What Kheja_Link's own payment screens need from the server.
///
/// The app never talks to Paystack, and never sees a secret key: it posts to
/// Kheja_Link, which drives Paystack's API and answers with what to show. A
/// payment is only ever marked paid after the server has heard it from
/// Paystack, so nothing here can grant access by lying.
enum ChargeState { pending, needsOtp, success, failed }

class ChargeResult {
  const ChargeResult({
    required this.state,
    this.displayText,
    this.message,
  });

  final ChargeState state;

  /// Paystack's own words for the customer ("approve the prompt on your
  /// phone"), shown inside our screen so instructions always match reality.
  final String? displayText;
  final String? message;

  String get instruction =>
      displayText ??
      message ??
      'Check your phone and enter your M-Pesa PIN to approve the payment.';
}

class KhejaCheckout {
  const KhejaCheckout._();

  static Uri _url(String path) => Uri.parse('${SupabaseConfig.siteUrl}$path');

  static Map<String, String> _headers() {
    final token = khejaApi.accessToken;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static ChargeResult _parse(Map<String, dynamic> body) {
    final status = body['status'] as String?;
    return ChargeResult(
      state: switch (status) {
        'success' => ChargeState.success,
        'send_otp' => ChargeState.needsOtp,
        'failed' => ChargeState.failed,
        _ => ChargeState.pending,
      },
      displayText: body['displayText'] as String?,
      message: body['message'] as String?,
    );
  }

  static ChargeResult _error(Map<String, dynamic>? body, String fallback) => ChargeResult(
        state: ChargeState.failed,
        message: (body?['error'] as String?) ?? fallback,
      );

  /// Charges an M-Pesa number. The amount comes from the pending payment on
  /// the server — it is not sent from here.
  static Future<ChargeResult> payWithMpesa({
    required String reference,
    required String phone,
  }) async {
    try {
      final response = await http
          .post(
            _url('/api/payments/charge'),
            headers: _headers(),
            body: jsonEncode({'reference': reference, 'phone': phone}),
          )
          .timeout(const Duration(seconds: 40));

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        return _error(body, 'Could not start the payment. Please try again.');
      }
      return _parse(body);
    } catch (_) {
      return const ChargeResult(
        state: ChargeState.failed,
        message: 'Could not reach the payment service. Check your connection and try again.',
      );
    }
  }

  /// Where the payment has got to. The server asks Paystack, and records the
  /// payment itself once Paystack confirms it.
  static Future<ChargeResult> status(String reference) async {
    try {
      final response = await http
          .get(_url('/api/payments/status?reference=$reference'), headers: _headers())
          .timeout(const Duration(seconds: 25));

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        return _error(body, 'Could not check the payment.');
      }
      return _parse(body);
    } catch (_) {
      // A dropped request mid-payment is not a failed payment.
      return const ChargeResult(state: ChargeState.pending, message: 'Still checking…');
    }
  }

  /// Paystack's hosted page for this same payment, used only for cards —
  /// so a card number is never typed into Kheja_Link. Null if it cannot be
  /// opened.
  static Future<String?> cardCheckoutUrl(String reference) async {
    final email = khejaApi.currentUser?.email;
    if (email == null || email.isEmpty) return null;
    try {
      final response = await http
          .post(
            _url('/api/payments/initialize'),
            headers: _headers(),
            body: jsonEncode({'reference': reference, 'email': email}),
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['checkoutUrl'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// For providers that send a code instead of prompting the phone.
  static Future<ChargeResult> submitOtp({
    required String reference,
    required String otp,
  }) async {
    try {
      final response = await http
          .post(
            _url('/api/payments/otp'),
            headers: _headers(),
            body: jsonEncode({'reference': reference, 'otp': otp}),
          )
          .timeout(const Duration(seconds: 30));

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode != 200) {
        return _error(body, 'That code was not accepted.');
      }
      return _parse(body);
    } catch (_) {
      return const ChargeResult(
        state: ChargeState.failed,
        message: 'Could not reach the payment service. Please try again.',
      );
    }
  }
}
