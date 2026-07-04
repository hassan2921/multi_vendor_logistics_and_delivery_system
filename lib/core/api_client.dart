import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config/env.dart';
import 'supabase_client.dart';

/// Thin HTTP client for the Express backend. Attaches the current Supabase
/// session's access token as a bearer token so the backend can verify it and
/// resolve the caller's app role.
class ApiClient {
  const ApiClient();

  Uri _uri(String path) => Uri.parse('${Env.apiBaseUrl}$path');

  Map<String, String> _headers({String? idempotencyKey}) {
    final token = supabase.auth.currentSession?.accessToken;
    final bearer = token == null ? null : 'Bearer $token';
    return {
      'Content-Type': 'application/json',
      'Authorization': ?bearer,
      'Idempotency-Key': ?idempotencyKey,
    };
  }

  Future<Map<String, dynamic>> get(String path) async {
    final res = await http.get(_uri(path), headers: _headers());
    return _decode(res);
  }

  /// [idempotencyKey] is required for any request that creates a
  /// side-effecting resource (orders, payment intents). The caller must
  /// generate the key ONCE per logical operation and reuse it across
  /// retries — a fresh key per attempt would defeat the dedup entirely.
  /// See backend's idempotency.middleware.ts for the server-side half.
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    String? idempotencyKey,
  }) async {
    final res = await http.post(
      _uri(path),
      headers: _headers(idempotencyKey: idempotencyKey),
      body: jsonEncode(body),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> patch(String path, Map<String, dynamic> body) async {
    final res = await http.patch(_uri(path), headers: _headers(), body: jsonEncode(body));
    return _decode(res);
  }

  Map<String, dynamic> _decode(http.Response res) {
    final body = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(res.statusCode, body['error'] as String? ?? 'Request failed');
    }
    return body;
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}
