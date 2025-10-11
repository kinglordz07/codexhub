import 'package:supabase_flutter/supabase_flutter.dart';

class MessageService {
  final SupabaseClient supabase = Supabase.instance.client;

  String get currentUserId => supabase.auth.currentUser!.id;

  /// Get all messages between current user and other user
  Future<List<Map<String, dynamic>>> getMessages(String otherUserId) async {
    final userId = currentUserId;

    final data = await supabase
        .from('mentor_messages')
        .select()
        .or(
          'and(sender_id.eq.$userId,receiver_id.eq.$otherUserId),and(sender_id.eq.$otherUserId,receiver_id.eq.$userId)',
        )
        .order('created_at', ascending: true);

    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Stream for realtime messages
  Stream<List<Map<String, dynamic>>> messageStream(String otherUserId) {
    final userId = currentUserId;

    return supabase.from('mentor_messages').stream(primaryKey: ['id']).map((
      List<Map<String, dynamic>> allMessages,
    ) {
      return allMessages.where((msg) {
        final sender = msg['sender_id'].toString();
        final receiver = msg['receiver_id'].toString();
        return (sender == userId && receiver == otherUserId) ||
            (sender == otherUserId && receiver == userId);
      }).toList();
    });
  }

  /// Send message
  Future<void> sendMessage(String otherUserId, String message) async {
    final userId = currentUserId;

    await supabase.from('mentor_messages').insert({
      'sender_id': userId,
      'receiver_id': otherUserId,
      'message': message,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }
}
