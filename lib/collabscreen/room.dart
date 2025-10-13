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
  bool _isLoading = true;
  String? _creatorId;
  bool _isCreator = false;
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeRoom();
  }

  Future<void> _initializeRoom() async {
    try {
      await _loadRoomDetails();
      await _loadMessages();
      await _loadMembers();
      await _loadSnippets();
      _setupRealtimeSubscriptions();
      _checkIfCreator();
    } catch (e) {
      _showError('Failed to initialize room: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadRoomDetails() async {
    try {
      final response = await supabase
          .from('rooms')
          .select()
          .eq('id', widget.roomId)
          .single();
      
      if (mounted) {
        setState(() {
          _creatorId = response['creator_id'];
        });
      }
    } catch (e) {
      _showError('Failed to load room details: ${e.toString()}');
    }
  }

  Future<void> _loadMembers() async {
    try {
      final response = await supabase
          .from('room_members')
          .select('user_id, role, joined_at')
          .eq('room_id', widget.roomId);

      // Extract user IDs and fetch their profiles
      final userIds = response.map((member) => member['user_id'] as String).toList();
      if (userIds.isNotEmpty) {
        await _fetchUserBatch(userIds);
      }

      // Build members list with profile data
      final membersWithProfiles = <Map<String, dynamic>>[];
      for (var member in response) {
        final userId = member['user_id'] as String;
        final userData = _userData[userId] ?? {
          'name': 'User ${userId.substring(0, 8)}',
          'avatar_url': '',
          'id': userId,
        };
        
        membersWithProfiles.add({
          ...member,
          'profiles': userData,
        });
      }

      if (mounted) {
        setState(() {
          _members = membersWithProfiles;
        });
      }
    } catch (e) {
      _showError('Failed to load members: ${e.toString()}');
    }
  }

  Future<void> _loadMessages() async {
    try {
      if (mounted) {
        setState(() => _isLoadingMessages = true);
      }

      final response = await supabase
          .from('room_messages')
          .select('*')
          .eq('room_id', widget.roomId)
          .order('created_at', ascending: true); // Changed to ascending for proper chat flow

      // Load user data for messages
      final userIds = response.map((msg) => msg['user_id'] as String).toSet().toList();
      if (userIds.isNotEmpty) {
        await _fetchUserBatch(userIds);
      }

      final messagesWithUserData = <Map<String, dynamic>>[];
      for (var message in response) {
        final userId = message['user_id'] as String;
        final userData = _userData[userId] ?? {
          'name': 'User ${userId.substring(0, 8)}',
          'avatar_url': '',
          'id': userId,
        };
        
        messagesWithUserData.add({
          ...message,
          'sender_name': userData['name'],
          'sender_avatar': userData['avatar_url'],
        });
      }

      if (mounted) {
        setState(() {
          _messages = messagesWithUserData;
          _isLoadingMessages = false;
        });
      }

      // Scroll to bottom to show latest messages
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_messageScrollController.hasClients && _messages.isNotEmpty) {
          _messageScrollController.jumpTo(
            _messageScrollController.position.maxScrollExtent,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMessages = false);
      }
      _showError('Error loading messages: ${e.toString()}');
    }
  }

  void _checkIfCreator() {
    final user = supabase.auth.currentUser;
    if (user != null && _creatorId != null) {
      if (mounted) {
        setState(() {
          _isCreator = user.id == _creatorId;
        });
      }
    }
  }

  void _setupRealtimeSubscriptions() {
    // Messages subscription
    supabase
        .channel('room_${widget.roomId}_messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'room_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.roomId,
          ),
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.insert) {
              _fetchUserData(payload.newRecord['user_id']).then((userData) {
                if (mounted) {
                  setState(() {
                    _messages.add({
                      ...payload.newRecord,
                      'sender_name': userData['name'],
                      'sender_avatar': userData['avatar_url'],
                    });
                  });
                }

                // Scroll to bottom when new message arrives
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
            }
          },
        )
        .subscribe();

    // Snippets subscription
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
              if (mounted) {
                setState(() {
                  _snippets.add({
                    ...payload.newRecord,
                    'user_name': userData['name'],
                    'user_avatar': userData['avatar_url'],
                  });
                });
              }

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

  Future<void> _fetchUserBatch(List<String> userIds) async {
    if (userIds.isEmpty) return;

    try {
      final response = await supabase
          .from('profiles')
          .select('id, username, avatar_url')
          .inFilter('id', userIds);

      for (var profile in response) {
        _userData[profile['id']] = {
          'name': profile['username'] ?? 'Unknown User',
          'avatar_url': profile['avatar_url'] ?? '',
          'id': profile['id'],
        };
      }

      // Create entries for any missing users
      for (var userId in userIds) {
        if (!_userData.containsKey(userId)) {
          _userData[userId] = {
            'name': 'User ${userId.substring(0, 8)}',
            'avatar_url': '',
            'id': userId,
          };
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error in _fetchUserBatch: $e');
      }
      // If profile fetch fails, create basic entries
      for (var userId in userIds) {
        _userData[userId] = {
          'name': 'User ${userId.substring(0, 8)}',
          'avatar_url': '',
          'id': userId,
        };
      }
    }
  }

  Future<Map<String, dynamic>> _fetchUserData(String userId) async {
    if (_userData.containsKey(userId)) {
      return _userData[userId]!;
    }

    try {
      // Try profiles table without full_name
      final profileResponse = await supabase
          .from('profiles')
          .select('username, avatar_url')
          .eq('id', userId)
          .maybeSingle();

      if (profileResponse != null) {
        final userData = {
          'name': profileResponse['username'] ?? 'Unknown User',
          'avatar_url': profileResponse['avatar_url'] ?? '',
          'id': userId,
        };
        _userData[userId] = userData;
        return userData;
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching user data for $userId: $e');
      }
    }

    // Fallback
    final userData = {
      'name': 'User ${userId.substring(0, 8)}',
      'avatar_url': '',
      'id': userId,
    };
    _userData[userId] = userData;
    return userData;
  }

  Future<void> _copyRoomId() async {
    await Clipboard.setData(ClipboardData(text: widget.roomId));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Room ID copied to clipboard!')),
      );
    }
  }

  Future<void> _deleteRoom([String? roomId]) async {
    final id = roomId ?? widget.roomId;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await supabase.from('rooms').delete().eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room deleted')));
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete room: $e')));
    }
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Optimistic UI update
    final newMessage = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'content': content,
      'user_id': userId,
      'room_id': widget.roomId,
      'created_at': DateTime.now().toIso8601String(),
      'sender_name': _userData[userId]?['name'] ?? 'You',
      'sender_avatar': _userData[userId]?['avatar_url'] ?? '',
    };

    if (mounted) {
      setState(() {
        _messages.add(newMessage);
        _messageController.clear();
      });
    }

    // Scroll to bottom to show new message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_messageScrollController.hasClients) {
        _messageScrollController.animateTo(
          _messageScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });

    try {
      await supabase.from('room_messages').insert({
        'room_id': widget.roomId,
        'user_id': userId,
        'content': content,
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Send failed: $e')));
      
      // Remove optimistic update if failed
      if (mounted) {
        setState(() {
          _messages.removeWhere((msg) => msg['id'] == newMessage['id']);
        });
      }
    }
  }

  Future<void> _shareSnippet() async {
    final code = _snippetController.text.trim();
    if (code.isEmpty) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase.from('snippets').insert({
        'room_id': widget.roomId,
        'user_id': userId,
        'code': code,
      });
      _snippetController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Share failed: $e')));
    }
  }

  Future<void> _loadSnippets() async {
    try {
      if (mounted) {
        setState(() => _isLoadingSnippets = true);
      }

      final response = await supabase
          .from('snippets')
          .select('*')
          .eq('room_id', widget.roomId)
          .order('created_at', ascending: true);

      // Load user data for snippets
      final userIds = response.map((snippet) => snippet['user_id'] as String).toSet().toList();
      if (userIds.isNotEmpty) {
        await _fetchUserBatch(userIds);
      }

      final snippetsWithUserData = <Map<String, dynamic>>[];
      for (var snippet in response) {
        final userId = snippet['user_id'] as String;
        final userData = _userData[userId] ?? {
          'name': 'User ${userId.substring(0, 8)}',
          'avatar_url': '',
          'id': userId,
        };
        
        snippetsWithUserData.add({
          ...snippet,
          'user_name': userData['name'],
          'user_avatar': userData['avatar_url'],
        });
      }

      if (mounted) {
        setState(() {
          _snippets = snippetsWithUserData;
          _isLoadingSnippets = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSnippets = false);
      }
      _showError('Error loading snippets: ${e.toString()}');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildAvatar(Map<String, dynamic> userData, {double radius = 20}) {
    final String name = (userData['name'] ?? 'User') as String;
    final String? avatarUrl = userData['avatar_url'] as String?;
    
    // If we have a valid avatar URL, try to use it
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      try {
        return CircleAvatar(
          radius: radius,
          backgroundImage: NetworkImage(avatarUrl),
          onBackgroundImageError: (exception, stackTrace) {
            // Fall through to colored avatar if image fails
          },
        );
      } catch (e) {
        // Fall through to colored avatar if any error
      }
    }
    
    // Always use colored circle with initial (NO ASSET DEPENDENCY)
    return CircleAvatar(
      radius: radius,
      backgroundColor: _getAvatarColor(name),
      child: Text(
        _getAvatarInitial(name),
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.6,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getAvatarColor(String name) {
    // Simple consistent color based on first character
    final firstChar = name.isNotEmpty ? name[0].toLowerCase() : 'a';
    final colorMap = {
      'a': Colors.blue,
      'b': Colors.red,
      'c': Colors.green,
      'd': Colors.orange,
      'e': Colors.purple,
      'f': Colors.teal,
      'g': Colors.indigo,
      'h': Colors.brown,
      'i': Colors.blueGrey,
      'j': Colors.deepOrange,
      'k': Colors.lightBlue,
      'l': Colors.lightGreen,
      'm': Colors.pink,
      'n': Colors.deepPurple,
      'o': Colors.cyan,
      'p': Colors.amber,
      'q': Colors.lime,
      'r': Colors.yellow,
      's': Colors.grey,
      't': Colors.blue,
      'u': Colors.red,
      'v': Colors.green,
      'w': Colors.orange,
      'x': Colors.purple,
      'y': Colors.teal,
      'z': Colors.indigo,
      '0': Colors.blue,
      '1': Colors.red,
      '2': Colors.green,
      '3': Colors.orange,
      '4': Colors.purple,
      '5': Colors.teal,
      '6': Colors.indigo,
      '7': Colors.brown,
      '8': Colors.blueGrey,
      '9': Colors.deepOrange,
    };
    
    return colorMap[firstChar] ?? Colors.blue;
  }

  String _getAvatarInitial(String name) {
    if (name.isNotEmpty) {
      return name[0].toUpperCase();
    }
    return '?';
  }

  @override
  void dispose() {
    _messageController.dispose();
    _snippetController.dispose();
    _tabController.dispose();
    _messageScrollController.dispose();
    _snippetScrollController.dispose();
    supabase.removeAllChannels();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = supabase.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.roomName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  GestureDetector(
                    onTap: _copyRoomId,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "ID: ${widget.roomId}",
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.copy, size: 12, color: Colors.white70),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        centerTitle: false, // This makes the title left-aligned
        actions: [
          // REMOVED: Copy Room ID icon button - now it's part of the title
          if (_isCreator)
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
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: const Text("Delete"),
                        ),
                      ],
                    );
                  },
                );
              },
              tooltip: 'Delete Room',
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
      
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Chat Tab
                      Column(
                        children: [
                          // Members list with profile pictures
                          Container(
                            height: 70,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _members.length,
                              itemBuilder: (context, index) {
                                final member = _members[index];
                                final userData = _userData[member['user_id']] ?? 
                                    {'name': 'User ${member['user_id'].toString().substring(0, 8)}', 'avatar_url': ''};
                                final isCreator = member['user_id'] == _creatorId;
                                
                                return Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Stack(
                                        children: [
                                          _buildAvatar(userData, radius: 20),
                                          if (isCreator)
                                            Positioned(
                                              right: 0,
                                              bottom: 0,
                                              child: Container(
                                                padding: const EdgeInsets.all(3),
                                                decoration: const BoxDecoration(
                                                  color: Colors.blue,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.star,
                                                  color: Colors.white,
                                                  size: 10,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      SizedBox(
                                        width: 44,
                                        child: Text(
                                          userData['name'],
                                          style: const TextStyle(fontSize: 9),
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          const Divider(height: 1),
                    
                          // Messages - Now with proper chat flow (latest at bottom)
                          Expanded(
                            child: _isLoadingMessages
                                ? const Center(child: CircularProgressIndicator())
                                : _messages.isEmpty
                                    ? const Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.chat, size: 64, color: Colors.grey),
                                            SizedBox(height: 16),
                                            Text('No messages yet'),
                                          ],
                                        ),
                                      )
                                    : ListView.builder(
                                        controller: _messageScrollController,
                                        itemCount: _messages.length,
                                        // No reverse needed since we're ordering by ascending date
                                        itemBuilder: (context, index) {
                                          final msg = _messages[index];
                                          final isMe = msg['user_id'] == currentUserId;
                                          final userData = {
                                            'name': msg['sender_name'],
                                            'avatar_url': msg['sender_avatar'],
                                            'id': msg['user_id'],
                                          };

                                          return MessageBubble(
                                            message: msg,
                                            isMe: isMe,
                                            userData: userData,
                                            formatDate: _formatDate,
                                            buildAvatar: _buildAvatar,
                                            currentUserId: currentUserId,
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
                                        hintText: "Type a message...",
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 12,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                      ),
                                      onSubmitted: (_) => _sendMessage(),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
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
                            child: _isLoadingSnippets
                                ? const Center(child: CircularProgressIndicator())
                                : _snippets.isEmpty
                                    ? const Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.code, size: 64, color: Colors.grey),
                                            SizedBox(height: 16),
                                            Text(
                                              'No code snippets yet',
                                              style: TextStyle(
                                                fontSize: 18,
                                                color: Colors.grey,
                                              ),
                                            ),
                                            Text(
                                              'Share your first code snippet!',
                                              style: TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ListView.builder(
                                        controller: _snippetScrollController,
                                        itemCount: _snippets.length,
                                        itemBuilder: (context, index) {
                                          final snip = _snippets[index];
                                          final isMe = snip['user_id'] == currentUserId;
                                          final userData = {
                                            'name': snip['user_name'],
                                            'avatar_url': snip['user_avatar'],
                                            'id': snip['user_id'],
                                          };

                                          return SnippetBubble(
                                            snippet: snip,
                                            isMe: isMe,
                                            userData: userData,
                                            formatDate: _formatDate,
                                            buildAvatar: _buildAvatar,
                                            currentUserId: currentUserId,
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
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.send),
                                    onPressed: () => _shareSnippet(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ])
    );
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString).toLocal();
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }
}

// Updated MessageBubble with simplified props
class MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final Map<String, dynamic> userData;
  final String Function(String) formatDate;
  final Widget Function(Map<String, dynamic>, {double radius}) buildAvatar;
  final String? currentUserId;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.userData,
    required this.formatDate,
    required this.buildAvatar,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isMe) buildAvatar(userData, radius: 20),
            if (!isMe) const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isMe ? Colors.indigo[100] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMe)
                      Text(
                        userData['name'] ?? 'Unknown User',
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
            if (isMe) buildAvatar(userData, radius: 20),
          ],
        ),
      ),
    );
  }
}

// Updated SnippetBubble with simplified props
class SnippetBubble extends StatelessWidget {
  final Map<String, dynamic> snippet;
  final bool isMe;
  final Map<String, dynamic> userData;
  final String Function(String) formatDate;
  final Widget Function(Map<String, dynamic>, {double radius}) buildAvatar;
  final String? currentUserId;

  const SnippetBubble({
    super.key,
    required this.snippet,
    required this.isMe,
    required this.userData,
    required this.formatDate,
    required this.buildAvatar,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (!isMe) buildAvatar(userData, radius: 20),
            if (!isMe) const SizedBox(width: 8),
            Flexible(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isMe ? Colors.blue[100] : Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMe)
                      Text(
                        userData['name'] ?? 'Unknown User',
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
            if (isMe) buildAvatar(userData, radius: 20),
          ],
        ),
      ),
    );
  }
}