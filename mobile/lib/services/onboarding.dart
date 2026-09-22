import '../config/app_state.dart';
import '../main.dart';
import '../models/models.dart';

/// Whether a first-run tour is due, and recording that it is done.
///
/// A tour is shown once per role. "Done" is remembered twice: on the device
/// (works signed out and offline) and on the account (carries across phones).
/// Either one is enough to skip it.
class Onboarding {
  const Onboarding._();

  static bool isDue(String role, Profile? profile) {
    if (AppState.instance.hasToured(role)) return false;

    final onAccount = switch (role) {
      'landlord' => profile?.landlordOnboardedAt,
      _ => profile?.tenantOnboardedAt,
    };
    if (onAccount != null) {
      // Seen on another phone: remember it here too, quietly.
      AppState.instance.markToured(role);
      return false;
    }
    return true;
  }

  static Future<void> complete(String role) async {
    await AppState.instance.markToured(role);
    await khejaApi.markOnboarded(role);
  }
}
