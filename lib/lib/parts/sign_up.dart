// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:codexhub01/parts/log_in.dart';
import 'package:codexhub01/services/authservice.dart';
import 'package:codexhub01/parts/mentor_qualification'; // IMPORT QUALIFICATION

class SignUp extends StatefulWidget {
  const SignUp({super.key});

  @override
  State<SignUp> createState() => _SignUpState();
}

class _SignUpState extends State<SignUp> {
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  String? _selectedRole;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    _safeSetState(() => _isLoading = true);

    try {
      final username = _usernameController.text.trim();
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();
      final role = _selectedRole?.toLowerCase();

      if (role == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Please select a role"), backgroundColor: Colors.red),
        );
        return;
      }

      final result = await _authService.signUp(
        email: email,
        password: password,
        username: username,
        role: role,
      );

      debugPrint('📝 AuthService result: $result');
      debugPrint('🎭 Selected role: $role');

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ ${result['message']}"),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );

        // ✅✅✅ FIXED: CHECK IF MENTOR OR STUDENT
        if (role == 'mentor') {
          debugPrint('🚀 Redirecting mentor to qualification page...');
          // MENTOR -> QUALIFICATION PAGE
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => MentorQualification(
                username: username,
                email: email,
              ),
            ),
          );
        } else {
          debugPrint('🎓 Redirecting student to login page...');
          // STUDENT -> LOGIN PAGE
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const SignIn()),
          );
        }

      } else if (result['requiresEmailVerification'] == true) {
        // Email verification required
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("📧 Check your email! Verification link sent. You'll also need admin approval."),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 6),
          ),
        );
        
        // ✅✅✅ FIXED: CHECK IF MENTOR OR STUDENT FOR EMAIL VERIFICATION CASE TOO
        if (role == 'mentor') {
          debugPrint('🚀 Redirecting mentor to qualification page (email verification required)...');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => MentorQualification(
                username: username,
                email: email,
              ),
            ),
          );
        } else {
          debugPrint('🎓 Redirecting student to login page (email verification required)...');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const SignIn()),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ ${result['error']}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('💥 Unexpected exception during signup: $e\n$st');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Unexpected error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      _safeSetState(() => _isLoading = false);
    }
  }

  // ... (REST OF YOUR CODE REMAINS THE SAME - validators and UI)
  String? _validateUsername(String? value) {
    if (value == null || value.isEmpty) return 'Please enter a username';
    return value.length >= 3 ? null : 'Username must be at least 3 characters';
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your email';
    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
    if (!emailRegex.hasMatch(value)) return 'Please enter a valid email';
    return null;
  }

  String? _validatePassword(String? value) =>
      (value == null || value.isEmpty)
          ? 'Please enter your password'
          : (value.length < 6 ? 'Password must be at least 6 characters' : null);

  String? _validateConfirmPassword(String? value) =>
      value != _passwordController.text ? 'Passwords do not match' : null;

  String? _validateRole(String? value) =>
      (value == null || value.isEmpty)
          ? 'Please select a role'
          : (value != 'student' && value != 'mentor' ? 'Invalid role selected' : null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black45 : Colors.black12,
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    "Create Account",
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildTextField(_usernameController, "Username", Icons.person_outline, _validateUsername, isDark),
                  const SizedBox(height: 20),
                  _buildTextField(_emailController, "Email", Icons.email_outlined, _validateEmail, isDark),
                  const SizedBox(height: 20),
                  _buildPasswordField(_passwordController, "Password", _obscurePassword, () => _safeSetState(() => _obscurePassword = !_obscurePassword), isDark),
                  const SizedBox(height: 20),
                  _buildPasswordField(_confirmPasswordController, "Confirm Password", _obscureConfirmPassword, () => _safeSetState(() => _obscureConfirmPassword = !_obscureConfirmPassword), isDark),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedRole,
                    onChanged: _isLoading ? null : (v) => _safeSetState(() => _selectedRole = v),
                    items: const [
                      DropdownMenuItem(value: "student", child: Text("Student")),
                      DropdownMenuItem(value: "mentor", child: Text("Mentor")),
                    ],
                    decoration: const InputDecoration(labelText: "Select Role"),
                    validator: _validateRole,
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ElevatedButton(
                            onPressed: _signUp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colorScheme.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text(
                              "Create Account",
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Already have an account?", style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                      TextButton(
                        onPressed: () {
                          if (!mounted) return;
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SignIn()));
                        },
                        child: Text("Login", style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, String? Function(String?)? validator, bool isDark) {
    return TextFormField(
      controller: controller,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _buildPasswordField(TextEditingController controller, String label, bool obscureText, VoidCallback toggleObscure, bool isDark) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      validator: label == "Confirm Password" ? _validateConfirmPassword : _validatePassword,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        filled: true,
        fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        suffixIcon: IconButton(
          icon: Icon(obscureText ? Icons.visibility : Icons.visibility_off, color: Theme.of(context).colorScheme.primary),
          onPressed: toggleObscure,
        ),
      ),
    );
  }
}