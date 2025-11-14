// lib/services/sessionservice.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SessionService {
  final _supabase = Supabase.instance.client;

  String? get currentUserId => _supabase.auth.currentUser?.id;

  Future<void> scheduleSession({
    required String mentorId,
    required String userId,
    required String sessionType,
    required DateTime date,
    required String timeString,
    required String notes,
  }) async {
    try {
      // Insert the session
      final response = await _supabase
          .from('mentor_sessions')
          .insert({
            'mentor_id': mentorId,
            'user_id': userId,
            'session_type': sessionType,
            'session_date': DateTime(date.year, date.month, date.day)
                .toIso8601String()
                .split('T')
                .first,
            'session_time': timeString,
            'notes': notes,
            'status': 'pending',
          })
          .select()
          .single();

      final studentProfile = await _supabase
          .from('profiles_new')
          .select('username')
          .eq('id', userId)
          .single();

      final studentName = studentProfile['username'] ?? 'Student';
      
      debugPrint('🎯 Sending notification to mentor: $mentorId');
      
      // Send notification to mentor
      await _sendNewSessionNotificationToMentor(
        mentorId: mentorId,
        studentName: studentName,
        sessionType: sessionType,
        sessionId: response['id'],
      );

    } catch (e) {
      debugPrint('Error scheduling session: $e');
      rethrow;
    }
  }

  Future<void> _sendNewSessionNotificationToMentor({
    required String mentorId,
    required String studentName,
    required String sessionType,
    required String sessionId,
  }) async {
    try {
      // Create a real-time notification channel for the mentor
      final channel = _supabase.channel('mentor_new_sessions_$mentorId');
      
      channel.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('✅ Mentor notification channel subscribed');
        }
      });

      await _supabase.from('notifications').insert({
        'user_id': mentorId,
        'title': 'New Session Request! 🎯',
        'message': '$studentName requested a $sessionType session',
        'type': 'new_session',
        'session_id': sessionId,
        'created_at': DateTime.now().toIso8601String(),
      });

      debugPrint('📨 Notification sent to mentor: $mentorId');

    } catch (e) {
      debugPrint('Error sending mentor notification: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getUserSessions() async {
    final userId = currentUserId;
    if (userId == null) return [];

    try {
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
            rescheduled_at,
            original_date,
            original_time,
            profiles_new!mentor_sessions_mentor_id_fkey(
              username
            )
          ''')
          .eq('user_id', userId)
          .order('session_date', ascending: true);

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
      
      final response = await _supabase
          .from('mentor_sessions')
          .select('*')
          .eq('user_id', userId)
          .order('session_date', ascending: true);
          
      return List<Map<String, dynamic>>.from(response.map((session) => {
        ...session,
        'mentor_name': 'Mentor', 
      }));
    }
  }

  Future<List<Map<String, dynamic>>> getActiveSessions() async {
    final userId = currentUserId;
    if (userId == null) return [];

    try {
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
            rescheduled_at,
            original_date,
            original_time,
            profiles_new!mentor_sessions_mentor_id_fkey(
              username
            )
          ''')
          .eq('user_id', userId)
          .filter('status', 'in', ['pending', 'accepted', 'confirmed'])
          .order('session_date', ascending: true);

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
      debugPrint('Error in getActiveSessions: $e');
      
      final response = await _supabase
          .from('mentor_sessions')
          .select('*')
          .eq('user_id', userId)
          .filter('status', 'in', ['pending', 'accepted', 'confirmed'])
          .order('session_date', ascending: true);
          
      return List<Map<String, dynamic>>.from(response.map((session) => {
        ...session,
        'mentor_name': 'Mentor',
      }));
    }
  }

  Future<List<Map<String, dynamic>>> getRescheduledSessions() async {
    final userId = currentUserId;
    if (userId == null) return [];

    try {
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
            rescheduled_at,
            original_date,
            original_time,
            profiles_new!mentor_sessions_mentor_id_fkey(
              username
            )
          ''')
          .eq('user_id', userId)
          .eq('status', 'rescheduled')
          .order('session_date', ascending: true);

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
      debugPrint('Error in getRescheduledSessions: $e');
      
      final response = await _supabase
          .from('mentor_sessions')
          .select('*')
          .eq('user_id', userId)
          .eq('status', 'rescheduled')
          .order('session_date', ascending: true);
          
      return List<Map<String, dynamic>>.from(response.map((session) => {
        ...session,
        'mentor_name': 'Mentor',
      }));
    }
  }

  Future<List<Map<String, dynamic>>> getCompletedSessions() async {
    final userId = currentUserId;
    if (userId == null) return [];

    try {
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
            rescheduled_at,
            original_date,
            original_time,
            completed_at,
            profiles_new!mentor_sessions_mentor_id_fkey(
              username
            )
          ''')
          .eq('user_id', userId)
          .filter('status', 'in', ['completed', 'declined', 'cancelled', 'rejected'])
          .order('session_date', ascending: false);

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
      debugPrint('Error in getCompletedSessions: $e');
      
      final response = await _supabase
          .from('mentor_sessions')
          .select('*')
          .eq('user_id', userId)
          .filter('status', 'in', ['completed', 'declined', 'cancelled', 'rejected'])
          .order('session_date', ascending: false);
          
      return List<Map<String, dynamic>>.from(response.map((session) => {
        ...session,
        'mentor_name': 'Mentor',
      }));
    }
  }

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
            original_date,
            original_time,
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
      
      return await _supabase
          .from('mentor_sessions')
          .select('*')
          .eq('mentor_id', mentorId)
          .order('session_date', ascending: true)
          .order('session_time', ascending: true);
    }
  }

  Future<void> updateSessionStatus(String sessionId, String newStatus) async {
    final mentorId = currentUserId;
    if (mentorId == null) return;

    try {
      // Get session details first for notification
      final sessionResponse = await _supabase
          .from('mentor_sessions')
          .select('''
            session_type,
            user_id,
            mentor_id,
            session_date,
            session_time,
            profiles_new!mentor_sessions_mentor_id_fkey(username)
          ''')
          .eq('id', sessionId)
          .single();

      final studentId = sessionResponse['user_id'];
      final mentorName = sessionResponse['profiles_new']?['username'] ?? 'Mentor';
      final sessionType = sessionResponse['session_type'] ?? 'session';
      final sessionDate = sessionResponse['session_date'];
      final sessionTime = sessionResponse['session_time'];

      debugPrint('🎯 Preparing to notify student: $studentId about status: $newStatus');

      // Update the status
      await _supabase
          .from('mentor_sessions')
          .update({'status': newStatus})
          .eq('id', sessionId);

      debugPrint('🔄 Status updated to: $newStatus');

      // Send notification to STUDENT when mentor accepts/declines
      if (newStatus == 'accepted' || newStatus == 'declined') {
        await _sendSessionStatusNotificationToStudent(
          studentId: studentId,
          mentorName: mentorName,
          status: newStatus,
          sessionType: sessionType,
          sessionId: sessionId,
          sessionDate: sessionDate,
          sessionTime: sessionTime,
        );
      }

    } catch (e) {
      debugPrint('Error updating session status: $e');
      rethrow;
    }
  }
  
  Future<void> _sendSessionStatusNotificationToStudent({
  required String studentId,
  required String mentorName,
  required String status,
  required String sessionType,
  required String sessionId,
  required String sessionDate,
  required String sessionTime,
}) async {
  try {
    debugPrint('🚀 SENDING NOTIFICATION TO STUDENT: $studentId');

    String title = status == 'accepted' 
        ? 'Session Accepted! 🎉' 
        : 'Session Declined';
    
    String message = status == 'accepted'
        ? '$mentorName accepted your $sessionType session on $sessionDate at $sessionTime'
        : '$mentorName declined your $sessionType session request';

    // Try database function first
    try {
      await _supabase.rpc('create_notification', params: {
        'p_user_id': studentId,
        'p_title': title,
        'p_message': message,
        'p_type': 'session_status',
        'p_session_id': sessionId,
      });
      debugPrint('✅ Notification sent via database function');
      return;
    } catch (e) {
      debugPrint('⚠️ Database function failed: $e');
    }

    // Fallback to direct insert
    try {
      await _supabase.from('notifications').insert({
        'user_id': studentId,
        'title': title,
        'message': message,
        'type': 'session_status',
        'session_id': sessionId,
        'created_at': DateTime.now().toIso8601String(),
      });
      debugPrint('✅ Notification sent via direct insert');
    } catch (e) {
      debugPrint('❌ All notification methods failed: $e');
      // You could add a fallback like sending an email or using a different notification service
    }

  } catch (e) {
    debugPrint('❌ Error in notification system: $e');
  }
}

  Future<void> rescheduleSession(
    String sessionId, 
    String newDate, 
    String newTime,
    String originalDate,
    String originalTime,
  ) async {
    await _supabase
        .from('mentor_sessions')
        .update({
          'session_date': newDate,
          'session_time': newTime,
          'status': 'rescheduled',
          'rescheduled_at': DateTime.now().toIso8601String(),
          'original_date': originalDate,
          'original_time': originalTime,
        })
        .eq('id', sessionId);
  }

  Future<void> completeSession(String sessionId) async {
    await _supabase
        .from('mentor_sessions')
        .update({
          'status': 'completed',
          'completed_at': DateTime.now().toIso8601String(),
        })
        .eq('id', sessionId);
  }
}