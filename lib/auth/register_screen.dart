import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import '../core/supabase_client.dart';
import '../data/models/user_role.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  UserRole _role = UserRole.customer;
  bool _isSubmitting = false;
  String? _error;

  Future<void> _register() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      // Registration writes both the Supabase auth user and the app-level
      // `users` row (with role) atomically, so it goes through the backend
      // rather than calling supabase.auth.signUp directly from the client.
      final res = await http.post(
        Uri.parse('${Env.apiBaseUrl}/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
          'fullName': _fullNameController.text.trim(),
          'role': _role.wireValue,
        }),
      );

      if (res.statusCode >= 400) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        throw Exception(body['error'] ?? 'Registration failed');
      }

      await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _fullNameController,
              decoration: const InputDecoration(labelText: 'Full name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<UserRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'I am a...'),
              items: const [
                DropdownMenuItem(value: UserRole.customer, child: Text('Customer')),
                DropdownMenuItem(value: UserRole.courier, child: Text('Courier')),
                DropdownMenuItem(value: UserRole.vendor, child: Text('Vendor')),
              ],
              onChanged: (value) => setState(() => _role = value ?? UserRole.customer),
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            FilledButton(
              onPressed: _isSubmitting ? null : _register,
              child: _isSubmitting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Register'),
            ),
          ],
        ),
      ),
    );
  }
}
