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
    } catch (e) {
      print('❌ Error fetching mentors: $e');
      return [];
    }
  }

  /// 🔹 Create live session and invitation
  Future<String?> createLiveSession(
    String menteeId,
    String mentorId,
    String code,
  ) async {
    try {
      // 1️⃣ Fetch mentee username
      final profileRes =
          await _supabase
              .from('profiles')
              .select('username')
              .eq('id', menteeId)
              .single();

      final menteeName = profileRes['username'] ?? 'Unknown';

      // 2️⃣ Create new live session
      final sessionRes =
          await _supabase
              .from('live_sessions')
              .insert({
                'mentee_id': menteeId,
                'mentor_id': mentorId,
                'code': code,
                'is_live': false,
                'waiting': true,
              })
              .select('id')
              .single();

      final sessionId = sessionRes['id'] as String?;

      // 3️⃣ Create corresponding invitation
      if (sessionId != null) {
        await _supabase.from('live_invitations').insert({
          'session_id': sessionId,
          'mentor_id': mentorId,
          'mentee_id': menteeId,
          'mentee_name': menteeName,
          'status': 'pending',
        });
      }

      print('✅ Live session + invite created for $menteeName');
      return sessionId;
    } catch (e) {
      print('❌ Error creating live session: $e');
      return null;
    }
  }

  /// 🔹 Fetch all pending invites for mentor
  Future<List<Map<String, dynamic>>> fetchInvitesForMentor(
    String mentorId,
  ) async {
    try {
      final response = await _supabase
          .from('live_invitations')
          .select('id, session_id, mentee_name, status, created_at')
          .eq('mentor_id', mentorId)
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      print('✅ Mentor invites fetched: $response');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching invites for mentor: $e');
      return [];
    }
  }

  /// 🔹 Accept or decline session invitation
  Future<String?> updateSessionStatus(String inviteId, bool accept) async {
    try {
      final newStatus = accept ? 'accepted' : 'declined';

      // Update invitation row
      await _supabase
          .from('live_invitations')
          .update({'status': newStatus})
          .eq('id', inviteId);

      // Get the corresponding session ID
      final invitation =
          await _supabase
              .from('live_invitations')
              .select('session_id')
              .eq('id', inviteId)
              .maybeSingle();

      final sessionId = invitation?['session_id'] as String?;

      if (sessionId != null) {
        await _supabase
            .from('live_sessions')
            .update({'is_live': accept, 'waiting': !accept})
            .eq('id', sessionId);
      }

      return sessionId; // ✅ Return session ID
    } catch (e) {
      print('❌ Error updating session status: $e');
      return null;
    }
  }

  /// 🔹 Fetch saved code from session (for Collab editor)
  Future<String> fetchSessionCode(String sessionId) async {
    try {
      final response =
          await _supabase
              .from('live_sessions')
              .select('code')
              .eq('id', sessionId)
              .maybeSingle();

      if (response == null ||
          response['code'] == null ||
          response['code'] == 'mentee') {
        return '';
      }

      return response['code'] as String;
    } catch (e) {
      print('❌ Error fetching code: $e');
      return '';
    }
  }
}
