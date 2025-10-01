import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:codexhub01/parts/newpass.dart';

class ResetPasswordCallback extends StatefulWidget {
  const ResetPasswordCallback({super.key});

  @override
  State<ResetPasswordCallback> createState() => _ResetPasswordCallbackState();
}

class _ResetPasswordCallbackState extends State<ResetPasswordCallback> {
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Wait until context is available
    Future.delayed(Duration.zero, _handleResetCallback);
  }

  Future<void> _handleResetCallback() async {
    try {
      final route = ModalRoute.of(context);
      if (route == null) throw Exception('No route found');

      final settings = route.settings;
      if (settings.arguments == null) throw Exception('No arguments found');
      if (settings.arguments is! Uri)
        throw Exception('Arguments are not a Uri');

      final Uri deepLink = settings.arguments as Uri;
      final String? token = deepLink.queryParameters['token'];
      if (token == null || token.isEmpty) throw Exception('Invalid reset link');

      // Complete password recovery
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: ''), // Will be updated in the next screen
      );

      if (!mounted) return;

      // Open UpdatePasswordScreen
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => UpdatePasswordScreen()),
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = 'Request timed out. Please try again.';
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('Reset error: $e');
      debugPrint('Stack trace: $stackTrace');
      if (!mounted) return;
      setState(() {
        _error = 'Error: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _retryResetCallback() {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _handleResetCallback();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child:
            _isLoading
                ? const CircularProgressIndicator()
                : Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _error ?? 'An unknown error occurred',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 20),
                      if (_error != null)
                        ElevatedButton(
                          onPressed: _retryResetCallback,
                          child: const Text('Try Again'),
                        ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                ),
      ),
    );
  }
}
