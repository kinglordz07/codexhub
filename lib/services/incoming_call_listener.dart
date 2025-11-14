import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'notif.dart';

/// Supabase Realtime listener for incoming calls.
/// Subscribes to calls table and shows notifications when a new call arrives.
class IncomingCallListener {
  final SupabaseClient _supabase = Supabase.instance.client;
  RealtimeChannel? _subscription;
  bool _isListening = false;

  String? get currentUserId => _supabase.auth.currentUser?.id;


  Future<void> _showIncomingCallNotification({
    required String callId,
    required String callerName,
    required String callType,
  }) async {
    try {
      final id = callId.hashCode & 0x7fffffff;

      await NotificationService.showIncomingCallNotification(
        id: id,
        callerName: callerName,
        callType: callType,
        payload: callId,
      );
      
      debugPrint('🔔 Call notification triggered: $callerName ($callType)');
    } catch (e) {
      debugPrint('❌ Error triggering call notification: $e');
    }
  }

  /// Start listening for incoming calls for the current user
  /// Listens to mentor_sessions table for new sessions where user_id matches (student receiving session)
  Future<void> startListening(VoidCallback onCallReceived) async {
    if (_isListening || currentUserId == null) {
      debugPrint('⚠️ Already listening or no user logged in');
      return;
    }

    _isListening = true;
    final userId = currentUserId!;

    try {
      // Subscribe to mentor_sessions table for current user (as student/user_id)
      _subscription = _supabase.realtime.channel(
        'public:mentor_sessions:user_id=eq.$userId',
      );

      // Listen to INSERT events on mentor_sessions table
      // When a mentor creates a new session for this user
      _subscription!.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'mentor_sessions',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (payload) async {
          try {
            debugPrint('🎯🎯🎯 REALTIME CALLBACK FIRED!');
            debugPrint('📥 Realtime event: ${payload.eventType}');
            debugPrint('� Session data: ${payload.newRecord}');
            
            final newRecord = payload.newRecord;
            final status = newRecord['status']?.toString() ?? '';
            final sessionType = newRecord['session_type']?.toString() ?? 'audio';
            final mentorId = newRecord['mentor_id']?.toString();
            final sessionId = newRecord['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

            debugPrint('📋 Session Status: $status, Type: $sessionType, Mentor ID: $mentorId');

            // Show notification only for pending sessions (new incoming calls)
            if (status == 'pending' && mentorId != null) {
              // Get mentor name
              try {
                final mentorProfile = await _supabase
                    .from('profiles_new')
                    .select('username')
                    .eq('id', mentorId)
                    .single();

                final mentorName = mentorProfile['username'] ?? 'Mentor';
                
                await _showIncomingCallNotification(
                  callId: sessionId,
                  callerName: mentorName,
                  callType: sessionType,
                );

                debugPrint('✅ Incoming session notification shown for mentor: $mentorName');

                // Trigger callback (e.g., to update UI or show modal)
                onCallReceived();
              } catch (e) {
                debugPrint('❌ Error fetching mentor profile: $e');
              }
            }
          } catch (e, st) {
            debugPrint('❌ Error in session listener callback: $e');
            debugPrint('📍 Stack trace: $st');
          }
        },
      );

      // Subscribe to the channel
      _subscription!.subscribe((status, error) {
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('✅ Started listening for incoming sessions');
          debugPrint('🔍 Monitoring mentor_sessions for user: $userId');
        } else if (status == RealtimeSubscribeStatus.closed) {
          debugPrint('🛑 Session subscription closed');
          _isListening = false;
        }
        if (error != null) {
          debugPrint('❌ Session subscription error: $error');
          _isListening = false;
        }
      });
      
    } catch (e) {
      debugPrint('❌ Error starting session listener: $e');
      _isListening = false;
    }
  }

  /// Stop listening for incoming calls
  Future<void> stopListening() async {
    if (_subscription != null) {
      await _subscription!.unsubscribe();
      debugPrint('🛑 Stopped listening for incoming calls');
    }
    _isListening = false;
  }

  /// Check if currently listening
  bool get isListening => _isListening;

  /// Dispose resources
  void dispose() {
    stopListening();
  }
}