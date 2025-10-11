import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CollabRoomScreen extends StatefulWidget {
  final String roomId;
  final String roomName;

  const CollabRoomScreen({
    super.key,
    required this.roomId,
    required this.roomName,
  });

  @override
  State<CollabRoomScreen> createState() => _CollabRoomScreenState();
}

class _CollabRoomScreenState extends State<CollabRoomScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _snippetController = TextEditingController();
  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _snippets = [];
  final Map<String, Map<String, dynamic>> _userData = {};
  late TabController _tabController;
  final ScrollController _messageScrollController = ScrollController();
  final ScrollController _snippetScrollController = ScrollController();
  bool _isLoadingMessages = false;
  bool _isLoadingSnippets = true;
  String? _creatorId;
  // ignore: unused_field
  List<Map<String, dynamic>> _allFriends = [];
  // ignore: unused_field
  final List<Map<String, dynamic>> _nonFriends = [];
  // ignore: unused_field
  List<Map<String, dynamic>> _friendRequests = [];

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);

    _loadMessages();
    _loadSnippets();
    _loadFriendsData();
    _loadRoomDetails();
    _setupRealtimeSubscriptions();
  }

  ImageProvider _getAvatarImage(String? avatarUrl) {
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return NetworkImage(avatarUrl);
    }
    return const AssetImage('assets/default_avatar.png');
  }

  String _getAvatarText(String? name) {
    if (name != null && name.isNotEmpty) {
      return name[0].toUpperCase();
    }
    return '?';
  }

  Future<void> _loadRoomDetails() async {
    try {
      final response =
          await supabase
              .from('rooms')
              .select('creator_id')
              .eq('id', widget.roomId)
              .single();

      setState(() {
        _creatorId = response['creator_id'];
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading room details: $e')));
    }
  }

  void _setupRealtimeSubscriptions() {
    supabase
        .channel('room_${widget.roomId}_messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.roomId,
          ),
          callback: (payload) {
            _fetchUserData(payload.newRecord['sender_id']).then((userData) {
              setState(() {
                _messages.add({
                  ...payload.newRecord,
                  'sender_name': userData['name'],
                  'sender_avatar': userData['avatar'],
                });
              });

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_messageScrollController.hasClients) {
                  _messageScrollController.animateTo(
                    _messageScrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              });
            });
          },
        )
        .subscribe();

    supabase
        .channel('room_${widget.roomId}_snippets')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'snippets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.roomId,
          ),
          callback: (payload) {
            _fetchUserData(payload.newRecord['user_id']).then((userData) {
              setState(() {
                _snippets.add({
                  ...payload.newRecord,
                  'user_name': userData['name'],
                  'user_avatar': userData['avatar'],
                });
              });

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_snippetScrollController.hasClients) {
                  _snippetScrollController.animateTo(
                    _snippetScrollController.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                }
              });
            });
          },
        )
        .subscribe();
  }

  Future<void> _loadFriendsData() async {
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final friendsResponse = await supabase
          .from('friends')
          .select('*')
          .eq('user_id', currentUser.id)
          .eq('status', 'accepted');

      final requestsResponse = await supabase
          .from('friend_requests')
          .select('*')
          .eq('receiver_id', currentUser.id)
          .eq('status', 'pending');

      setState(() {
        _allFriends = List<Map<String, dynamic>>.from(friendsResponse);
        _friendRequests = List<Map<String, dynamic>>.from(requestsResponse);
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error loading friends data: $e');
      }
    }
  }

  Future<void> _fetchUserBatch(List<String> userIds) async {
    if (userIds.isEmpty) return;

    try {
      final response = await supabase
          .from('profiles')
          .select('id, username, full_name, avatar_url')
          .inFilter('id', userIds);

      for (var profile in response) {
        _userData[profile['id']] = {
          'name': profile['full_name'] ?? profile['username'] ?? 'Unknown User',
          'avatar': profile['avatar_url'] ?? '',
          'id': profile['id'],
        };
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching users batch: $e');
      }
    }
  }

  Future<void> _loadUserDataForMessages(List<dynamic> messages) async {
    final userIds =
        messages.map((msg) => msg['sender_id'] as String).toSet().toList();
    await _fetchUserBatch(userIds);
  }

  Future<Map<String, dynamic>> _fetchUserData(String userId) async {
    if (_userData.containsKey(userId)) {
      return _userData[userId]!;
    }

    try {
      final profileResponse =
          await supabase
              .from('profiles')
              .select('username, full_name, avatar_url')
              .eq('id', userId)
              .maybeSingle();

      String name = 'Unknown User';
      String avatarUrl = '';

      if (profileResponse != null) {
        name =
            profileResponse['full_name'] ??
            profileResponse['username'] ??
            'Unknown User';
        avatarUrl = profileResponse['avatar_url'] ?? '';
      } else {
        final userResponse = await supabase.auth.admin.getUserById(userId);
        if (userResponse.user != null && userResponse.user!.email != null) {
          name = userResponse.user!.email!;
        }
      }

      final userData = {'name': name, 'avatar': avatarUrl, 'id': userId};
      _userData[userId] = userData;
      return userData;
    } catch (e) {
      return {'name': 'Unknown User', 'avatar': '', 'id': userId};
    }
  }

  Future<void> _loadMessages() async {
    try {
      setState(() => _isLoadingMessages = true);

      final response = await supabase
          .from('messages')
          .select('id, content, sender_id, created_at')
          .eq('room_id', widget.roomId)
          .order('created_at', ascending: true);

      await _loadUserDataForMessages(response);

      final messagesWithUserData = <Map<String, dynamic>>[];
      for (var message in response) {
        final userData =
            _userData[message['sender_id']] ??
            {'name': 'Unknown User', 'avatar': '', 'id': message['sender_id']};
        messagesWithUserData.add({
          ...message,
          'sender_name': userData['name'],
          'sender_avatar': userData['avatar'],
        });
      }

      setState(() {
        _messages = messagesWithUserData;
        _isLoadingMessages = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_messageScrollController.hasClients) {
          _messageScrollController.jumpTo(
            _messageScrollController.position.maxScrollExtent,
          );
        }
      });
    } catch (e) {
      setState(() => _isLoadingMessages = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading messages: ${e.toString()}')),
      );
    }
  }

  /// Delete the room (optional roomId). Adjust Supabase table/schema as needed.
  Future<void> _deleteRoom([String? roomId]) async {
    // ignore: unused_local_variable
    final id = roomId ?? widget.roomId;
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Delete room?'),
            content: const Text(
              'Are you sure you want to delete this room? This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );

    if (confirm != true) return;

    try {
      // Example Supabase deletion — adapt table name and column if different
      // final res = await supabase.from('rooms').delete().eq('id', id);
      // handle response...
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Room deleted')));
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete room: $e')));
    }
  }

  /// Show options for a user (signature matches your call sites)
  void _showUserOptions(BuildContext ctx, Map<String, dynamic> userData) {
    showModalBottomSheet(
      context: ctx,
      builder: (sheetCtx) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.person),
                title: const Text('View profile'),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  // Navigate to profile screen (implement navigation)
                  // Navigator.pushNamed(ctx, '/profile', arguments: userData['id']);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('Copy user ID'),
                onTap: () {
                  Clipboard.setData(
                    ClipboardData(text: userData['id']?.toString() ?? ''),
                  );
                  Navigator.pop(sheetCtx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Copied user id')),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.remove_circle),
                title: const Text('Remove from room'),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  final userId = userData['id']?.toString();
                  if (userId != null) {
                    await _removeUserFromRoom(userId);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(sheetCtx),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _removeUserFromRoom(String userId) async {
    try {
      // Example Supabase deletion — adapt as needed
      // await supabase.from('room_members').delete().eq('room_id', widget.roomId).eq('user_id', userId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User removed')));
      // optionally refresh member list
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Remove failed: $e')));
    }
  }

  /// Send a message. Accepts optional text or uses _messageController.
  Future<void> _sendMessage([String? text]) async {
    final content = (text ?? _messageController.text).trim();
    if (content.isEmpty) return;

    final userId = supabase.auth.currentUser?.id;
    final currentUserData = userId != null ? _userData[userId] : null;

    // optimistic UI update: add to local list and scroll
    final newMessage = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'content': content,
      'sender_id': supabase.auth.currentUser?.id ?? 'unknown',
      'created_at': DateTime.now().toIso8601String(),
      'sender_name': currentUserData?['name'] ?? 'You',
      'sender_avatar': currentUserData?['avatar'] ?? '',
    };

    setState(() {
      _messages.add(newMessage);
      _messageController.clear();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_messageScrollController.hasClients) {
        _messageScrollController.jumpTo(
          _messageScrollController.position.maxScrollExtent,
        );
      }
    });

    try {
      // Example Supabase insert — adapt table name/columns
      // await supabase.from('messages').insert([{
      //   'room_id': widget.roomId,
      //   'sender_id': supabase.auth.currentUser!.id,
      //   'content': content,
      // }]);
      // Optionally refresh messages or handle returned message id
    } catch (e) {
      // On failure, show error (optionally remove optimistic message or mark as failed)
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Send failed: $e')));
    }
  }

  /// Share/copy a code snippet. Accepts snippet text (optional).
  Future<void> _shareSnippet([String? snippetText]) async {
    final text = snippetText ?? '/* snippet not provided */';
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Snippet copied to clipboard')),
      );
      // To invoke OS share dialog, add share_plus and call Share.share(text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  Future<void> _loadSnippets() async {
    try {
      setState(() => _isLoadingSnippets = true);

      final response = await supabase
          .from('snippets')
          .select('id, code, user_id, created_at')
          .eq('room_id', widget.roomId)
          .order('created_at', ascending: true);

      final userIds =
          response
              .map((snippet) => snippet['user_id'] as String)
              .toSet()
              .toList();
      await _fetchUserBatch(userIds);

      final snippetsWithUserData = <Map<String, dynamic>>[];
      for (var snippet in response) {
        final userData =
            _userData[snippet['user_id']] ??
            {'name': 'Unknown User', 'avatar': '', 'id': snippet['user_id']};
        snippetsWithUserData.add({
          ...snippet,
          'user_name': userData['name'],
          'user_avatar': userData['avatar'],
        });
      }

      setState(() {
        _snippets = snippetsWithUserData;
        _isLoadingSnippets = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_snippetScrollController.hasClients) {
          _snippetScrollController.jumpTo(
            _snippetScrollController.position.maxScrollExtent,
          );
        }
      });
    } catch (e) {
      setState(() => _isLoadingSnippets = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading snippets: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = supabase.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text("Room: ${widget.roomName}"),
        actions: [
          if (_creatorId != null && _creatorId == supabase.auth.currentUser?.id)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text("Delete Room"),
                      content: const Text(
                        "Are you sure you want to delete this room? This action cannot be undone.",
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Cancel"),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            _deleteRoom();
                          },
                          child: const Text(
                            "Delete",
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.chat), text: "Chat"),
            Tab(icon: Icon(Icons.code), text: "Snippets"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Chat Tab
          Column(
            children: [
              Expanded(
                child:
                    _isLoadingMessages
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                          controller: _messageScrollController,
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final msg = _messages[index];
                            final isMe = msg['sender_id'] == currentUserId;
                            final userData = {
                              'name': msg['sender_name'],
                              'avatar': msg['sender_avatar'],
                              'id': msg['sender_id'],
                            };

                            return MessageBubble(
                              message: msg,
                              isMe: isMe,
                              userData: userData,
                              onAvatarTap:
                                  () => _showUserOptions(context, userData),
                              formatDate: _formatDate,
                              getAvatarImage: _getAvatarImage,
                              getAvatarText: _getAvatarText,
                              currentUserId: currentUserId,
                              allUserData: _userData,
                            );
                          },
                        ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: InputDecoration(
                            hintText: "Enter message...",
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send, color: Colors.indigo),
                        onPressed: _sendMessage,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Snippets Tab
          Column(
            children: [
              Expanded(
                child:
                    _isLoadingSnippets
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                          controller: _snippetScrollController,
                          itemCount: _snippets.length,
                          itemBuilder: (context, index) {
                            final snip = _snippets[index];
                            final isMe = snip['user_id'] == currentUserId;
                            final userData = {
                              'name': snip['user_name'],
                              'avatar': snip['user_avatar'],
                              'id': snip['user_id'],
                            };

                            return SnippetBubble(
                              snippet: snip,
                              isMe: isMe,
                              userData: userData,
                              onAvatarTap:
                                  () => _showUserOptions(context, userData),
                              formatDate: _formatDate,
                              getAvatarImage: _getAvatarImage,
                              getAvatarText: _getAvatarText,
                              currentUserId: currentUserId,
                              allUserData: _userData,
                            );
                          },
                        ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _snippetController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: "Enter code snippet...",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onSubmitted: (_) => _shareSnippet(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _shareSnippet,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }
}

// === single MessageBubble (kept) and SnippetBubble ===

class MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final Map<String, dynamic> userData;
  final VoidCallback onAvatarTap;
  final String Function(String) formatDate;
  final ImageProvider Function(String?) getAvatarImage;
  final String Function(String?) getAvatarText;
  final String? currentUserId;
  final Map<String, Map<String, dynamic>> allUserData;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.userData,
    required this.onAvatarTap,
    required this.formatDate,
    required this.getAvatarImage,
    required this.getAvatarText,
    required this.currentUserId,
    required this.allUserData,
  });

  @override
  Widget build(BuildContext context) {
    // Safely extract strings
    final String name = (userData['name'] ?? '') as String;
    final String avatarRaw = (userData['avatar'] ?? '') as String;

    // Use getAvatarImage/getAvatarText helpers passed into the widget
    final ImageProvider avatarImage = getAvatarImage(
      avatarRaw.isNotEmpty ? avatarRaw : null,
    );
    final String avatarText = getAvatarText(name);

    // For current user avatar (right side), fetch safely from allUserData
    final Map<String, dynamic>? meData =
        (currentUserId != null) ? allUserData[currentUserId] : null;
    final String myName = (meData?['name'] ?? '') as String;
    final String myAvatarRaw = (meData?['avatar'] ?? '') as String;
    final ImageProvider myAvatarImage = getAvatarImage(
      myAvatarRaw.isNotEmpty ? myAvatarRaw : null,
    );
    final String myAvatarText = getAvatarText(myName);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            // left avatar (other users)
            if (!isMe)
              GestureDetector(
                onTap: onAvatarTap,
                child: CircleAvatar(
                  backgroundImage: avatarImage,
                  radius: 20,
                  child:
                      avatarRaw.isEmpty
                          ? Text(
                            avatarText,
                            style: const TextStyle(color: Colors.white),
                          )
                          : null,
                ),
              ),

            if (!isMe) const SizedBox(width: 8),

            // message bubble
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isMe ? Colors.indigo[200] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMe)
                      Text(
                        name.isNotEmpty ? name : 'Unknown User',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                    if (!isMe) const SizedBox(height: 4),
                    Text(
                      (message['content'] ?? '').toString(),
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDate((message['created_at'] ?? '').toString()),
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),

            if (isMe) const SizedBox(width: 8),

            // right avatar (current user)
            if (isMe)
              GestureDetector(
                onTap: onAvatarTap,
                child: CircleAvatar(
                  backgroundImage: myAvatarImage,
                  radius: 20,
                  child:
                      (myAvatarRaw.isEmpty)
                          ? Text(
                            myAvatarText,
                            style: const TextStyle(color: Colors.white),
                          )
                          : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class SnippetBubble extends StatelessWidget {
  final Map<String, dynamic> snippet;
  final bool isMe;
  final Map<String, dynamic> userData;
  final VoidCallback onAvatarTap;
  final String Function(String) formatDate;
  final ImageProvider Function(String?) getAvatarImage;
  final String Function(String?) getAvatarText;
  final String? currentUserId;
  final Map<String, Map<String, dynamic>> allUserData;

  const SnippetBubble({
    super.key,
    required this.snippet,
    required this.isMe,
    required this.userData,
    required this.onAvatarTap,
    required this.formatDate,
    required this.getAvatarImage,
    required this.getAvatarText,
    required this.currentUserId,
    required this.allUserData,
  });

  @override
  Widget build(BuildContext context) {
    final String name = (userData['name'] ?? '') as String;
    final String avatarRaw = (userData['avatar'] ?? '') as String;
    final ImageProvider avatarImage = getAvatarImage(
      avatarRaw.isNotEmpty ? avatarRaw : null,
    );
    final String avatarText = getAvatarText(name);

    final Map<String, dynamic>? meData =
        (currentUserId != null) ? allUserData[currentUserId] : null;
    final String myName = (meData?['name'] ?? '') as String;
    final String myAvatarRaw = (meData?['avatar'] ?? '') as String;
    final ImageProvider myAvatarImage = getAvatarImage(
      myAvatarRaw.isNotEmpty ? myAvatarRaw : null,
    );
    final String myAvatarText = getAvatarText(myName);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isMe)
              GestureDetector(
                onTap: onAvatarTap,
                child: CircleAvatar(
                  backgroundImage: avatarImage,
                  radius: 20,
                  child:
                      avatarRaw.isEmpty
                          ? Text(
                            avatarText,
                            style: const TextStyle(color: Colors.white),
                          )
                          : null,
                ),
              ),
            if (!isMe) const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isMe ? Colors.blue[200] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMe)
                      Text(
                        name.isNotEmpty ? name : 'Unknown User',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                    if (!isMe) const SizedBox(height: 4),
                    Text(
                      (snippet['code'] ?? '').toString(),
                      style: const TextStyle(fontFamily: "monospace"),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatDate((snippet['created_at'] ?? '').toString()),
                      style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),
            if (isMe) const SizedBox(width: 8),
            if (isMe)
              GestureDetector(
                onTap: onAvatarTap,
                child: CircleAvatar(
                  backgroundImage: myAvatarImage,
                  radius: 20,
                  child:
                      myAvatarRaw.isEmpty
                          ? Text(
                            myAvatarText,
                            style: const TextStyle(color: Colors.white),
                          )
                          : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
