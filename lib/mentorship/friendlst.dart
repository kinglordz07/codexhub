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

  StreamSubscription? _friendSub; // real-time subscription

  @override
  void initState() {
    super.initState();
    loadData();

    // Real-time listener for friend_requests table
    _friendSub = service.supabase
        .from('friend_requests') // change if using a different table
        .stream(primaryKey: ['id'])
        .listen((changes) {
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
          title: const Text("My Friends"),
          bottom: const TabBar(
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

  Widget _buildRequests() {
    if (requests.isEmpty) {
      return const Center(child: Text("No pending requests"));
    }
    return ListView(
      children: requests.map((req) {
        final user = req['profiles'];
        final avatarUrl = user['avatar_url'] ?? '';

        return Card(
          margin: const EdgeInsets.all(6),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage:
                  avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty ? const Icon(Icons.person) : null,
            ),
            title: Text(user['username']),
            subtitle: Text(user['email']),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check, color: Colors.green),
                  onPressed: () async {
                    await service.acceptRequest(
                      req['id'],
                      req['sender_id'],
                    );
                    loadData();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatScreen(
                          otherUserId: req['sender_id'],
                          otherUserName: user['username'],
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () async {
                    await service.rejectRequest(req['id']);
                    loadData();
                  },
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

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
        final profile = friends[index]['profiles'] ?? {};
        final avatarUrl = profile['avatar_url'] ?? '';
        final id = profile['id']?.toString();
        final username = profile['username']?.toString() ?? 'Unknown';
        final email = profile['email']?.toString() ?? '';

        if (id == null || id.isEmpty) return const SizedBox.shrink();

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage:
                  avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty ? const Icon(Icons.person) : null,
            ),
            title: Text(
              username,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(email),
            trailing: const Icon(Icons.chat, color: Colors.indigo),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      ChatScreen(otherUserId: id, otherUserName: username),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSuggestions() {
    final list = searchResults.isNotEmpty ? searchResults : suggestions;

    if (list.isEmpty) {
      return const Center(child: Text("No suggestions available"));
    }

    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, index) {
        final user = list[index]['profiles'] ?? list[index];
        final avatarUrl = user['avatar_url'] ?? '';
        final id = user['id']?.toString();
        final username = user['username']?.toString() ?? 'Unknown';
        final email = user['email']?.toString() ?? '';

        if (id == null || id.isEmpty) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.all(6),
          child: ListTile(
            leading: CircleAvatar(
              backgroundImage:
                  avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
              child: avatarUrl.isEmpty ? const Icon(Icons.person) : null,
            ),
            title: Text(username),
            subtitle: Text(email),
            trailing: IconButton(
              icon: const Icon(Icons.person_add, color: Colors.blue),
              onPressed: () async {
                await service.sendRequest(id);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Friend request sent to $username")),
                );
                loadData();
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
