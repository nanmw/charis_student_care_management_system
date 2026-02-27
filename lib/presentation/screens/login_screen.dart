import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/seed_provider.dart';
import 'package:charis_student_care/presentation/widgets/shell/app_footer.dart';

/// Username/password login screen.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(authStateProvider.notifier).signInWithCredentials(
          _usernameController.text.trim(),
          _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(seedFirstAdminProvider);
    final authAsync = ref.watch(authStateProvider);
    final isLoading = authAsync.isLoading;
    final error = authAsync.hasError ? authAsync.error : null;

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/logo.png',
                        height: 100,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Charis Student Care',
                        style: TextStyle(
                            fontSize: 32, fontWeight: FontWeight.bold,),
                      ),
                      const SizedBox(height: 48),
                      if (error != null) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            error
                                .toString()
                                .replaceFirst('AuthException: ', ''),
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error,),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                      SizedBox(
                        width: 320,
                        child: TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          textInputAction: TextInputAction.next,
                          enabled: !isLoading,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Enter username';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 320,
                        child: TextFormField(
                          controller: _passwordController,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          enabled: !isLoading,
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return 'Enter password';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: 320,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : _submit,
                          child: isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,),
                                )
                              : const Text('Log in'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const AppFooter(),
        ],
      ),
    );
  }
}
