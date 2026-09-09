import 'dart:async';
import 'dart:io';

/// Making the app survive a mobile connection.
///
/// On WiFi almost anything works. On Meru mobile data the same code stalls:
/// a request can hang for minutes with no error, which looks identical to the
/// app being broken. Everything here exists to make slow and flaky behave
/// differently from dead.
class KhejaNetwork {
  const KhejaNetwork._();

  /// Long enough for a bad 3G round trip, short enough that a user is not
  /// staring at a spinner wondering whether the app is finished.
  static const requestTimeout = Duration(seconds: 20);

  /// Runs [action], retrying transient network failures with backoff.
  ///
  /// A timeout or a socket error on mobile data is usually worth one more go;
  /// a Postgres permission error never is, so only connection-shaped failures
  /// are retried.
  static Future<T> run<T>(
    Future<T> Function() action, {
    int attempts = 3,
    Duration timeout = requestTimeout,
  }) async {
    Object? lastError;

    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        return await action().timeout(timeout);
      } on TimeoutException catch (error) {
        lastError = error;
      } on SocketException catch (error) {
        lastError = error;
      } on HttpException catch (error) {
        lastError = error;
      } catch (error) {
        // Anything else — an RLS refusal, a bad query — is a real answer.
        rethrow;
      }

      if (attempt < attempts - 1) {
        // 400ms, then 1.2s. Enough for a carrier hiccup to clear without
        // making the user wait through a long ladder of retries.
        await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1) * (attempt + 1)));
      }
    }

    throw lastError ?? const SocketException('Network unavailable');
  }

  /// Whether the device can actually reach the internet, as opposed to merely
  /// being attached to a network. A captive portal or a data bundle that has
  /// run out both look "connected" to the OS.
  static Future<bool> isOnline() async {
    try {
      final result = await InternetAddress.lookup('supabase.co')
          .timeout(const Duration(seconds: 6));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// True when this failure is about the connection rather than the request.
  static bool isConnectionError(Object error) {
    if (error is TimeoutException) return true;
    if (error is SocketException) return true;
    if (error is HttpException) return true;

    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection closed') ||
        text.contains('connection reset') ||
        text.contains('connection refused') ||
        text.contains('network is unreachable') ||
        text.contains('timeout') ||
        text.contains('timed out');
  }
}

/// Rewrites a photo URL to ask for only the pixels actually being shown.
///
/// The seeded images are 1200px wide, roughly 200–400 KB each. A home screen
/// of 24 of those is several megabytes — instant on WiFi, painful on a mobile
/// bundle. Asking Unsplash for the size we are really drawing cuts that by
/// around an order of magnitude.
String sizedImageUrl(String url, int width) {
  if (url.isEmpty) return url;

  // Unsplash serves any width from the same URL.
  if (url.contains('images.unsplash.com')) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            'w': '$width',
            'q': width <= 400 ? '65' : '75',
            'auto': 'format',
            'fit': 'crop',
          },
        )
        .toString();
  }

  // Supabase Storage transforms, where the project plan allows them.
  if (url.contains('/storage/v1/object/public/')) {
    final base = url.replaceFirst('/object/public/', '/render/image/public/');
    final joiner = url.contains('?') ? '&' : '?';
    return '$base${joiner}width=$width&quality=75';
  }

  // Anything else is left alone rather than guessed at.
  return url;
}
