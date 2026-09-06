import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Supabase credentials.
///
/// Read from the bundled `.env` at runtime, but overridable at build time with
/// `--dart-define`, which is what CI and release builds should use:
///
///   flutter build apk --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
///
/// Only ever the anon key — Row Level Security is what protects the data, and
/// the service_role key must never ship inside an app binary.
class SupabaseConfig {
  const SupabaseConfig._();

  static const _urlFromDefine = String.fromEnvironment('SUPABASE_URL');
  static const _keyFromDefine = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get url {
    if (_urlFromDefine.isNotEmpty) return _urlFromDefine;
    final value = dotenv.maybeGet('SUPABASE_URL') ?? '';
    if (value.isEmpty) {
      throw StateError(
        'SUPABASE_URL is not set. Copy .env.example to .env and fill it in, '
        'or pass --dart-define=SUPABASE_URL=...',
      );
    }
    return value;
  }

  static String get anonKey {
    if (_keyFromDefine.isNotEmpty) return _keyFromDefine;
    final value = dotenv.maybeGet('SUPABASE_ANON_KEY') ?? '';
    if (value.isEmpty) {
      throw StateError(
        'SUPABASE_ANON_KEY is not set. Copy .env.example to .env and fill it in, '
        'or pass --dart-define=SUPABASE_ANON_KEY=...',
      );
    }
    return value;
  }

  /// The public Kheja_Link website. Support links in the app point here.
  /// Override per build with:
  ///   flutter build apk --dart-define=SITE_URL=https://staging.example.com
  static const siteUrl = String.fromEnvironment(
    'SITE_URL',
    defaultValue: 'https://khejalink.name.ng',
  );

  /// Deep link Supabase sends users back to after they confirm their email.
  /// Must match the scheme registered in AndroidManifest.xml / Info.plist and
  /// be listed under Authentication → URL Configuration in Supabase.
  static const authRedirect = 'ke.co.khejalink://login-callback';
}
