import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; 
import 'package:codexhub01/services/friendservice.dart';
import 'package:codexhub01/mentorship/menteemessaging_screen.dart';

class MentorFriendPage extends StatefulWidget {
  const MentorFriendPage({super.key});

  @override
  State<MentorFriendPage> createState() => _MentorFriendPageState();
}

class _MentorFriendPageState extends State<MentorFriendPage> {
  final service = MentorFriendService();
  final SupabaseClient supabase = Supabase.instance.client; 
  
  List<Map<String, dynamic>> friends = [];
  List<Map<String, dynamic>> requests = [];
  List<Map<String, dynamic>> suggestions = [];
  List<Map<String, dynamic>> searchResults = [];

  final TextEditingController _searchController = TextEditingController();
  StreamSubscription? _requestsSub;
  StreamSubscription? _friendsSub;
  
  bool _isLoading = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    loadData();
    _setupRealtimeListeners();
  }

  @override
  void dispose() {
    _requestsSub?.cancel();
    _friendsSub?.cancel();
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Setup real-time listeners for friend requests and friendships
  void _setupRealtimeListeners() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Listen to friend requests changes
    _requestsSub = supabase
        .from('mentor_friend_requests')
        .stream(primaryKey: ['id'])
        .listen((data) {
      debugPrint('🔔 Friend requests updated');
      _debouncedLoadData();
    });

    // Listen to friendships changes
    _friendsSub = supabase
        .from('mentor_friends')
        .stream(primaryKey: ['id'])
        .listen((data) {
      debugPrint('🔔 Friendships updated');
      _debouncedLoadData();
    });
  }

  /// Debounced load to prevent multiple rapid calls
  void _debouncedLoadData() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) loadData();
    });
  }

  /// Load all data (friends, requests, suggestions)
  Future<void> loadData() async {
    if (_isLoading) {
      debugPrint('⚠️ Already loading, skipping...');
      return;
    }
    
    setState(() => _isLoading = true);
    
    try {
      debugPrint('🔄 Loading data...');
      
      final reqs = await service.getPendingRequests();
      final frs = await service.getFriends();
      final suggs = await service.getSuggestions();
      
      if (!mounted) return;
      
      setState(() {
        requests = reqs;
        friends = frs;
        suggestions = suggs;
        searchResults = [];
        _isLoading = false;
      });
      
      debugPrint('✅ Loaded: ${friends.length} friends, ${requests.length} requests, ${suggestions.length} suggestions');
    } catch (e) {
      debugPrint('❌ Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Search users by username
  Future<void> searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }
    
    try {
      final res = await service.searchUsers(query);
      if (!mounted) return;
      
      setState(() {
        searchResults = res;
      });
    } catch (e) {
      debugPrint('❌ Error searching users: $e');
    }
  }


  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.indigo,
          title: const Text("Friends"),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.lightBlueAccent,
            tabs: [
              Tab(text: "Requests"),
              Tab(text: "Friends"),
              Tab(text: "People You May Know"),
            ],
          ),
        ),
        body: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _searchController,
                onChanged: searchUsers,
                decoration: InputDecoration(
                  hintText: "Search users...",
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

            // Loading indicator
            if (_isLoading)
              const LinearProgressIndicator(),

            // Tab content
            Expanded(
              child: TabBarView(
                children: [
                  _buildRequests(),
                  _buildFriends(),
                  _buildSuggestions(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 📨 Friend Requests Tab
  Widget _buildRequests() {
    if (requests.isEmpty) {
      return const Center(child: Text("No pending requests"));
    }
    
    return ListView(
      children: requests.map((req) {
        final user = req['profiles_new'];
        if (user == null) return const SizedBox.shrink();

        final requestId = req['id']?.toString();
        final senderId = req['sender_id']?.toString();
        final username = user['username']?.toString() ?? 'Unknown';
        final avatarUrl = user['avatar_url'] ?? '';

        if (requestId == null || senderId == null) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.all(6),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty ? const Icon(Icons.person) : null,
            ),
            title: Text(username),
            subtitle: Text(user['role'] ?? 'User'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () => _handleAcceptRequest(requestId, senderId, username),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () => _handleRejectRequest(requestId),
                ),
                IconButton(
                  icon: const Icon(Icons.chat, color: Colors.indigo),
                  onPressed: () => _handleChatWithSender(senderId),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 👥 Friends Tab
  Widget _buildFriends() {
    if (friends.isEmpty) {
      return const Center(
        child: Text("No friends yet", style: TextStyle(fontSize: 16)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemCount: friends.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final friend = friends[index];

        // Service returns flat structure with other user's data
        final id = friend['id']?.toString();
        final username = friend['username']?.toString() ?? 'Unknown';
        final avatarUrl = friend['avatar_url']?.toString() ?? '';
        final role = friend['role']?.toString() ?? 'User';

        if (id == null) return const SizedBox.shrink();

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty ? const Icon(Icons.person) : null,
            ),
            title: Text(
              username,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(role),
            trailing: IconButton(
              icon: const Icon(Icons.chat, color: Colors.indigo),
              onPressed: () => _handleChatWithFriend(id),
            ),
          ),
        );
      },
    );
  }

  /// 💡 Suggestions Tab
  Widget _buildSuggestions() {
    // Use search results if available, otherwise use suggestions
    final list = searchResults.isNotEmpty ? searchResults : suggestions;

    if (list.isEmpty) {
      return const Center(
        child: Text(
          "No suggestions available",
          style: TextStyle(fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final user = list[index]['profiles_new'] ?? list[index];
        final avatarUrl = user['avatar_url'] ?? '';
        final id = user['id']?.toString();
        final username = user['username']?.toString() ?? 'Unknown';

        if (id == null) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.all(6),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty ? const Icon(Icons.person) : null,
            ),
            title: Text(username),
            subtitle: Text(user['role'] ?? 'User'),
            trailing: IconButton(
              icon: const Icon(Icons.person_add, color: Colors.blue),
              onPressed: () => _handleSendRequest(id, username),
            ),
            onTap: () {
              Navigator.pop(context, {'id': id, 'username': username});
            },
          ),
        );
      },
    );
  }

  // ========== ACTION HANDLERS ==========

  Future<void> _handleAcceptRequest(String requestId, String senderId, String username) async {
    try {
      print('✅ Accepting request from $username...');
      
      await service.acceptRequest(requestId, senderId);
      
      // Wait for database propagation (especially important on mobile)
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("You are now friends with $username")),
      );
      
      // Reload data to update UI
      await loadData();
    } catch (e) {
      print('❌ Error accepting request: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to accept request")),
      );
    }
  }

  Future<void> _handleRejectRequest(String requestId) async {
    try {
      await service.rejectRequest(requestId);
      if (!mounted) return;
      await loadData();
    } catch (e) {
      print('❌ Error rejecting request: $e');
    }
  }

  Future<void> _handleChatWithSender(String senderId) async {
    final friend = await service.startChatWithFriend(senderId);
    if (friend == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can only chat with friends")),
      );
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MenteeMessagingScreen(
          otherUserId: friend['id']!,
          otherUserName: friend['username']!,
        ),
      ),
    );
  }

  Future<void> _handleChatWithFriend(String id) async {
    final friend = await service.startChatWithFriend(id);
    if (friend == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can only chat with friends")),
      );
      return;
    }
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MenteeMessagingScreen(
          otherUserId: friend['id']!,
          otherUserName: friend['username']!,
        ),
      ),
    );
  }

  Future<void> _handleSendRequest(String id, String username) async {
    try {
      await service.sendRequest(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Friend request sent to $username")),
      );
      await loadData();
    } catch (e) {
      print('❌ Error sending request: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to send request")),
      );
    }
  }
}