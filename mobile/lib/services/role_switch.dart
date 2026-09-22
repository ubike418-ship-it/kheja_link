import 'package:flutter/material.dart';

import '../config/app_state.dart';
import '../config/theme.dart';
import '../main.dart';
import '../screens/app_shell.dart';
import '../widgets/states.dart';
import 'kheja_api.dart';

/// "List a house" from the tenant side.
///
/// Signed out: go through the landlord door. Signed in as a tenant: offer to
/// switch the account to a landlord account (a user may do that for
/// themselves; the database refuses anything beyond it). Either way the app
/// restarts into the landlord experience, whose tour runs if it has not yet.
Future<void> openListAHouse(BuildContext context) async {
  if (khejaApi.isSignedIn) {
    final profile = await khejaApi.fetchProfile().catchError((_) => null);
    if (!context.mounted) return;
    if (profile == null) {
      showKhejaSnack(context, 'Could not load your account. Please try again.', isError: true);
      return;
    }

    if (!profile.isLandlord) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KhejaRadius.lg)),
          title: const Text('List a property?'),
          content: const Text(
            'Your account will become a landlord account, so you can list and manage '
            'houses. Listing is free for now.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;

      try {
        await khejaApi.updateProfile(
          fullName: profile.fullName ?? '',
          phone: profile.phone,
          bio: profile.bio,
          role: 'landlord',
        );
      } catch (error) {
        if (context.mounted) showKhejaSnack(context, describeError(error), isError: true);
        return;
      }
    }
  }

  await AppState.instance.setChosenRole('landlord');
  if (!context.mounted) return;
  await Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const AppShell()),
    (_) => false,
  );
}
