import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FriendList extends StatefulWidget {
  const FriendList({super.key});

  @override
  State<FriendList> createState() => _FriendListState();
}

class _FriendListState extends State<FriendList> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final String? _currentUserId = Supabase.instance.client.auth.currentUser?.id;

  List<Map<String, dynamic>> _allFriends = [];
  List<Map<String, dynamic>> _nonFriends = [];
  List<Map<String, dynamic>> _friendRequests = [];

  String _searchQuery = '';
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFriendData();
  }

  Future<void> _loadFriendData() async {
    if (_currentUserId == null) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'You must be logged in to view friends';
        _isLoading = false;
      });
      return;
    }

    try {
      final friendsResponse = await _supabase
          .from('friends')
          .select('''
            friend:profiles!friends_friend_id_fkey(id, username, online_status)
          ''')
          .eq('user_id', _currentUserId)
          .eq('status', 'accepted');

      final List<Map<String, dynamic>> friendsData =
          (friendsResponse as List<dynamic>).cast<Map<String, dynamic>>();

      if (!mounted) return;
      setState(() {
        _allFriends =
            friendsData
                .map((friend) => friend['friend'] as Map<String, dynamic>)
                .toList();
      });

      final requestsResponse = await _supabase
          .from('friend_requests')
          .select('''
            sender:profiles!friend_requests_sender_id_fkey(id, username, online_status)
          ''')
          .eq('receiver_id', _currentUserId)
          .eq('status', 'pending');

      final List<Map<String, dynamic>> requestsData =
          (requestsResponse as List<dynamic>).cast<Map<String, dynamic>>();

      if (!mounted) return;
      setState(() {
        _friendRequests =
            requestsData
                .map((request) => request['sender'] as Map<String, dynamic>)
                .toList();
      });

      final nonFriendsResponse = await _supabase.rpc(
        'get_non_friends',
        params: {'current_user_id': _currentUserId},
      );

      final List<Map<String, dynamic>> nonFriendsData =
          (nonFriendsResponse as List<dynamic>).cast<Map<String, dynamic>>();

      if (!mounted) return;
      setState(() {
        _nonFriends = nonFriendsData;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _allFriends = [];
        _nonFriends = [];
        _friendRequests = [];
        _isLoading = false;
        _errorMessage = 'Failed to load friend data. Please try again later.';
      });
    }
  }

  List<Map<String, dynamic>> get _filteredFriends {
    return _allFriends
        .where(
          (friend) => friend['username'].toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ),
        )
        .toList();
  }

  List<Map<String, dynamic>> get _filteredNonFriends {
    return _nonFriends
        .where(
          (user) => user['username'].toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ),
        )
        .toList();
  }

  Future<void> _sendFriendRequest(Map<String, dynamic> user) async {
    if (_currentUserId == null) return;

    try {
      await _supabase.from('friend_requests').insert({
        'sender_id': _currentUserId,
        'receiver_id': user['id'],
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      setState(() {
        _friendRequests.add(user);
        _nonFriends.removeWhere((u) => u['id'] == user['id']);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Friend request sent to ${user['username']}!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send friend request')),
      );
    }
  }

  Future<void> _acceptFriendRequest(Map<String, dynamic> request) async {
    if (_currentUserId == null) return;

    try {
      await _supabase
          .from('friend_requests')
          .update({'status': 'accepted'})
          .eq('sender_id', request['id'])
          .eq('receiver_id', _currentUserId);

      await _supabase.from('friends').insert({
        'user_id': _currentUserId,
        'friend_id': request['id'],
        'status': 'accepted',
      });

      await _supabase.from('friends').insert({
        'user_id': request['id'],
        'friend_id': _currentUserId,
        'status': 'accepted',
      });

      if (!mounted) return;
      setState(() {
        _allFriends.add(request);
        _friendRequests.removeWhere((r) => r['id'] == request['id']);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${request['username']} is now your friend!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to accept friend request')),
      );
    }
  }

  Future<void> _rejectFriendRequest(Map<String, dynamic> request) async {
    if (_currentUserId == null) return;

    try {
      await _supabase
          .from('friend_requests')
          .update({'status': 'rejected'})
          .eq('sender_id', request['id'])
          .eq('receiver_id', _currentUserId);

      if (!mounted) return;
      setState(() {
        _friendRequests.removeWhere((r) => r['id'] == request['id']);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Friend request from ${request['username']} rejected.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to reject friend request')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends & Requests'),
        backgroundColor: Colors.indigo,
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _errorMessage != null
              ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _errorMessage!,
                      style: const TextStyle(fontSize: 16, color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _loadFriendData,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
              : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search friends...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged:
                          (value) => setState(() => _searchQuery = value),
                    ),
                  ),
                  if (_friendRequests.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Friend Requests',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._friendRequests.map(
                            (request) => Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue,
                                  child: Text(request['username'][0]),
                                ),
                                title: Text(request['username']),
                                subtitle: Text(
                                  request['online_status']
                                      ? 'Online'
                                      : 'Offline',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.check,
                                        color: Colors.green,
                                      ),
                                      tooltip: 'Accept Friend Request',
                                      onPressed:
                                          () => _acceptFriendRequest(request),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.red,
                                      ),
                                      tooltip: 'Reject Friend Request',
                                      onPressed:
                                          () => _rejectFriendRequest(request),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text(
                              'Your Friends',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (_filteredFriends.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text('No friends found.'),
                            )
                          else
                            ..._filteredFriends.map(
                              (friend) => Card(
                                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.blue,
                                    child: Text(friend['username'][0]),
                                  ),
                                  title: Text(friend['username']),
                                  subtitle: Text(
                                    friend['online_status']
                                        ? 'Online'
                                        : 'Offline',
                                  ),
                                  trailing:
                                      friend['online_status']
                                          ? const Icon(
                                            Icons.circle,
                                            color: Colors.green,
                                            size: 12,
                                          )
                                          : const Icon(
                                            Icons.circle,
                                            color: Colors.grey,
                                            size: 12,
                                          ),
                                ),
                              ),
                            ),
                          const Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text(
                              'People You May Know',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (_filteredNonFriends.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text('No suggestions available.'),
                            )
                          else
                            ..._filteredNonFriends.map(
                              (user) => Card(
                                margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.grey,
                                    child: Text(user['username'][0]),
                                  ),
                                  title: Text(user['username']),
                                  subtitle: Text(
                                    user['online_status']
                                        ? 'Online'
                                        : 'Offline',
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.person_add,
                                      color: Colors.green,
                                    ),
                                    tooltip: 'Send Friend Request',
                                    onPressed: () => _sendFriendRequest(user),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
    );
  }
}
