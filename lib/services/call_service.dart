import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

/// Singleton CallService
class CallService {
  CallService._internal();
  static final CallService instance = CallService._internal();

  final SupabaseClient supabase = Supabase.instance.client;
  final Set<String> _seenCalls = {}; // IDs of handled calls
  CallService(); 
  final Queue<Map<String, dynamic>> _callQueue = Queue(); // queued calls
  bool _isShowing = false;

  StreamSubscription? _callSub;

  String? get currentProfileId => supabase.auth.currentUser?.id;

  /// --------------------------
  /// FCM TOKEN METHODS
  /// --------------------------
  Future<void> saveFcmToken(String token, String platform) async {
    final profileId = currentProfileId;
    if (profileId == null) return;

    await supabase.from('fcm_tokens').upsert(
      {
        'profile_id': profileId,
        'token': token,
        'platform': platform,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'fcm_tokens_profile_token_unique',
    );
  }

  Future<List<String>> getFcmTokens(String receiverId) async {
    final List<Map<String, dynamic>> tokens = await supabase
        .from('fcm_tokens')
        .select('token')
        .eq('profile_id', receiverId);

    return tokens.map((t) => t['token'] as String).toList();
  }

  /// --------------------------
  /// CALL METHODS
  /// --------------------------
  Future<void> startCall(String receiverId, String callType) async {
    final userId = currentProfileId;
    if (userId == null) throw Exception('User not logged in');

    // Insert call in database
    await supabase.from('calls').insert({
      'caller_id': userId,
      'receiver_id': receiverId,
      'call_type': callType,
      'status': 'ringing',
      'ice_candidates': jsonEncode([]),
      'created_at': DateTime.now().toIso8601String(),
    }).select().maybeSingle();

    // Fetch caller username
    final profile = await supabase
        .from('profiles')
        .select('username')
        .eq('id', userId)
        .maybeSingle();
    final callerUsername = profile?['username'] ?? 'Unknown';

    // Send push notification
    final tokens = await getFcmTokens(receiverId);
    for (var token in tokens) {
      await _sendFcmNotification(
        token,
        title: 'Incoming $callType Call',
        body: 'From: $callerUsername',
      );
    }
  }

  Future<void> _sendFcmNotification(String token,
      {required String title, required String body}) async {
    final serverKey = 'YOUR_FIREBASE_SERVER_KEY'; // Replace with your FCM server key
    final url = Uri.parse('https://fcm.googleapis.com/fcm/send');

    await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'key=$serverKey',
      },
      body: jsonEncode({
        'to': token,
        'notification': {'title': title, 'body': body},
        'priority': 'high',
      }),
    );
  }

  /// --------------------------
  /// REALTIME LISTENER
  /// --------------------------
  void listenToCallsGlobal(BuildContext context) {
    final userId = currentProfileId;
    if (userId == null) return;

    _callSub = supabase
        .from('calls:receiver_id=eq.$userId')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .listen((rows) {
      final newCalls = rows.where((r) =>
          r['status'] == 'ringing' && !_seenCalls.contains(r['id'].toString()));
      for (var call in newCalls) {
        _enqueueCall(context, call);
      }
    });
  }

  void _enqueueCall(BuildContext context, Map<String, dynamic> call) {
    if (!_seenCalls.contains(call['id'].toString())) {
      _callQueue.add(call);
      _showNextCallDialog(context);
    }
  }

  Future<void> _showNextCallDialog(
      BuildContext context) async {
    if (_isShowing || _callQueue.isEmpty) return;
    _isShowing = true;

    final call = _callQueue.removeFirst();
    final callerId = call['caller_id'] as String?;
    String callerUsername = 'Unknown';

    if (callerId != null) {
      final profile = await supabase
          .from('profiles')
          .select('username')
          .eq('id', callerId)
          .maybeSingle();
      if (profile != null) callerUsername = profile['username'] ?? 'Unknown';
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text("Incoming ${call['call_type']} call"),
        content: Text("From: $callerUsername"),
        actions: [
          TextButton(
            onPressed: () async {
              await updateCallStatus(call['id'], 'declined');
              _seenCalls.add(call['id'].toString());
              Navigator.pop(context);
              _isShowing = false;
              _showNextCallDialog(context);
            },
            child: const Text("Decline"),
          ),
          ElevatedButton(
            onPressed: () async {
              await updateCallStatus(call['id'], 'accepted');
              _seenCalls.add(call['id'].toString());
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      "You accepted the ${call['call_type']} call from $callerUsername."),
                ),
              );
              _isShowing = false;
              _showNextCallDialog(context);
            },
            child: const Text("Accept"),
          ),
        ],
      ),
    );
  }

  Future<void> updateCallStatus(String callId, String status) async {
    await supabase.from('calls').update({'status': status}).eq('id', callId);
  }

  void dispose() {
    _callSub?.cancel();
  }
}
