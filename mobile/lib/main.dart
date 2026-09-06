import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'config/theme.dart';
import 'screens/app_shell.dart';
import 'services/kheja_api.dart';

/// Single Supabase-backed API instance for the whole app.
late final KhejaApi khejaApi;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // A missing .env should produce a readable screen, not a blank one.
  String? startupError;
  try {
    await dotenv.load(fileName: '.env', isOptional: true);
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
      authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
    );
    khejaApi = KhejaApi(Supabase.instance.client);
  } catch (error) {
    startupError = error.toString();
  }

  runApp(KhejaApp(startupError: startupError));
}

class KhejaApp extends StatelessWidget {
  const KhejaApp({super.key, this.startupError});

  final String? startupError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kheja_Link',
      debugShowCheckedModeBanner: false,
      theme: buildKhejaTheme(Brightness.light),
      darkTheme: buildKhejaTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: startupError == null
          ? const AppShell()
          : _ConfigErrorScreen(message: startupError!),
    );
  }
}

class _ConfigErrorScreen extends StatelessWidget {
  const _ConfigErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.settings_rounded, size: 56, color: KhejaColors.zinc400),
              const SizedBox(height: 24),
              Text(
                'Kheja_Link is not configured',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Copy .env.example to .env and add your Supabase URL and anon key, '
                'then restart the app.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(color: KhejaColors.zinc500),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: KhejaColors.zinc400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
