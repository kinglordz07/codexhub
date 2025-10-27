import 'dart:async';
import 'package:flutter/material.dart';
import 'package:codexhub01/utils/newpass.dart';

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
    // Schedule the callback after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleResetCallback());
  }

  Future<void> _handleResetCallback() async {
    try {
      final route = ModalRoute.of(context);
      if (route == null) throw Exception('No route found');

      final args = route.settings.arguments;
      if (args == null) throw Exception('No arguments provided');
      if (args is! Uri) throw Exception('Arguments must be a Uri');

      final Uri deepLink = args;
      final String? token = deepLink.queryParameters['token'];
      if (token == null || token.isEmpty) throw Exception('Invalid reset link');

      // Navigate to the UpdatePasswordScreen with token
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => UpdatePasswordScreen(token: token),
        ),
      );
    } on TimeoutException {
      _setError('Request timed out. Please try again.');
    } catch (e, st) {
      debugPrint('Reset error: $e');
      debugPrint('Stack trace: $st');
      _setError('Error: $e');
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _isLoading = false;
    });
  }

  void _retry() {
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
        child: _isLoading
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
                        onPressed: _retry,
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
