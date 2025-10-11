// lib/services/sessionservice.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionService {
  final _supabase = Supabase.instance.client;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  /// Student schedules a session
  Future<void> scheduleSession({
    required String mentorId,
    required String userId,
    required String sessionType,
    required DateTime date,
    required String timeString,
    required String notes,
  }) async {
    await _supabase.from('mentor_sessions').insert({
      'mentor_id': mentorId,
      'user_id': userId,
      'session_type': sessionType,
      'session_date':
          DateTime(
            date.year,
            date.month,
            date.day,
          ).toIso8601String().split('T').first, // ✅ stable yyyy-MM-dd
      'session_time': timeString, // ✅ always "HH:mm"
      'notes': notes,
      'status': 'pending',
    });
  }

  /// Mentor gets all sessions assigned to them (with student username)
  Future<List<Map<String, dynamic>>> getMentorSessions() async {
    final mentorId = currentUserId;
    if (mentorId == null) return [];

    final response = await _supabase
        .from('mentor_sessions')
        .select('''
          id,
          user_id,
          session_type,
          session_date,
          session_time,
          notes,
          status,
          profiles!mentor_sessions_user_id_fkey(username)
        ''')
        .eq('mentor_id', mentorId)
        .order('session_date', ascending: true);

    return List<Map<String, dynamic>>.from(response);
  }

  /// Mentor updates status (accept/decline) of a session
  Future<void> updateSessionStatus(String sessionId, String newStatus) async {
    await _supabase
        .from('mentor_sessions')
        .update({'status': newStatus})
        .eq('id', sessionId);
  }
}
