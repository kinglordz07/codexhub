import 'package:supabase_flutter/supabase_flutter.dart';

class MentorFriendService {
  final supabase = Supabase.instance.client;

  /// Send a mentor friend request if it doesn't already exist
  Future<void> sendRequest(String receiverId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Check existing pending requests (either sent or received)
    final existing = await supabase
        .from('mentor_friend_requests')
        .select('id')
        .filter('status', 'eq', 'pending')
        .or('and(sender_id.eq.$userId,receiver_id.eq.$receiverId),and(sender_id.eq.$receiverId,receiver_id.eq.$userId)');

    if ((existing as List).isNotEmpty) return;

    await supabase.from('mentor_friend_requests').insert({
      'sender_id': userId,
      'receiver_id': receiverId,
    });
  }

  /// Accept a mentor friend request and create friendship if not exists
  Future<void> acceptRequest(String requestId, String senderId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Update request status
    await supabase
        .from('mentor_friend_requests')
        .update({'status': 'accepted'})
        .eq('id', requestId);

    // Check if friendship already exists
    final existingFriendship = await supabase
        .from('mentor_friends')
        .select('id')
        .or('and(mentor_id.eq.$userId,friend_id.eq.$senderId),and(mentor_id.eq.$senderId,friend_id.eq.$userId)');

    if ((existingFriendship as List).isNotEmpty) return;

    // Insert friendship
    await supabase.from('mentor_friends').insert({
      'mentor_id': userId,
      'friend_id': senderId,
      'status': 'accepted',
    });
  }

  /// Reject a mentor friend request
  Future<void> rejectRequest(String requestId) async {
    await supabase
        .from('mentor_friend_requests')
        .update({'status': 'rejected'})
        .eq('id', requestId);
  }

  /// Get all pending requests with profile info including avatar
  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final res = await supabase
        .from('mentor_friend_requests')
        .select(
          'id, sender_id, profiles!mentor_friend_requests_sender_id_fkey(id, username, email, avatar_url)',
        )
        .eq('receiver_id', userId)
        .eq('status', 'pending');

    return List<Map<String, dynamic>>.from(res);
  }

  /// Get all accepted friends with profile info including avatar
  Future<List<Map<String, dynamic>>> getFriends() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final res = await supabase
        .from('mentor_friends')
        .select(
          'id, mentor_id, friend_id, profiles!mentor_friends_friend_id_fkey(id, username, email, avatar_url)',
        )
        .or('mentor_id.eq.$userId,friend_id.eq.$userId')
        .eq('status', 'accepted');

    return List<Map<String, dynamic>>.from(res);
  }

  /// Get "People You May Know" (mentors not yet friends) with avatar
  Future<List<Map<String, dynamic>>> getSuggestions() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final res = await supabase.rpc(
      'get_mentor_notfriend',
      params: {'uid': userId},
    );

    return List<Map<String, dynamic>>.from(res);
  }

  /// Search for users/mentors by username with avatar
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final res = await supabase
        .from('profiles')
        .select('id, username, email, avatar_url')
        .ilike('username', '%$query%')
        .neq('id', userId);

    return List<Map<String, dynamic>>.from(res);
  }

  /// Start chat directly with a friend
  Future<Map<String, String>?> startChatWithFriend(String friendId) async {
    try {
      final res = await supabase
          .from('profiles')
          .select('id, username, avatar_url')
          .eq('id', friendId)
          .maybeSingle();

      if (res == null || res['id'] == null || res['username'] == null) {
        return null;
      }

      return {
        'id': res['id'] as String,
        'username': res['username'] as String,
        'avatar_url': res['avatar_url'] as String? ?? ''
      };
    } catch (_) {
      return null;
    }
  }
}
