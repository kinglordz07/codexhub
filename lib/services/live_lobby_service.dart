// ignore_for_file: avoid_print

import 'package:supabase_flutter/supabase_flutter.dart';

class LiveLobbyService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> fetchMentors() async {
    try {
      print('🟡 fetchMentors: Fetching mentors from profiles_new...');
      
      final response = await _supabase
          .from('profiles_new')
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


  Future<Map<String, dynamic>?> createLiveSession(
    String menteeId,
    String mentorId,
    String menteeName, 
    {String message = ''}
  ) async {
    try {
      print('🟡 createLiveSession: Starting for mentee: $menteeId, mentor: $mentorId');

      String finalMenteeName = menteeName;
      if (menteeName.isEmpty) {
        print('🟡 createLiveSession: Fetching mentee name from profiles_new...');
        final profileRes = await _supabase
            .from('profiles_new')
            .select('username')
            .eq('id', menteeId)
            .maybeSingle();
        
        finalMenteeName = profileRes?['username'] ?? 'Mentee';
        print('🟢 createLiveSession: Found mentee name: $finalMenteeName');
      }


      final roomName = 'Live Session with $finalMenteeName';

      print('🟡 createLiveSession: Creating room...');
      final insertedRoom = await _supabase
          .from('rooms')
          .insert({
            'name': roomName,
            'creator_id': menteeId,
            'is_public': false, 
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
            'is_live': true, 
            'language': 'python',
            'waiting': false, 
          })
          .select('id')
          .single();
      
      print('🟢 createLiveSession: Live session created: ${sessionRes['id']}');

      final sessionId = sessionRes['id']?.toString();
      if (sessionId == null) {
        print('🔴 createLiveSession: Session insert returned null ID');
        return null;
      }

      print('🟡 createLiveSession: Creating invitation...');
      await _supabase.from('live_invitations').insert({
        'session_id': sessionId,
        'mentor_id': mentorId,
        'mentee_id': menteeId,
        'mentee_name': finalMenteeName,
        'message': message,
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

  Future<Map<String, dynamic>?> updateExistingRoomSession(
    String existingRoomId,
    String menteeId,
    String mentorId,
    String roomName, {
    String message = '',
  }) async {
    try {
      print('🔄 updateExistingRoomSession: Updating existing room session: $existingRoomId');
      
      final room = await _supabase
          .from('rooms')
          .select()
          .eq('id', existingRoomId)
          .maybeSingle();

      if (room == null) {
        throw Exception('Room not found: $existingRoomId');
      }

      final existingSession = await _supabase
          .from('live_sessions')
          .select()
          .eq('room_id', existingRoomId)
          .maybeSingle();

      String sessionId;

      if (existingSession != null) {

        sessionId = existingSession['id'].toString();
        
        await _supabase
            .from('live_sessions')
            .update({
              'mentee_id': menteeId,
              'mentor_id': mentorId,
              'is_live': false,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            })
            .eq('id', sessionId);
            
        print('✅ updateExistingRoomSession: Updated existing session: $sessionId');
      } else {

        final newSession = await _supabase
            .from('live_sessions')
            .insert({
              'room_id': existingRoomId,
              'mentee_id': menteeId,
              'mentor_id': mentorId,
              'is_live': false,
              'code': '// Welcome to collaboration room!\n// Start coding...',
              'language': 'python',
              'created_at': DateTime.now().toUtc().toIso8601String(),
            })
            .select()
            .single();
            
        sessionId = newSession['id'].toString();
        print('✅ updateExistingRoomSession: Created new session in existing room: $sessionId');
      }

      final existingMembership = await _supabase
          .from('room_members')
          .select()
          .eq('room_id', existingRoomId)
          .eq('user_id', menteeId)
          .maybeSingle();

      if (existingMembership == null) {
        await _supabase.from('room_members').insert({
          'room_id': existingRoomId,
          'user_id': menteeId,
        });
        print('✅ updateExistingRoomSession: Added mentee to room members');
      }

      print('🟡 updateExistingRoomSession: Creating invitation...');
      await _supabase.from('live_invitations').insert({
        'session_id': sessionId,
        'mentor_id': mentorId,
        'mentee_id': menteeId,
        'mentee_name': roomName.replaceAll('Live Session with ', ''),
        'message': message,
        'status': 'pending',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (message.isNotEmpty) {
        await _supabase.from('room_messages').insert({
          'room_id': existingRoomId,
          'user_id': menteeId,
          'content': 'Invitation to mentor: $message',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      }

      print('✅ updateExistingRoomSession: Successfully updated existing room session');

      return {
        'roomId': existingRoomId,
        'roomName': roomName,
        'sessionId': sessionId,
        'menteeId': menteeId,
        'mentorId': mentorId,
      };
    } catch (e, stack) {
      print('❌ Error updating existing room session: $e');
      print('Stack trace: $stack');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getMentorProfile(String mentorId) async {
    try {
      print('🟡 getMentorProfile: Fetching profile for mentor: $mentorId');
      
      final response = await _supabase
          .from('profiles_new') 
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

  Future<List<Map<String, dynamic>>> fetchInvitesForMentor(String mentorId) async {
    try {
      print('🟡 fetchInvitesForMentor: Fetching invites for mentor: $mentorId');
      
      final response = await _supabase
          .from('live_invitations')
          .select('*')
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

  Future<Map<String, dynamic>?> updateSessionStatus(String inviteId, bool accept) async {
    try {
      print('🟡 updateSessionStatus: Updating invite $inviteId to ${accept ? 'accepted' : 'declined'}');
      
      final newStatus = accept ? 'accepted' : 'declined';

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
        print('🟡 updateSessionStatus: Updating live session to active...');
        await _supabase
            .from('live_sessions')
            .update({
              'is_live': true,
              'waiting': false,
              'mentor_id': mentorId,
            })
            .eq('id', sessionId);

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