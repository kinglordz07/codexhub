import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class CallService {
  final supabase = Supabase.instance.client;

  /// 🔹 Start a call, returns callID
  Future<String> startCall({
    required String callerId,
    required String receiverId,
    required String callType, // "audio" or "video"
  }) async {
    // Insert call
    final response = await supabase.from('calls').insert({
      'caller_id': callerId,
      'receiver_id': receiverId,
      'status': 'ringing',
      'call_type': callType,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    }).select('id').single();

    // Return the generated call ID
    return response['id'] as String;
  }

  /// 🔹 Listen to incoming calls for a user
  Stream<List<Map<String, dynamic>>> listenIncomingCalls(String userId) {
    return supabase
        .from('calls:receiver_id=eq.$userId')
        .stream(primaryKey: ['id'])
        .map((event) => event
            .where((c) => c['status'] == 'ringing')
            .map<Map<String, dynamic>>((e) => e)
            .toList());
  }

  /// 🔹 Accept call
  Future<void> acceptCall(Map<String, dynamic> call) async {
    await supabase
        .from('calls')
        .update({'status': 'accepted'})
        .eq('id', call['id']);
  }

  /// 🔹 Decline call
  Future<void> declineCall(Map<String, dynamic> call) async {
    await supabase
        .from('calls')
        .update({'status': 'declined'})
        .eq('id', call['id']);
  }

  /// 🔹 Listen to call status (for caller)
  Stream<List<Map<String, dynamic>>> listenCallStatus(String callID) {
    return supabase
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('id', callID)
        .map((event) => event.toList());
  }

  /// 🔹 Optional: Cancel a call (if caller hangs up before accepted)
  Future<void> cancelCall(String callID) async {
    await supabase.from('calls').update({'status': 'cancelled'}).eq('id', callID);
  }
}
