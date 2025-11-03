import 'package:flutter/material.dart';
import 'package:codexhub01/parts/log_in.dart';
import 'package:codexhub01/services/authservice.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    try {
      // Add a small delay to show the splash screen
      await Future.delayed(const Duration(milliseconds: 1500));

      if (_authService.isLoggedIn) {
        final userRole = await _authService.getCurrentUserRole();
        debugPrint('✅ User is logged in with role: $userRole');
        
        // Navigate based on role
        _navigateBasedOnRole(userRole);
      } else {
        debugPrint('❌ User is not logged in, going to login screen');
        _goToLogin();
      }
    } catch (e, st) {
      debugPrint('💥 Error checking auth status: $e');
      debugPrint('📄 Stack trace: $st');
      _goToLogin();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateBasedOnRole(String role) {
    if (!mounted) return;

    try {
      switch (role) {
        case 'student':
          // Navigate to student dashboard
          Navigator.pushReplacementNamed(context, '/student-dashboard');
          break;
        case 'mentor':
          // Navigate to mentor dashboard
          Navigator.pushReplacementNamed(context, '/mentor-dashboard');
          break;
        default:
          _goToLogin();
      }
    } catch (e, st) {
      debugPrint('💥 Navigation error: $e');
      debugPrint('📄 Stack trace: $st');
      _goToLogin();
    }
  }

  void _goToLogin() {
    if (!mounted) return;

    try {
      // ✅ FIXED: Use Navigator.pushReplacement with proper context
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const SignIn()),
          );
        }
      });
    } catch (e, st) {
      debugPrint('💥 Error navigating to login: $e');
      debugPrint('📄 Stack trace: $st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Your app logo
            Icon(
              Icons.code,
              size: 80,
              color: Colors.white,
            ),
            const SizedBox(height: 20),
            Text(
              'CodexHub',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}