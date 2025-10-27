// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:codexhub01/services/friendservice.dart';
import 'package:codexhub01/mentorship/menteemessaging_screen.dart';

class MentorFriendPage extends StatefulWidget {
  const MentorFriendPage({super.key});

  @override
  State<MentorFriendPage> createState() => _MentorFriendPageState();
}

class _MentorFriendPageState extends State<MentorFriendPage> {
  final service = MentorFriendService();
  List<Map<String, dynamic>> friends = [];
  List<Map<String, dynamic>> requests = [];
  List<Map<String, dynamic>> suggestions = [];
  List<Map<String, dynamic>> searchResults = [];

  final TextEditingController _searchController = TextEditingController();
  StreamSubscription? _friendSub;

  @override
  void initState() {
    super.initState();
    loadData();

    // Real-time listener for friend_requests table
    _friendSub = service.supabase
        .from('mentor_friend_requests')
        .stream(primaryKey: ['id'])
        .listen((_) {
      loadData(); // refresh UI automatically
    });
  }

  @override
  void dispose() {
    _friendSub?.cancel();
    super.dispose();
  }

  Future<void> loadData() async {
    final reqs = await service.getPendingRequests();
    final frs = await service.getFriends();
    final suggs = await service.getSuggestions();
    if (!mounted) return;
    setState(() {
      requests = reqs;
      friends = frs;
      suggestions = suggs;
      searchResults = [];
    });
  }

  Future<void> searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }
    final res = await service.searchUsers(query);
    if (!mounted) return;
    setState(() {
      searchResults = res;
    });
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
            // 🔍 Search bar
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
              backgroundImage:
                  avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty ? const Icon(Icons.person) : null,
            ),
            title: Text(username),
            subtitle: Text(user['role'] ?? 'Mentor'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () async {
                    await service.acceptRequest(requestId, senderId);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("You are now friends with $username")),
                    );
                    await loadData();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () async {
                    await service.rejectRequest(requestId);
                    if (!mounted) return;
                    await loadData();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.chat, color: Colors.indigo),
                  onPressed: () async {
                    final friend = await service.startChatWithFriend(senderId);
                    if (friend == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("You can only chat with friends")),
                      );
                      return;
                    }
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          otherUserId: friend['id']!,
                          otherUserName: friend['username']!,
                        ),
                      ),
                    );
                  },
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

  final currentUserId = service.supabase.auth.currentUser?.id ?? '';

  return ListView.separated(
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
    itemCount: friends.length,
    separatorBuilder: (_, __) => const SizedBox(height: 6),
    itemBuilder: (context, index) {
      final friendData = friends[index];

      // Determine the other user (not the current user)
      final profile = friendData['mentor_id'] == currentUserId
          ? friendData['friend']    // friend_id profile
          : friendData['mentor'];   // mentor_id profile

      if (profile == null) return const SizedBox.shrink();

      final id = profile['id']?.toString();
      final username = profile['username']?.toString() ?? 'Unknown';
      final avatarUrl = profile['avatar_url'] ?? '';

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
          subtitle: Text(profile['role'] ?? 'Mentor'),
          trailing: IconButton(
            icon: const Icon(Icons.chat, color: Colors.indigo),
            onPressed: () async {
              final friend = await service.startChatWithFriend(id);
              if (friend == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("You can only chat with friends")),
                );
                return;
              }
              if (!mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    otherUserId: friend['id']!,
                    otherUserName: friend['username']!,
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}
  /// 💡 Suggestions Tab
  Widget _buildSuggestions() {
    final list = searchResults.isNotEmpty ? searchResults : suggestions;

    if (list.isEmpty) {
      return const Center(child: Text("No suggestions available"));
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
              backgroundImage:
                  avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty ? const Icon(Icons.person) : null,
            ),
            title: Text(username),
            subtitle: Text(user['role'] ?? 'Mentor'),
            trailing: IconButton(
              icon: const Icon(Icons.person_add, color: Colors.blue),
              onPressed: () async {
                await service.sendRequest(id);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Friend request sent to $username")),
                );
                await loadData();
              },
            ),
            onTap: () {
              Navigator.pop(context, {'id': id, 'username': username});
            },
          ),
        );
      },
    );
  }
}
