// call_services.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CallService {
  final supabase = Supabase.instance.client;
  final Map<String, Timer> _missedCallTimers = {};
  final Map<String, StreamSubscription> _activeSubscriptions = {};

  /// 🔹 Start a call - WITH UPDATED SCHEMA
  Future<String> startCall({
    required String callerId,
    required String receiverId,
    required String callType, // 'audio' or 'video'
  }) async {
    debugPrint('📞 [startCall] Caller: $callerId → Receiver: $receiverId ($callType)');

    try {
      // ✅ Check if receiver already has a ringing call
      final existingCalls = await supabase
          .from('calls')
          .select()
          .eq('receiver_id', receiverId)
          .eq('status', 'ringing');

      if (existingCalls.isNotEmpty) {
        debugPrint('⚠️ [startCall] Receiver is already in another call');
        throw Exception("Receiver is already in another call");
      }

      // ✅ Get caller name from profiles_new table
      final currentUser = supabase.auth.currentUser;
      String callerName = 'Unknown User';

      if (currentUser?.id != null) {
        try {
          final userProfile = await supabase
              .from('profiles_new')
              .select('username')
              .eq('id', currentUser!.id)
              .maybeSingle()
              .catchError((_) => null);

          callerName = userProfile?['username'] ?? 'Unknown User';
          debugPrint('👤 [startCall] Found caller name: $callerName');
        } catch (e) {
          debugPrint('⚠️ [startCall] Error fetching user profile: $e');
          callerName = 'Unknown User';
        }
      }

      // ✅ Insert new call - WITH UPDATED SCHEMA
      final response = await supabase.from('calls').insert({
        'caller_id': callerId,
        'receiver_id': receiverId,
        'status': 'ringing',
        'call_type': callType,
        'caller_name': callerName,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'accepted_at': null, // Will be set when call is accepted
        'ended_at': null, // Will be set when call ends
      }).select('id').single();

      final callID = response['id'] as String;
      debugPrint('✅ [startCall] Call created successfully: $callID');

      // 🔹 Start missed call timer (30 seconds)
      _startMissedCallTimer(callID);

      return callID;
    } catch (e, stack) {
      debugPrint('❌ [startCall] Error starting call: $e');
      debugPrint('Stack trace: $stack');
      rethrow;
    }
  }

  /// 🔹 Automatically marks a call as "missed" after 30 seconds if still ringing
  void _startMissedCallTimer(String callID) {
    debugPrint('⏳ [missedCallTimer] Timer started for call $callID');
    
    _missedCallTimers[callID]?.cancel();
    
    _missedCallTimers[callID] = Timer(const Duration(seconds: 30), () async {
      try {
        final result = await supabase
            .from('calls')
            .select('status')
            .eq('id', callID)
            .maybeSingle();

        if (result != null && result['status'] == 'ringing') {
          await supabase
              .from('calls')
              .update({
                'status': 'missed',
                'ended_at': DateTime.now().toUtc().toIso8601String(),
              })
              .eq('id', callID);
          debugPrint('📵 [missedCallTimer] Call $callID marked as missed');
        }
        
        _missedCallTimers.remove(callID);
      } catch (e) {
        debugPrint('⚠️ [missedCallTimer] Error updating missed call: $e');
        _missedCallTimers.remove(callID);
      }
    });
  }

  /// 🔹 Accept call - WITH accepted_at TIMESTAMP
  Future<void> acceptCall(String callID) async {
    debugPrint('✅ [acceptCall] Accepting call ID: $callID');
    
    try {
      _missedCallTimers[callID]?.cancel();
      _missedCallTimers.remove(callID);
      
      await supabase.from('calls').update({
        'status': 'accepted',
        'accepted_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', callID);
      
      debugPrint('✅ [acceptCall] Call $callID accepted successfully');
    } catch (e, stack) {
      debugPrint('❌ [acceptCall] Error accepting call: $e');
      debugPrint('Stack trace: $stack');
      rethrow;
    }
  }

  /// 🔹 Decline call - WITH ended_at TIMESTAMP
  Future<void> declineCall(String callID) async {
    debugPrint('🚫 [declineCall] Declining call ID: $callID');
    
    try {
      _missedCallTimers[callID]?.cancel();
      _missedCallTimers.remove(callID);
      
      await supabase.from('calls').update({
        'status': 'declined',
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', callID);
      
      debugPrint('✅ [declineCall] Call $callID declined successfully');
    } catch (e, stack) {
      debugPrint('❌ [declineCall] Error declining call: $e');
      debugPrint('Stack trace: $stack');
      rethrow;
    }
  }

  /// 🔹 End call - WITH ended_at TIMESTAMP
  Future<void> endCall(String callID) async {
    debugPrint('🛑 [endCall] Ending call ID: $callID');
    
    try {
      _missedCallTimers[callID]?.cancel();
      _missedCallTimers.remove(callID);
      
      await supabase.from('calls').update({
        'status': 'ended',
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', callID);
      
      debugPrint('✅ [endCall] Call $callID ended successfully');
    } catch (e, stack) {
      debugPrint('❌ [endCall] Error ending call: $e');
      debugPrint('Stack trace: $stack');
      rethrow;
    }
  }

  /// 🔹 Listen to incoming calls for a user
  Stream<List<Map<String, dynamic>>> listenIncomingCalls(String userId) {
    debugPrint('👂 [listenIncomingCalls] Listening for calls for user: $userId');

    return supabase
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', userId)
        .order('created_at', ascending: false)
        .map((events) {
          debugPrint('📡 [listenIncomingCalls] ${events.length} call(s) received');
          
          // Filter only ringing calls
          return events
              .where((call) => call['status'] == 'ringing')
              .map<Map<String, dynamic>>((call) => _formatCallData(call))
              .toList();
        });
  }

  /// 🔹 Format call data with new timestamp fields
  Map<String, dynamic> _formatCallData(Map<String, dynamic> call) {
    return {
      'id': call['id'],
      'caller_id': call['caller_id'],
      'receiver_id': call['receiver_id'],
      'status': call['status'],
      'call_type': call['call_type'],
      'caller_name': call['caller_name'],
      'created_at': call['created_at'],
      'accepted_at': call['accepted_at'], // New field
      'ended_at': call['ended_at'], // New field
    };
  }

  /// 🔹 Get call history for a user with duration calculation
  Future<List<Map<String, dynamic>>> getCallHistory(String userId) async {
    debugPrint('📚 [getCallHistory] Getting call history for user: $userId');
    
    try {
      final calls = await supabase
          .from('calls')
          .select()
          .or('caller_id.eq.$userId,receiver_id.eq.$userId')
          .order('created_at', ascending: false)
          .limit(50);

      debugPrint('✅ [getCallHistory] Retrieved ${calls.length} calls');
      
      // Calculate call duration for ended calls
      final enrichedCalls = calls.map((call) {
        final callData = _formatCallData(call);
        
        // Calculate duration if call has ended
        if (call['ended_at'] != null && call['accepted_at'] != null) {
          try {
            final acceptedAt = DateTime.parse(call['accepted_at']);
            final endedAt = DateTime.parse(call['ended_at']);
            final duration = endedAt.difference(acceptedAt);
            
            callData['duration_seconds'] = duration.inSeconds;
            callData['duration_formatted'] = _formatDuration(duration);
          } catch (e) {
            debugPrint('⚠️ Error calculating call duration: $e');
          }
        }
        
        return callData;
      }).toList();

      return enrichedCalls;
    } catch (e) {
      debugPrint('❌ [getCallHistory] Error getting call history: $e');
      rethrow;
    }
  }

  /// 🔹 Format duration for display
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    
    if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }

  /// 🔹 Get call statistics for a user
  Future<Map<String, dynamic>> getCallStats(String userId) async {
    debugPrint('📊 [getCallStats] Getting call stats for user: $userId');
    
    try {
      final calls = await supabase
          .from('calls')
          .select()
          .or('caller_id.eq.$userId,receiver_id.eq.$userId');

      int totalCalls = calls.length;
      int incomingCalls = calls.where((call) => call['receiver_id'] == userId).length;
      int outgoingCalls = calls.where((call) => call['caller_id'] == userId).length;
      int missedCalls = calls.where((call) => call['status'] == 'missed' && call['receiver_id'] == userId).length;
      int acceptedCalls = calls.where((call) => call['status'] == 'accepted').length;

      // Calculate total call time
      Duration totalCallTime = Duration.zero;
      for (final call in calls) {
        if (call['ended_at'] != null && call['accepted_at'] != null) {
          try {
            final acceptedAt = DateTime.parse(call['accepted_at']);
            final endedAt = DateTime.parse(call['ended_at']);
            totalCallTime += endedAt.difference(acceptedAt);
          } catch (e) {
            debugPrint('⚠️ Error calculating call time: $e');
          }
        }
      }

      return {
        'total_calls': totalCalls,
        'incoming_calls': incomingCalls,
        'outgoing_calls': outgoingCalls,
        'missed_calls': missedCalls,
        'accepted_calls': acceptedCalls,
        'total_call_time_seconds': totalCallTime.inSeconds,
        'total_call_time_formatted': _formatDuration(totalCallTime),
      };
    } catch (e) {
      debugPrint('❌ [getCallStats] Error getting call stats: $e');
      rethrow;
    }
  }

  /// 🔹 Get specific call details
  Future<Map<String, dynamic>?> getCallDetails(String callID) async {
    debugPrint('🔍 [getCallDetails] Getting details for call: $callID');
    
    try {
      final call = await supabase
          .from('calls')
          .select()
          .eq('id', callID)
          .maybeSingle();

      if (call != null) {
        debugPrint('✅ [getCallDetails] Call details retrieved');
        return _formatCallData(call);
      } else {
        debugPrint('⚠️ [getCallDetails] Call not found: $callID');
        return null;
      }
    } catch (e) {
      debugPrint('❌ [getCallDetails] Error getting call details: $e');
      rethrow;
    }
  }

  /// 🔹 Listen to updates for a specific call ID
  Stream<Map<String, dynamic>?> listenCallStatus(String callID) {
    debugPrint('🔄 [listenCallStatus] Listening for updates on call ID: $callID');
    
    return supabase
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('id', callID)
        .map((events) {
          if (events.isEmpty) return null;
          
          final call = events.first;
          debugPrint('➡️ [listenCallStatus] Call Update: ${call['status']}');
          return _formatCallData(call);
        });
  }

  /// 🔹 Cleanup specific call resources
  void cleanupCall(String callID) {
    _missedCallTimers[callID]?.cancel();
    _missedCallTimers.remove(callID);
    
    _activeSubscriptions[callID]?.cancel();
    _activeSubscriptions.remove(callID);
    
    debugPrint('🧹 [cleanupCall] Cleaned up resources for call: $callID');
  }

  /// 🔹 Cleanup all resources
  void dispose() {
    debugPrint('🧹 [dispose] Cleaning up all call resources');
    
    _missedCallTimers.forEach((callID, timer) {
      timer.cancel();
    });
    _missedCallTimers.clear();
    
    _activeSubscriptions.forEach((callID, subscription) {
      subscription.cancel();
    });
    _activeSubscriptions.clear();
  }
}