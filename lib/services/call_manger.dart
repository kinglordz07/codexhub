import 'dart:async';
import 'package:flutter/material.dart';
import 'call_services.dart';
import '../main.dart'; 
import '../services/call_screen.dart';

class CallManager {
  static CallManager? _instance;
  factory CallManager() => _instance ??= CallManager._internal();
  CallManager._internal();

  final CallService _callService = CallService();
  final ValueNotifier<Map<String, dynamic>?> _currentCall = ValueNotifier(null);
  final ValueNotifier<bool> _showNotification = ValueNotifier(false);
  StreamSubscription? _callSubscription;

  ValueNotifier<Map<String, dynamic>?> get currentCall => _currentCall;
  ValueNotifier<bool> get showNotification => _showNotification;

  // ✅ CORRECTED: This method should be called initializeCallListener
  void initializeCallListener() {
    final userId = _callService.supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('⚠️ No user ID for call listener');
      return;
    }

    _callSubscription = _callService.listenIncomingCalls(userId).listen((calls) {
      if (calls.isNotEmpty) {
        _handleIncomingCall(calls.first);
      }
    }, onError: (error) {
      debugPrint('❌ Error in call listener: $error');
    });
  }

  void _handleIncomingCall(Map<String, dynamic> callData) {
    debugPrint('📞 Incoming call received: ${callData['id']}');
    
    _currentCall.value = callData;
    _showNotification.value = true;
    
    // Auto-dismiss after 45 seconds if not answered
    Future.delayed(Duration(seconds: 45), () {
      if (_showNotification.value && _currentCall.value?['id'] == callData['id']) {
        _dismissNotification();
        debugPrint('⏰ Call notification auto-dismissed');
      }
    });
  }

  void _dismissNotification() {
    _currentCall.value = null;
    _showNotification.value = false;
  }

  // Start a call to another user
  Future<String> startCall({
    required String receiverId,
    required String callType,
  }) async {
    try {
      final callerId = _callService.supabase.auth.currentUser?.id;
      if (callerId == null) throw Exception('User not authenticated');

      final callId = await _callService.startCall(
        callerId: callerId,
        receiverId: receiverId,
        callType: callType,
      );

      return callId;
    } catch (e) {
      debugPrint('❌ Error starting call: $e');
      rethrow;
    }
  }

  // Accept incoming call
  Future<void> acceptCall() async {
    if (_currentCall.value == null) return;

    try {
      final callId = _currentCall.value!['id'];
      await _callService.acceptCall(callId);
      _dismissNotification();
      debugPrint('✅ Call accepted: $callId');
      _navigateToCallScreen(_currentCall.value!);
    } catch (e) {
      debugPrint('❌ Error accepting call: $e');
      rethrow;
    }
  }

  void _navigateToCallScreen(Map<String, dynamic> callData) {
   navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (context) => CallScreen(callData: callData),
    ),
  );
}

  // Decline incoming call
  Future<void> declineCall() async {
    if (_currentCall.value == null) return;

    try {
      final callId = _currentCall.value!['id'];
      await _callService.declineCall(callId);
      _dismissNotification();
      debugPrint('🚫 Call declined: $callId');
    } catch (e) {
      debugPrint('❌ Error declining call: $e');
      rethrow;
    }
  }

  // End active call
  Future<void> endCall(String callId) async {
    try {
      await _callService.endCall(callId);
      debugPrint('🛑 Call ended: $callId');
    } catch (e) {
      debugPrint('❌ Error ending call: $e');
      rethrow;
    }
  }

  // Get call history
  Future<List<Map<String, dynamic>>> getCallHistory() async {
    final userId = _callService.supabase.auth.currentUser?.id;
    if (userId == null) return [];
    
    return await _callService.getCallHistory(userId);
  }

  // Get call statistics
  Future<Map<String, dynamic>> getCallStats() async {
    final userId = _callService.supabase.auth.currentUser?.id;
    if (userId == null) return {};
    
    return await _callService.getCallStats(userId);
  }

  void dispose() {
    _callSubscription?.cancel();
    _callService.dispose();
    _currentCall.dispose();
    _showNotification.dispose();
  }
}