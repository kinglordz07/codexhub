// lib/services/sessionservice.dart
import 'package:flutter/material.dart';
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

  /// 🔹 FIXED: Fetch all sessions for the current mentee
  Future<List<Map<String, dynamic>>> getUserSessions() async {
    final userId = currentUserId;
    if (userId == null) return [];

    try {
      // Try different join approaches
      final response = await _supabase
          .from('mentor_sessions')
          .select('''
            id,
            session_type,
            session_date,
            session_time,
            notes,
            status,
            mentor_id,
            user_id,
            profiles_new!mentor_sessions_mentor_id_fkey(
              username
            )
          ''')
          .eq('user_id', userId)
          .order('session_date', ascending: true);

      // Manual mapping of mentor name
      return List<Map<String, dynamic>>.from(
        response.map((session) {
          final mentorData = session['profiles_new'];
          final mentorName = mentorData != null && mentorData is Map 
              ? mentorData['username'] 
              : 'Unknown Mentor';
              
          return {
            ...session,
            'mentor_name': mentorName,
          };
        }),
      );
    } catch (e) {
      debugPrint('Error in getUserSessions: $e');
      
      // Fallback: Simple query without join
      final response = await _supabase
          .from('mentor_sessions')
          .select('*')
          .eq('user_id', userId)
          .order('session_date', ascending: true);
          
      return List<Map<String, dynamic>>.from(response.map((session) => {
        ...session,
        'mentor_name': 'Mentor', // Fallback name
      }));
    }
  }

  /// FIXED: Mentor gets all sessions assigned to them
  Future<List<Map<String, dynamic>>> getMentorSessions() async {
    final mentorId = currentUserId;
    if (mentorId == null) return [];

    try {
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
            rescheduled_at,
            created_at,
            profiles_new!mentor_sessions_user_id_fkey(
              username
            )
          ''')
          .eq('mentor_id', mentorId)
          .order('session_date', ascending: true)
          .order('session_time', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error in getMentorSessions: $e');
      
      // Fallback
      return await _supabase
          .from('mentor_sessions')
          .select('*')
          .eq('mentor_id', mentorId)
          .order('session_date', ascending: true)
          .order('session_time', ascending: true);
    }
  }

  /// Mentor updates status (accept/decline) of a session
  Future<void> updateSessionStatus(String sessionId, String newStatus) async {
    await _supabase
        .from('mentor_sessions')
        .update({'status': newStatus})
        .eq('id', sessionId);
  }

  /// Mentor reschedules a session
  Future<void> rescheduleSession(String sessionId, String newDate, String newTime) async {
    await _supabase
        .from('mentor_sessions')
        .update({
          'session_date': newDate,
          'session_time': newTime,
          'status': 'rescheduled',
          'rescheduled_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId);
  }
}