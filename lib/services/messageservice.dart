import 'dart:async';
import 'package:flutter/material.dart';
import 'notif.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessageService {
  final SupabaseClient supabase = Supabase.instance.client;
  final Set<String> _seenMessageIds = {};

  String? get currentUserId => supabase.auth.currentUser?.id;

  Future<List<Map<String, dynamic>>> getMessages(String otherUserId) async {
    final userId = currentUserId;
    if (userId == null) return [];

    final data = await supabase
        .from('mentor_messages')
        .select()
        .or(
          'and(sender_id.eq.$userId,receiver_id.eq.$otherUserId),and(sender_id.eq.$otherUserId,receiver_id.eq.$userId)',
        )
        .order('created_at', ascending: true);

    final messages = List<Map<String, dynamic>>.from(data as List);
    _seenMessageIds.addAll(messages.map((m) => m['id'].toString()));
    return messages;
  }

  Stream<List<Map<String, dynamic>>> messageStream(String otherUserId) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return const Stream.empty();

    return supabase
        .from('mentor_messages')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: true)
        .map((rows) {
          final filtered = rows.where((msg) {
            final sender = msg['sender_id']?.toString();
            final receiver = msg['receiver_id']?.toString();
            return (sender == userId && receiver == otherUserId) ||
                (sender == otherUserId && receiver == userId);
          }).toList();

          filtered.sort((a, b) =>
              DateTime.parse(a['created_at']).compareTo(DateTime.parse(b['created_at'])));
          return filtered;
        });
  }

  Future<Map<String, dynamic>?> sendMessage(
      String otherUserId, String message) async {
    final userId = currentUserId;
    if (userId == null) return null;

    final response = await supabase
        .from('mentor_messages')
        .insert({
          'sender_id': userId,
          'receiver_id': otherUserId,
          'message': message,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        })
        .select()
        .single();

    _seenMessageIds.add(response['id'].toString());
    return response;
  }

  void listenForNewMessages() {
    final userId = currentUserId;
    if (userId == null) return;

    // Simple approach: listen to all new messages and filter manually
    supabase
        .channel('mentor_messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'mentor_messages',
          callback: (payload) async {
            final newMessage = payload.newRecord;
            final messageText = newMessage['message']?.toString() ?? '';
            final senderId = newMessage['sender_id']?.toString();
            final receiverId = newMessage['receiver_id']?.toString();
            final messageId = newMessage['id']?.toString();

            // Only process if this message is for the current user
            if (receiverId != userId) {
              return;
            }

            // Don't notify for messages you sent yourself
            if (senderId == userId) {
              return;
            }

            // Check if we've already seen this message
            if (_seenMessageIds.contains(messageId)) {
              return;
            }

            _seenMessageIds.add(messageId!);

            // Check if receiver has notifications enabled
            final receiverHasNotifications = await _checkUserNotificationPreference(userId);
            if (!receiverHasNotifications) {
              debugPrint('🔕 Notifications disabled by receiver - ignoring message');
              return;
            }

            // Get sender's name for notification
            try {
              if (senderId == null) {
                debugPrint('⚠️ Sender ID is null');
                return;
              }
              
              final senderProfile = await supabase
                  .from('profiles_new')
                  .select('username')
                  .eq('id', senderId)
                  .single();

              await NotificationService.showMessageNotification(
                fromUserName: senderProfile['username'] ?? 'Someone',
                message: messageText,
              );
              
              debugPrint('🔔 New message notification from ${senderProfile['username']}');
            } catch (e) {
              debugPrint('Error getting sender profile for notification: $e');
            }
          },
        )
        .subscribe();
  }

  Future<bool> _checkUserNotificationPreference(String userId) async {
    try {
      final response = await supabase
          .from('profiles_new')
          .select('notifications_enabled')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 3));
      
      return response?['notifications_enabled'] as bool? ?? true;
    } catch (e) {
      debugPrint('❌ Error checking notification preference for user $userId: $e');
      return true; // Default to enabled if there's an error
    }
  }

  // Clean up when done
  void dispose() {
    _seenMessageIds.clear();
  }
}