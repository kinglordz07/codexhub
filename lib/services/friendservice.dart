import 'package:supabase_flutter/supabase_flutter.dart';

class MentorFriendService {
  final supabase = Supabase.instance.client;

  /// 🔹 Send a mentor friend request if it doesn't already exist
  Future<void> sendRequest(String receiverId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Check existing requests (any status, both directions)
    final existing = await supabase
        .from('mentor_friend_requests')
        .select('id')
        .or('and(sender_id.eq.$userId,receiver_id.eq.$receiverId),and(sender_id.eq.$receiverId,receiver_id.eq.$userId)');

    if ((existing as List).isNotEmpty) return;

    // Check if already friends (BOTH DIRECTIONS)
    final existingFriendship = await supabase
        .from('mentor_friends')
        .select('id')
        .or('and(mentor_id.eq.$userId,friend_id.eq.$receiverId),and(mentor_id.eq.$receiverId,friend_id.eq.$userId)');

    if ((existingFriendship as List).isNotEmpty) return;

    await supabase.from('mentor_friend_requests').insert({
      'sender_id': userId,
      'receiver_id': receiverId,
    });
  }

  /// 🔹 Accept a mentor friend request and create friendship with correct roles
  Future<void> acceptRequest(String requestId, String senderId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Update request status
      await supabase
          .from('mentor_friend_requests')
          .update({'status': 'accepted'})
          .eq('id', requestId);

      // Check if friendship already exists (BOTH DIRECTIONS)
      final existingFriendship = await supabase
          .from('mentor_friends')
          .select('id')
          .or('and(mentor_id.eq.$userId,friend_id.eq.$senderId),and(mentor_id.eq.$senderId,friend_id.eq.$userId)');

      if ((existingFriendship as List).isNotEmpty) {
        print('✅ Friendship already exists');
        return;
      }

      // Determine roles correctly
      final users = await supabase
          .from('profiles_new')
          .select('id, role')
          .inFilter('id', [userId, senderId]);

      final userRole = users.firstWhere((u) => u['id'] == userId)['role'];
      final senderRole = users.firstWhere((u) => u['id'] == senderId)['role'];

      String mentorId;
      String friendId;

      if (userRole == 'mentor') {
        mentorId = userId;
        friendId = senderId;
      } else if (senderRole == 'mentor') {
        mentorId = senderId;
        friendId = userId;
      } else {
        // Both students - use alphabetical order to prevent duplicates
        final sorted = [userId, senderId]..sort();
        mentorId = sorted[0];
        friendId = sorted[1];
      }

      // Insert friendship with correct roles
      final result = await supabase.from('mentor_friends').insert({
        'mentor_id': mentorId,
        'friend_id': friendId,
        'status': 'accepted',
      }).select();

      print('✅ Friendship created: $result');
    } catch (e) {
      print('❌ Error accepting request: $e');
      rethrow;
    }
  }

  /// 🔹 Reject a mentor friend request
  Future<void> rejectRequest(String requestId) async {
    await supabase
        .from('mentor_friend_requests')
        .update({'status': 'rejected'})
        .eq('id', requestId);
  }

  /// 🔹 Get all pending requests with profile info
  Future<List<Map<String, dynamic>>> getPendingRequests() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final res = await supabase
        .from('mentor_friend_requests')
        .select('id, sender_id, profiles_new!mentor_friend_requests_sender_id_fkey(id, username, avatar_url, role)')
        .eq('receiver_id', userId)
        .eq('status', 'pending');

    return List<Map<String, dynamic>>.from(res);
  }

  /// 🔹 Get all accepted friends - FIXED VERSION
  Future<List<Map<String, dynamic>>> getFriends() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      print('❌ No user ID');
      return [];
    }

    print('🔍 Fetching friends for user: $userId');

    final res = await supabase
        .from('mentor_friends')
        .select('''
          id,
          mentor_id,
          friend_id,
          status,
          mentor:mentor_id (id, username, avatar_url, role),
          friend:friend_id (id, username, avatar_url, role)
        ''')
        .or('mentor_id.eq.$userId,friend_id.eq.$userId')
        .eq('status', 'accepted');

    print('📦 Raw response: $res');
    print('📊 Friend count: ${(res as List).length}');

    final List<Map<String, dynamic>> friends = [];

    for (var row in res) {
      final mentor = row['mentor'] as Map<String, dynamic>?;
      final friend = row['friend'] as Map<String, dynamic>?;

      if (mentor == null || friend == null) {
        print('⚠️ Skipping row - null mentor or friend: $row');
        continue;
      }

      // Get the OTHER user (not you)
      final otherUser = (mentor['id'] == userId) ? friend : mentor;

      friends.add({
        'friendship_id': row['id'],
        'status': row['status'],
        'id': otherUser['id'],
        'username': otherUser['username'],
        'avatar_url': otherUser['avatar_url'],
        'role': otherUser['role'],
      });
    }

    print('✅ Processed friends: ${friends.length}');
    return friends;
  }

  /// 🔹 Get suggestions - FIXED VERSION
  Future<List<Map<String, dynamic>>> getSuggestions() async {
    final currentUser = supabase.auth.currentUser;
    if (currentUser == null) return [];

    // Step 1: Get current friends
    final friends = await getFriends();
    final friendIds = friends.map((f) => f['id'] as String).toSet();

    // Step 2: Get ALL requests (sent or received, any status)
    final requests = await supabase
        .from('mentor_friend_requests')
        .select('sender_id, receiver_id')
        .or('sender_id.eq.${currentUser.id},receiver_id.eq.${currentUser.id}');

    // Step 3: Extract user IDs from those requests
    final requestUserIds = <String>{};
    for (var req in requests) {
      final senderId = req['sender_id'] as String?;
      final receiverId = req['receiver_id'] as String?;
      
      if (senderId != null && senderId != currentUser.id) {
        requestUserIds.add(senderId);
      }
      if (receiverId != null && receiverId != currentUser.id) {
        requestUserIds.add(receiverId);
      }
    }

    // Step 4: Combine all IDs to exclude
    final excludeIds = <String>{
      ...friendIds,
      ...requestUserIds,
    };

    // Step 5: Query ALL profiles (no exclusion yet)
    final res = await supabase
        .from('profiles_new')
        .select('id, username, avatar_url, role')
        .neq('id', currentUser.id)
        .inFilter('role', ['mentor', 'student'])
        .limit(50); // Get more, then filter manually

    // Step 6: Filter out excluded users manually
    final filtered = (res as List)
        .where((user) => !excludeIds.contains(user['id']))
        .take(20)
        .toList();

    return List<Map<String, dynamic>>.from(filtered);
  }

  /// 🔹 Search for mentors by username
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    final res = await supabase
        .from('profiles_new')
        .select('id, username, avatar_url, role, online_status')
        .ilike('username', '%$query%')
        .neq('id', userId)
        .eq('role', 'mentor')
        .eq('is_approved', true);

    return List<Map<String, dynamic>>.from(res);
  }

  /// 🔹 Start chat directly with a friend
  Future<Map<String, String>?> startChatWithFriend(String friendId) async {
    try {
      final res = await supabase
          .from('profiles_new')
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

  /// 🔹 Cancel your sent request
  Future<void> cancelRequest(String receiverId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    await supabase
        .from('mentor_friend_requests')
        .delete()
        .eq('sender_id', userId)
        .eq('receiver_id', receiverId)
        .eq('status', 'pending');
  }

  /// 🔹 Remove friend
  Future<void> removeFriend(String friendshipId) async {
    await supabase
        .from('mentor_friends')
        .delete()
        .eq('id', friendshipId);
  }
}