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
        'message': 'Account created successfully!, Please wait for Admin approval',
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

  // 🔹 SUBMIT MENTOR QUALIFICATION - FIXED METHOD
Future<Map<String, dynamic>> submitMentorQualification(Map<String, dynamic> qualificationData) async {
  try {
    debugPrint('🎯 SUBMITTING MENTOR QUALIFICATION');
    debugPrint('📝 Qualification data: $qualificationData');

    // 1️⃣ Validate required fields
    final requiredFields = ['username', 'email', 'fullName', 'profession', 'yearsOfExperience', 'education'];
    for (final field in requiredFields) {
      if (qualificationData[field] == null || qualificationData[field].toString().isEmpty) {
        return {'success': false, 'error': 'Missing required field: $field'};
      }
    }

    // 2️⃣ Check if user exists in profiles_new - FIXED QUERY
    debugPrint('🔍 Checking user profile...');
    final userProfile = await _supabase
        .from('profiles_new')
        .select('id, role')
        .eq('username', qualificationData['username'].toString()) // ✅ FIXED
        .maybeSingle();

    debugPrint('📊 User profile result: $userProfile');

    if (userProfile == null) {
      return {'success': false, 'error': 'User profile not found. Please sign up first.'};
    }

    // 3️⃣ Verify user is a mentor
    if (userProfile['role'] != 'mentor') {
      return {'success': false, 'error': 'Only users with mentor role can submit qualifications'};
    }

    // 4️⃣ Prepare qualification data for database
    final dbData = {
      'user_id': userProfile['id'],
      'username': qualificationData['username'].toString(),
      'email': qualificationData['email'].toString(),
      'full_name': qualificationData['fullName'].toString(),
      'profession': qualificationData['profession'].toString(),
      'company': qualificationData['company']?.toString() ?? '',
      'years_of_experience': qualificationData['yearsOfExperience'],
      'education': qualificationData['education'].toString(),
      'has_mentoring_experience': qualificationData['hasMentoringExperience'] ?? false,
      'expertise_areas': qualificationData['expertiseAreas'] ?? [],
      'hours_per_week': qualificationData['hoursPerWeek'],
      'motivation': qualificationData['motivation']?.toString() ?? '',
      'submitted_at': DateTime.now().toIso8601String(),
      'status': 'pending', // pending, approved, rejected
      'reviewed_by': null,
      'reviewed_at': null,
      'admin_notes': null,
    };

    debugPrint('💾 Saving qualification to database...');

    // 5️⃣ Insert into mentor_qualifications table
    final qualificationInsert = await _supabase
        .from('mentor_qualifications')
        .insert(dbData)
        .select()
        .single();

    debugPrint('✅ MENTOR QUALIFICATION SUBMITTED SUCCESSFULLY');
    debugPrint('   - Qualification ID: ${qualificationInsert['id']}');
    debugPrint('   - User ID: ${qualificationInsert['user_id']}');
    debugPrint('   - Status: ${qualificationInsert['status']}');

    // 6️⃣ Update profiles_new to mark as qualification submitted
    await _supabase
        .from('profiles_new')
        .update({
          'qualification_submitted': true,
          'qualification_submitted_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userProfile['id']);

    debugPrint('📝 Profile updated with qualification submission timestamp');

    return {
      'success': true,
      'message': 'Mentor qualification submitted successfully! Please wait for admin approval.',
      'qualificationId': qualificationInsert['id'],
      'status': 'pending',
    };

  } catch (e, st) {
    debugPrint('💥 ERROR SUBMITTING MENTOR QUALIFICATION: $e');
    debugPrint('📄 STACK TRACE: $st');
    
    // More specific error handling
    if (e.toString().contains('relation "mentor_qualifications" does not exist')) {
      return {'success': false, 'error': 'Database table not found. Please create mentor_qualifications table first.'};
    } else if (e.toString().contains('network') || e.toString().contains('timeout')) {
      return {'success': false, 'error': 'Network error. Please check your internet connection.'};
    } else {
      return {'success': false, 'error': 'Failed to submit qualification: $e'};
    }
  }
}

  // 🔹 CHECK MENTOR QUALIFICATION STATUS - NEW METHOD
  Future<Map<String, dynamic>> getMentorQualificationStatus(String userId) async {
    try {
      debugPrint('🔍 Checking mentor qualification status for user: $userId');

      final qualification = await _supabase
          .from('mentor_qualifications')
          .select('*')
          .eq('user_id', userId)
          .order('submitted_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (qualification == null) {
        return {'success': true, 'status': 'not_submitted', 'message': 'No qualification submitted yet'};
      }

      return {
        'success': true,
        'status': qualification['status'] ?? 'pending',
        'qualification': qualification,
        'message': 'Qualification ${qualification['status']}',
      };
    } catch (e) {
      debugPrint('❌ Error checking qualification status: $e');
      return {'success': false, 'error': 'Failed to check qualification status: $e'};
    }
  }

  // 🔹 GET ALL PENDING QUALIFICATIONS (For Admin) - NEW METHOD
  Future<Map<String, dynamic>> getPendingMentorQualifications() async {
    try {
      debugPrint('📋 Fetching pending mentor qualifications');

      final qualifications = await _supabase
          .from('mentor_qualifications')
          .select('''
            *,
            profiles_new:user_id (username, email, created_at)
          ''')
          .eq('status', 'pending')
          .order('submitted_at', ascending: true);

      return {
        'success': true,
        'qualifications': qualifications,
        'count': qualifications.length,
      };
    } catch (e) {
      debugPrint('❌ Error fetching pending qualifications: $e');
      return {'success': false, 'error': 'Failed to fetch pending qualifications: $e'};
    }
  }

  // 🔹 UPDATE QUALIFICATION STATUS (For Admin) - NEW METHOD
  Future<Map<String, dynamic>> updateQualificationStatus({
    required String qualificationId,
    required String status,
    String? adminNotes,
    required String adminUserId,
  }) async {
    try {
      debugPrint('🔄 Updating qualification status: $qualificationId to $status');

      final updateData = {
        'status': status,
        'reviewed_by': adminUserId,
        'reviewed_at': DateTime.now().toIso8601String(),
        if (adminNotes != null) 'admin_notes': adminNotes,
      };

      // Update qualification status
      final qualificationUpdate = await _supabase
          .from('mentor_qualifications')
          .update(updateData)
          .eq('id', qualificationId)
          .select()
          .single();

      // If approved, update the user's profile to approved
      if (status == 'approved') {
        await _supabase
            .from('profiles_new')
            .update({'is_approved': true})
            .eq('id', qualificationUpdate['user_id']);
        
        debugPrint('✅ User profile approved for mentor role');
      }

      debugPrint('✅ Qualification status updated successfully');

      return {
        'success': true,
        'message': 'Qualification $status successfully',
        'qualification': qualificationUpdate,
      };
    } catch (e) {
      debugPrint('❌ Error updating qualification status: $e');
      return {'success': false, 'error': 'Failed to update qualification status: $e'};
    }
  }
}