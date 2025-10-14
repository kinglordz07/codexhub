import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class MessageService {
  final SupabaseClient supabase = Supabase.instance.client;

  /// Keep track of seen messages to avoid duplicates in streams
  final Set<String> _seenMessageIds = {};

  /// Null-safe current user ID
  String? get currentUserId => supabase.auth.currentUser?.id;

  /// --------------------------
  /// Fetch all messages between current user and another user
  /// --------------------------
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

    // Track seen IDs
    _seenMessageIds.addAll(messages.map((m) => m['id'].toString()));
    return messages;
  }

  /// --------------------------
  /// Real-time per-conversation stream
  /// --------------------------
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
  /// --------------------------
  /// Global stream for all messages involving current user
  /// --------------------------
  Stream<List<Map<String, dynamic>>> globalMessageStream() {
  final userId = currentUserId;
  if (userId == null) return const Stream.empty();

  return supabase
      .from('mentor_messages')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: true)
      .map((changes) {
        // ✅ Local filtering for current user
        final newMessages = changes.where((msg) {
          final sender = msg['sender_id']?.toString();
          final receiver = msg['receiver_id']?.toString();
          final id = msg['id'].toString();

          final relevant = sender == userId || receiver == userId;
          if (relevant && !_seenMessageIds.contains(id)) {
            _seenMessageIds.add(id);
            return true;
          }
          return false;
        }).toList();

        newMessages.sort((a, b) =>
            DateTime.parse(a['created_at']).compareTo(DateTime.parse(b['created_at'])));

        return newMessages;
      });
}
  /// --------------------------
  /// Send a message
  /// --------------------------
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
        .single(); // ✅ returns the inserted row

    _seenMessageIds.add(response['id'].toString());
    return response;
  }
}
