// ignore_for_file: avoid_print

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final SupabaseClient _supabase;

  AuthService({SupabaseClient? supabaseClient})
      : _supabase = supabaseClient ?? Supabase.instance.client;

  // 🔹 Current user & session
  User? get currentUser => _supabase.auth.currentUser;
  bool get isLoggedIn => _supabase.auth.currentSession != null;

  // 🔹 Fetch role from 'profiles_new' table
  Future<String> _fetchUserRole(User user) async {
    try {
      final profile = await _supabase
          .from('profiles_new')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      return profile?['role'] as String? ?? 'student';
    } catch (e) {
      debugPrint('❌ Error fetching user role: $e');
      return 'student';
    }
  }

  Future<String> getCurrentUserRole() async {
    final user = currentUser;
    if (user == null) return 'student';
    return _fetchUserRole(user);
  }

  // 🔹 Sign up - WITH EMAIL CONFIRMATION & ADMIN APPROVAL
Future<Map<String, dynamic>> signUp({
  required String email,
  required String password,
  String? username,
  required String role,
}) async {
  try {
    debugPrint('🎯 STARTING SIGNUP PROCESS');
    debugPrint('📧 Email: $email');
    debugPrint('👤 Username: $username');
    debugPrint('🎭 Role: $role');

    // 1️⃣ Validate role
    final validRoles = ['student', 'mentor'];
    if (!validRoles.contains(role.toLowerCase())) {
      return {'success': false, 'error': 'Invalid role, must be student or mentor'};
    }

    // 2️⃣ Ensure username
    final safeUsername = (username != null && username.isNotEmpty)
        ? username
        : 'user_${DateTime.now().millisecondsSinceEpoch}';

    debugPrint('🔍 Checking for duplicate username: $safeUsername');
    
    // 3️⃣ Check duplicates
    final existingUsername = await _supabase
        .from('profiles_new')
        .select('username')
        .eq('username', safeUsername)
        .maybeSingle();

    if (existingUsername != null) {
      debugPrint('❌ Username already exists');
      return {'success': false, 'error': 'Username already exists'};
    }

    debugPrint('✅ No duplicate username found');

    // 4️⃣ Create auth user - MINIMAL DEBUGGING
    debugPrint('🔄 CREATING AUTH USER...');
    
    final response = await _supabase.auth.signUp(
      email: email, 
      password: password,
      data: {
        'username': safeUsername,
        'role': role.toLowerCase(),
      }
    );
    
    // ONLY use properties that definitely exist
    final user = response.user;
    
    debugPrint('📦 AUTH RESPONSE SUMMARY:');
    debugPrint('  - User Created: ${user != null ? "YES" : "NO"}');
    debugPrint('  - User ID: ${user?.id ?? "NULL"}');
    debugPrint('  - Session: ${response.session != null ? "EXISTS" : "NULL"}');
    
    if (user == null) {
      debugPrint('❌ NO USER RETURNED FROM AUTH');
      return {'success': false, 'error': 'Failed to create auth user'};
    }

    debugPrint('✅ AUTH USER CREATED: ${user.id}');
    debugPrint('📧 User email: ${user.email}');
    debugPrint('🔐 Email confirmed: ${user.emailConfirmedAt}');
    debugPrint('📨 Confirmation sent: ${user.confirmationSentAt}');

    // 5️⃣ Wait and create profile
    debugPrint('⏳ Waiting before profile creation...');
    await Future.delayed(const Duration(seconds: 2));

    final profileData = {
      'id': user.id,
      'username': safeUsername,
      'role': role.toLowerCase(),
      'is_approved': false,
    };

    debugPrint('📝 PROFILE DATA: $profileData');
    
    try {
      debugPrint('🔄 CREATING PROFILE...');
      final profileInsert = await _supabase
          .from('profiles_new')
          .insert(profileData)
          .select()
          .single();
      
      debugPrint('✅ PROFILE CREATED SUCCESSFULLY');
      debugPrint('   - ID: ${profileInsert['id']}');
      debugPrint('   - Username: ${profileInsert['username']}');
      debugPrint('   - Role: ${profileInsert['role']}');
      debugPrint('   - Approved: ${profileInsert['is_approved']}');
      
      return {
        'success': true, 
        'user': user, 
        'profile': profileInsert,
        'message': 'Account created successfully! Please check your email for verification.',
        'userId': user.id,
        'requiresEmailVerification': user.emailConfirmedAt == null,
      };
    } catch (e) {
      debugPrint('❌ PROFILE CREATION FAILED: $e');
      // Even if profile fails, auth user was created
      return {
        'success': false, 
        'error': 'Account created but profile setup incomplete. Please check your email for verification.',
        'partialSuccess': true,
        'userId': user.id,
        'requiresEmailVerification': user.emailConfirmedAt == null,
      };
    }

  } catch (e, st) {
    debugPrint('💥 SIGNUP EXCEPTION: $e');
    debugPrint('📄 STACK TRACE: $st');
    return {'success': false, 'error': 'Signup failed: $e'};
  }
}

  // 🔹 Sign in - WITH CHECKS FOR VERIFICATION & APPROVAL
Future<Map<String, dynamic>> signIn({
  required String email,
  required String password,
}) async {
  try {
    final response = await _supabase.auth.signInWithPassword(email: email, password: password);
    final user = response.user;
    
    if (user != null) {
      // Check if email is verified
      if (user.emailConfirmedAt == null) {
        return {
          'success': false, 
          'error': 'Please verify your email before logging in. Check your inbox.',
          'requiresEmailVerification': true
        };
      }

      // Get user profile to check admin approval
      final profile = await _supabase
          .from('profiles_new')
          .select('role, is_approved')
          .eq('id', user.id)
          .maybeSingle();

      if (profile == null) {
        return {'success': false, 'error': 'Profile not found. Please contact support.'};
      }

      final role = profile['role'] as String? ?? 'student';
      final isApproved = profile['is_approved'] as bool? ?? false;

      // Check if user is approved by admin
      if (!isApproved) {
        return {
          'success': false, 
          'error': 'Your account is pending admin approval. Please wait for approval to access the platform.',
          'pendingApproval': true,
          'role': role
        };
      }

      return {
        'success': true, 
        'role': role, 
        'userId': user.id,
        'isApproved': true
      };
    }
    
    return {'success': false, 'error': 'Login failed'};
  } catch (e) {
    debugPrint('❌ SignIn exception: $e');
    return {'success': false, 'error': e.toString()};
  }
}

// 🔹 Resend email verification
Future<Map<String, dynamic>> resendVerificationEmail(String email) async {
  try {
    await _supabase.auth.resend(
      type: OtpType.signup,
      email: email,
    );
    return {'success': true, 'message': 'Verification email sent to $email'};
  } catch (e) {
    debugPrint('❌ Error resending verification: $e');
    return {'success': false, 'error': e.toString()};
  }
}

  // 🔹 Send reset password OTP
  Future<Map<String, dynamic>> sendResetOtp(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'com.codexhub01://reset-callback/',
      );
      return {'success': true, 'message': 'OTP sent to $email'};
    } catch (e) {
      debugPrint('❌ Error sending OTP: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 🔹 Update password
  Future<Map<String, dynamic>> updatePassword({required String newPassword}) async {
    try {
      final response = await _supabase.auth.updateUser(UserAttributes(password: newPassword));
      if (response.user == null) return {'success': false, 'error': 'Failed to update password'};
      return {'success': true, 'message': 'Password updated successfully'};
    } catch (e) {
      debugPrint('❌ Error updating password: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  // 🔹 Sign out
  Future<void> signOut() async {
    await _supabase.auth.signOut();
    debugPrint('✅ User signed out');
  }
}