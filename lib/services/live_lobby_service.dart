// ignore_for_file: avoid_print

import 'package:supabase_flutter/supabase_flutter.dart';

class LiveLobbyService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// 🔹 FIXED: Fetch all mentors from profiles_new table
  Future<List<Map<String, dynamic>>> fetchMentors() async {
    try {
      print('🟡 fetchMentors: Fetching mentors from profiles_new...');
      
      final response = await _supabase
          .from('profiles_new') // FIXED: Changed from 'profiles' to 'profiles_new'
          .select('id, username, avatar_url, role, online_status')
          .eq('role', 'mentor')
          .order('username');

      print('✅ fetchMentors: Found ${response.length} mentors');
      return List<Map<String, dynamic>>.from(response);
    } catch (e, stack) {
      print('❌ Error fetching mentors: $e');
      print(stack);
      return [];
    }
  }

  /// 🔹 FIXED: Create live session + invitation with profiles_new table
  Future<Map<String, dynamic>?> createLiveSession(
    String menteeId,
    String mentorId,
    String menteeName, // FIXED: Added menteeName parameter
  ) async {
    try {
      print('🟡 createLiveSession: Starting for mentee: $menteeId, mentor: $mentorId');

      // FIXED: Get mentee name from profiles_new if not provided
      String finalMenteeName = menteeName;
      if (menteeName.isEmpty) {
        print('🟡 createLiveSession: Fetching mentee name from profiles_new...');
        final profileRes = await _supabase
            .from('profiles_new') // FIXED: Use profiles_new
            .select('username')
            .eq('id', menteeId)
            .maybeSingle();
        
        finalMenteeName = profileRes?['username'] ?? 'Mentee';
        print('🟢 createLiveSession: Found mentee name: $finalMenteeName');
      }

      // Generate room name
      final roomName = 'Live Session with $finalMenteeName';

      print('🟡 createLiveSession: Creating room...');
      final insertedRoom = await _supabase
          .from('rooms')
          .insert({
            'name': roomName,
            'creator_id': menteeId,
            'is_public': false, // FIXED: Changed to false for privacy
            'description': 'Live coding session',
          })
          .select()
          .single();
      
      print('🟢 createLiveSession: Room created: ${insertedRoom['id']}');

      final roomId = insertedRoom['id']?.toString();
      if (roomId == null) {
        print('🔴 createLiveSession: Room insert returned null ID');
        return null;
      }

      // Add mentee as room member
      print('🟡 createLiveSession: Adding mentee to room members...');
      await _supabase.from('room_members').insert({
        'room_id': roomId,
        'user_id': menteeId,
      });

      print('🟡 createLiveSession: Creating live session...');
      final sessionRes = await _supabase
          .from('live_sessions')
          .insert({
            'room_id': roomId,
            'mentee_id': menteeId,
            'mentor_id': mentorId,
            'code': '// Welcome to the live coding session!\n// Start coding together...',
            'is_live': true, // FIXED: Set to true when mentor is invited
            'language': 'python',
            'waiting': false, // FIXED: Not waiting since mentor is directly invited
          })
          .select('id')
          .single();
      
      print('🟢 createLiveSession: Live session created: ${sessionRes['id']}');

      final sessionId = sessionRes['id']?.toString();
      if (sessionId == null) {
        print('🔴 createLiveSession: Session insert returned null ID');
        return null;
      }

      // FIXED: Create invitation record
      print('🟡 createLiveSession: Creating invitation...');
      await _supabase.from('live_invitations').insert({
        'session_id': sessionId,
        'mentor_id': mentorId,
        'mentee_id': menteeId,
        'mentee_name': finalMenteeName,
        'status': 'pending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      print('✅ createLiveSession: Room, live session, and invitation created successfully');
      
      return {
        'sessionId': sessionId,
        'roomId': roomId,
        'roomName': roomName,
        'menteeId': menteeId,
        'mentorId': mentorId,
      };
    } catch (e, stack) {
      print('❌ Error creating live session: $e');
      print('Stack trace: $stack');
      return null;
    }
  }

  /// 🔹 FIXED: Fetch mentor profile from profiles_new
  Future<Map<String, dynamic>?> getMentorProfile(String mentorId) async {
    try {
      print('🟡 getMentorProfile: Fetching profile for mentor: $mentorId');
      
      final response = await _supabase
          .from('profiles_new') // FIXED: Use profiles_new
          .select('id, username, avatar_url, role, online_status')
          .eq('id', mentorId)
          .eq('role', 'mentor')
          .maybeSingle();

      if (response != null) {
        print('✅ getMentorProfile: Found mentor profile: ${response['username']}');
      } else {
        print('⚠️ getMentorProfile: Mentor not found: $mentorId');
      }

      return response;
    } catch (e, stack) {
      print('❌ Error fetching mentor profile: $e');
      print(stack);
      return null;
    }
  }

  /// 🔹 FIXED: Fetch all pending invites for a mentor
  Future<List<Map<String, dynamic>>> fetchInvitesForMentor(String mentorId) async {
    try {
      print('🟡 fetchInvitesForMentor: Fetching invites for mentor: $mentorId');
      
      final response = await _supabase
          .from('live_invitations')
          .select('''
            id, 
            session_id, 
            mentee_name, 
            status, 
            created_at,
            live_sessions!inner(room_id, room:rooms(name))
          ''')
          .eq('mentor_id', mentorId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      print('✅ fetchInvitesForMentor: Found ${response.length} pending invites');
      return List<Map<String, dynamic>>.from(response);
    } catch (e, stack) {
      print('❌ Error fetching invites for mentor: $e');
      print(stack);
      return [];
    }
  }

  /// 🔹 FIXED: Accept or decline session invitation with better error handling
  Future<Map<String, dynamic>?> updateSessionStatus(String inviteId, bool accept) async {
    try {
      print('🟡 updateSessionStatus: Updating invite $inviteId to ${accept ? 'accepted' : 'declined'}');
      
      final newStatus = accept ? 'accepted' : 'declined';

      // 1️⃣ Update invitation
      final updated = await _supabase
          .from('live_invitations')
          .update({
            'status': newStatus,
            'responded_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', inviteId)
          .select('session_id, mentor_id, mentee_id')
          .maybeSingle();

      if (updated == null || updated['session_id'] == null) {
        print('⚠️ updateSessionStatus: No session found for invite ID: $inviteId');
        return null;
      }

      final sessionId = updated['session_id'].toString();
      final mentorId = updated['mentor_id'].toString();
      final menteeId = updated['mentee_id'].toString();

      if (accept) {
        // 2️⃣ Update live_sessions status to live
        print('🟡 updateSessionStatus: Updating live session to active...');
        await _supabase
            .from('live_sessions')
            .update({
              'is_live': true,
              'waiting': false,
              'mentor_id': mentorId,
            })
            .eq('id', sessionId);

        // 3️⃣ Get room details for navigation
        final sessionDetails = await _supabase
            .from('live_sessions')
            .select('room_id, room:rooms(name, creator_id)')
            .eq('id', sessionId)
            .single();

        print('✅ updateSessionStatus: Invitation accepted and session updated');
        
        return {
          'sessionId': sessionId,
          'roomId': sessionDetails['room_id'].toString(),
          'roomName': sessionDetails['room']['name']?.toString() ?? 'Live Session',
          'menteeId': menteeId,
          'mentorId': mentorId,
        };
      } else {
        // If declined, just update the invitation status
        print('✅ updateSessionStatus: Invitation declined');
        return {
          'sessionId': sessionId,
          'status': 'declined',
        };
      }
    } catch (e, stack) {
      print('❌ Error updating session status: $e');
      print(stack);
      return null;
    }
  }

  /// 🔹 FIXED: Fetch saved code from a session
  Future<String> fetchSessionCode(String sessionId) async {
    try {
      print('🟡 fetchSessionCode: Fetching code for session: $sessionId');
      
      final response = await _supabase
          .from('live_sessions')
          .select('code, language')
          .eq('id', sessionId)
          .maybeSingle();

      if (response == null || response['code'] == null) {
        print('⚠️ fetchSessionCode: No code found for session: $sessionId');
        return '// No code yet\n// Start coding...';
      }

      final code = response['code'] as String;
      final language = response['language'] as String? ?? 'python';
      
      print('✅ fetchSessionCode: Retrieved ${code.length} characters of $language code');
      return code;
    } catch (e, stack) {
      print('❌ Error fetching session code: $e');
      print(stack);
      return '// Error loading code\n// Please try again...';
    }
  }

  /// 🔹 NEW: Update session code
  Future<bool> updateSessionCode(String sessionId, String code, String language) async {
    try {
      print('🟡 updateSessionCode: Updating code for session: $sessionId');
      
      await _supabase
          .from('live_sessions')
          .update({
            'code': code,
            'language': language,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', sessionId);

      print('✅ updateSessionCode: Code updated successfully');
      return true;
    } catch (e, stack) {
      print('❌ Error updating session code: $e');
      print(stack);
      return false;
    }
  }

  /// 🔹 NEW: Check if user is mentor
  Future<bool> isUserMentor(String userId) async {
    try {
      final response = await _supabase
          .from('profiles_new')
          .select('role')
          .eq('id', userId)
          .maybeSingle();

      return response?['role'] == 'mentor';
    } catch (e) {
      print('❌ Error checking user role: $e');
      return false;
    }
  }

  /// 🔹 NEW: Get live session details
  Future<Map<String, dynamic>?> getLiveSession(String sessionId) async {
    try {
      final response = await _supabase
          .from('live_sessions')
          .select('''
            *,
            room:rooms(name, creator_id),
            mentee:profiles_new!live_sessions_mentee_id_fkey(username, avatar_url),
            mentor:profiles_new!live_sessions_mentor_id_fkey(username, avatar_url)
          ''')
          .eq('id', sessionId)
          .maybeSingle();

      return response;
    } catch (e, stack) {
      print('❌ Error fetching live session: $e');
      print(stack);
      return null;
    }
  }
}