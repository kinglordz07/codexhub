import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // --- Current User & Session ---
  User? get currentUser => _supabase.auth.currentUser;
  bool get isLoggedIn => _supabase.auth.currentSession != null;

  // --- PRIVATE: Fetch role from profiles table ---
  Future<String> _fetchUserRole(User user) async {
    try {
      final profile =
          await _supabase
              .from('profiles')
              .select('role')
              .eq('id', user.id)
              .maybeSingle();
      return profile?['role'] ?? 'user';
    } catch (e) {
      debugPrint('❌ Error fetching user role: $e');
      return 'user';
    }
  }

  // --- PUBLIC: Get current user's role ---
  Future<String> getCurrentUserRole() async {
    final user = currentUser;
    if (user == null) return 'user';
    return await _fetchUserRole(user);
  }

  // --- SIGN UP ---
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String username,
    required String role, // must be 'user' or 'mentor'
  }) async {
    try {
      debugPrint(
        '➡️ Starting signup for email: $email, username: $username, role: $role',
      );

      // 1️⃣ Create auth user first
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );
      debugPrint('✅ Auth signUp response: $response');

      final user = response.user;

      if (user == null) {
        debugPrint('❌ No user returned from auth.signUp()');
        return {'success': false, 'error': 'Failed to create auth user'};
      }

      debugPrint('➡️ Auth user created with ID: ${user.id}');

      // ensure role is valid
      final roleValue = role.toLowerCase();
      if (roleValue != 'user' && roleValue != 'mentor') {
        debugPrint('❌ Invalid role provided: $roleValue');
        return {
          'success': false,
          'error': 'Invalid role, must be user or mentor',
        };
      }

      // 2️⃣ Insert profile into `profiles` table
      debugPrint('➡️ Inserting profile into database...');
      final insertResponse =
          await _supabase
              .from('profiles')
              .insert({
                'id': user.id,
                'username': username,
                'email': email,
                'role': roleValue,
              })
              .select()
              .maybeSingle();
      debugPrint('✅ Profile inserted: $insertResponse');

      return {
        'success': true,
        'userId': user.id,
        'role': roleValue,
        'profile': insertResponse,
      };
    } catch (e, st) {
      debugPrint('❌ Signup caught exception: $e\n$st');

      String errorMessage = e.toString();

      // detect duplicate keys or role issues
      if (errorMessage.contains('duplicate key value')) {
        if (errorMessage.contains('username')) {
          errorMessage = 'Username already exists';
        } else if (errorMessage.contains('email')) {
          errorMessage = 'Email already exists';
        }
        debugPrint('⚠️ Duplicate key error detected: $errorMessage');
      } else if (errorMessage.contains('invalid input value') ||
          errorMessage.contains('role')) {
        errorMessage = 'Invalid role, must be user or mentor';
        debugPrint('⚠️ Role validation error detected: $errorMessage');
      }

      return {'success': false, 'error': errorMessage};
    }
  }

  // --- SIGN IN ---
  Future<Map<String, dynamic>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = response.user;
      if (user != null) {
        final role = await _fetchUserRole(user);
        return {'success': true, 'role': role, 'userId': user.id};
      } else {
        return {'success': false, 'error': 'Login failed'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<void> sendResetOtp(String email) async {
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'com.codexhub01://reset-callback/', // optional deep link
      );
      print('OTP sent to $email');
    } catch (e) {
      print('Error sending OTP: $e');
    }
  }

  Future<void> verifyOtpAndUpdatePassword(
    String token,
    String newPassword,
  ) async {
    final response = await Supabase.instance.client.auth.updateUser(
      UserAttributes(password: newPassword),
      // If using token-based reset
      // Not needed if using deep link in app
    );

    if (response.user == null) {
      print('Error updating password: Failed to update user password.');
    } else {
      print('Password updated successfully!');
    }
  }

  // --- SIGN OUT ---
  Future<void> signOut() async {
    await _supabase.auth.signOut();
    debugPrint("✅ User signed out");
  }
}
