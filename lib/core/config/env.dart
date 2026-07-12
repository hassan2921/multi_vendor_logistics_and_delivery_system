import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Thin wrapper around the values loaded from the bundled `.env` asset.
/// All defaults here are placeholders — see `.env.example` at the repo root.
class Env {
  static String get supabaseUrl => dotenv.get('SUPABASE_URL', fallback: 'PLACEHOLDER_SUPABASE_URL');

  static String get supabaseAnonKey =>
      dotenv.get('SUPABASE_ANON_KEY', fallback: 'PLACEHOLDER_SUPABASE_ANON_KEY');

  static String get apiBaseUrl => dotenv.get('API_BASE_URL', fallback: 'http://localhost:3000');

  static String get stripePublishableKey =>
      dotenv.get('STRIPE_PUBLISHABLE_KEY', fallback: 'PLACEHOLDER_pk_test');
}
