// ignore_for_file: avoid_print

import 'package:supabase_flutter/supabase_flutter.dart';

class LiveLobbyService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// 🔹 Fetch all mentors from profiles table
  Future<List<Map<String, dynamic>>> fetchMentors() async {
    try {
      final response = await _supabase
          .from('profiles')
          .select('id, username, email')
          .eq('role', 'mentor');

      return List<Map<String, dynamic>>.from(response);
    } catch (e, stack) {
      print('❌ Error fetching mentors: $e');
      print(stack);
      return [];
    }
  }

  /// 🔹 Create live session + invitation (UUID-friendly)
  Future<Map<String, String>?> createLiveSession(
    String menteeId,
    String mentorId,
    String roomName,
  ) async {
    try {
  print('🟡 createLiveSession: inserting room...');
      final insertedRoom = await _supabase
          .from('rooms')
          .insert({
            'name': roomName,
            'creator_id': menteeId,
            'is_public': true,
            'description': '',
          })
          .select()
          .single();
  print('🟢 createLiveSession: insertedRoom = $insertedRoom');

      final roomId = insertedRoom['id']?.toString();
      if (roomId == null) {
  print('🔴 createLiveSession: Room insert returned null ID');
        return null;
      }

  print('🟡 createLiveSession: fetching mentee username...');
      final profileRes = await _supabase
          .from('profiles')
          .select('username')
          .eq('id', menteeId)
          .single();
  print('🟢 createLiveSession: profileRes = $profileRes');

      final menteeName = profileRes['username'] ?? 'Unknown';

  print('🟡 createLiveSession: inserting live session...');
      final sessionRes = await _supabase
          .from('live_sessions')
          .insert({
            'room_id': roomId,
            'mentee_id': menteeId,
            'mentor_id': mentorId,
            'code': '',
            'is_live': false,
            'language': 'python',
            'waiting': true,
          })
          .select('id')
          .single();
  print('🟢 createLiveSession: sessionRes = $sessionRes');

      final sessionId = sessionRes['id']?.toString();
      if (sessionId == null) {
  print('🔴 createLiveSession: Session insert returned null ID');
        return null;
      }

  print('🟡 createLiveSession: inserting invitation...');
      final inviteRes = await _supabase.from('live_invitations').insert({
        'session_id': sessionId,
        'mentor_id': mentorId,
        'mentee_id': menteeId,
        'mentee_name': menteeName,
        'status': 'pending',
      });
  print('🟢 createLiveSession: inviteRes = $inviteRes');

  print('✅ Room, live session, and invitation created for $menteeName');
      return {
        'sessionId': sessionId,
        'roomId': roomId,
        'roomName': roomName,
      };
    } catch (e, stack) {
  print('❌ Error creating live session: $e');
  print('$stack');
      return null;
    }
  }

  /// 🔹 Fetch all pending invites for a mentor (UUID-safe)
  Future<List<Map<String, dynamic>>> fetchInvitesForMentor(String mentorId) async {
    try {
      final response = await _supabase
          .from('live_invitations')
          .select('id, session_id, mentee_name, status, created_at')
          .eq('mentor_id', mentorId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      print('✅ Mentor invites fetched successfully');
      return List<Map<String, dynamic>>.from(response);
    } catch (e, stack) {
      print('❌ Error fetching invites for mentor: $e');
      print(stack);
      return [];
    }
  }

  /// 🔹 Accept or decline session invitation (UUID-safe)
  Future<String?> updateSessionStatus(String inviteId, bool accept) async {
    try {
      final newStatus = accept ? 'accepted' : 'declined';

      // 1️⃣ Update invitation
      final updated = await _supabase
          .from('live_invitations')
          .update({'status': newStatus})
          .eq('id', inviteId)
          .select('session_id')
          .maybeSingle();

      if (updated == null || updated['session_id'] == null) {
        print('⚠️ No session found for invite ID: $inviteId');
        return null;
      }

      final sessionId = updated['session_id'].toString();

      // 2️⃣ Update live_sessions status
      await _supabase
          .from('live_sessions')
          .update({'is_live': accept, 'waiting': !accept})
          .eq('id', sessionId);

      print('✅ Invitation $newStatus and session updated');
      return sessionId;
    } catch (e, stack) {
      print('❌ Error updating session status: $e');
      print(stack);
      return null;
    }
  }

  /// 🔹 Fetch saved code from a session (for Collab Editor)
  Future<String> fetchSessionCode(String sessionId) async {
    try {
      final response = await _supabase
          .from('live_sessions')
          .select('code')
          .eq('id', sessionId)
          .maybeSingle();

      if (response == null || response['code'] == null) {
        return '';
      }

      return response['code'] as String;
    } catch (e, stack) {
      print('❌ Error fetching session code: $e');
      print(stack);
      return '';
    }
  }
}
