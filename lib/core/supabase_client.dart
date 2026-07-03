import 'package:supabase_flutter/supabase_flutter.dart';

/// Single shared Supabase client, initialized once in main().
SupabaseClient get supabase => Supabase.instance.client;
