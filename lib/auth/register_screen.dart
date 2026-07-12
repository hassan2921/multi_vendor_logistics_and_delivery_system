import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/config/env.dart';
import '../core/supabase_client.dart';
import '../core/ui/formatting.dart';
import '../core/widgets/async_views.dart';
import '../core/widgets/brand_header.dart';
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
  bool _obscurePassword = true;
  Object? _error;

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
      setState(() => _error = e);
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
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                children: [
                  const BrandHeader(subtitle: 'Create your account to get started'),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _fullNameController,
                            decoration: const InputDecoration(
                              labelText: 'Full name',
                              prefixIcon: Icon(Icons.person_outline_rounded),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            obscureText: _obscurePassword,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'I want to join as',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 8),
                          SegmentedButton<UserRole>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment(value: UserRole.customer, label: Text('Customer')),
                              ButtonSegment(value: UserRole.courier, label: Text('Courier')),
                              ButtonSegment(value: UserRole.vendor, label: Text('Vendor')),
                            ],
                            selected: {_role},
                            onSelectionChanged: (s) => setState(() => _role = s.first),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 16),
                            InlineError(friendlyError(_error!)),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _isSubmitting ? null : _register,
                            child: _isSubmitting
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                  )
                                : const Text('Create account'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
