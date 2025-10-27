import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:codexhub01/parts/create_live_lobby.dart';
import 'package:codexhub01/collabscreen/collab_room_tabs.dart'; 

class CollabRoomScreen extends StatefulWidget {
  final String roomId;
  final String roomName;
  final bool isMentor;

  const CollabRoomScreen({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.isMentor,
  });

  @override
  State<CollabRoomScreen> createState() => _CollabRoomScreenState();
}

class _CollabRoomScreenState extends State<CollabRoomScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  final TextEditingController _messageController = TextEditingController();
  final ScrollController _messageScrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  List<Map<String, dynamic>> _members = [];
  final Map<String, Map<String, dynamic>> _userData = {};

  bool _isLoading = true;
  bool _isLoadingMessages = false;
  bool _isLoadingInvite = false;

  String? _creatorId;
  bool _isCreator = false;

  @override
  void initState() {
    super.initState();
    _initializeRoom();
  }

  Future<void> _initializeRoom() async {
    try {
      await _loadRoomDetails();
      await _loadMembers();
      await _loadMessages();
      _setupRealtimeSubscriptions();
      _checkIfCreator();
    } catch (e) {
      _showError('Failed to initialize room: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadRoomDetails() async {
    try {
      final room = await supabase
          .from('rooms')
          .select()
          .eq('id', widget.roomId)
          .maybeSingle();
      if (room != null) _creatorId = room['creator_id'];
    } catch (e) {
      _showError('Failed to load room details: $e');
    }
  }

  Future<void> _loadMembers() async {
    try {
      final members = await supabase
          .from('room_members')
          .select('user_id')
          .eq('room_id', widget.roomId);

      final userIds = members.map((m) => m['user_id'] as String).toList();
      if (userIds.isNotEmpty) await _fetchUserBatch(userIds);

      _members = members.map((m) {
        final userId = m['user_id'] as String;
        final userData = _userData[userId] ??
            {
              'name': 'User ${userId.substring(0, 8)}',
              'avatar_url': '',
              'id': userId
            };
        return {...m, 'profiles': userData};
      }).toList();

      if (mounted) setState(() {});
    } catch (e) {
      _showError('Failed to load members: $e');
    }
  }

  Future<void> _loadMessages() async {
    try {
      setState(() => _isLoadingMessages = true);
      final messages = await supabase
          .from('room_messages')
          .select('*')
          .eq('room_id', widget.roomId)
          .order('created_at', ascending: true);

      final userIds = messages.map((msg) => msg['user_id'] as String).toSet().toList();
      if (userIds.isNotEmpty) await _fetchUserBatch(userIds);

      _messages = messages.map((msg) {
        final userId = msg['user_id'] as String;
        final userData = _userData[userId] ??
            {
              'name': 'User ${userId.substring(0, 8)}',
              'avatar_url': '',
              'id': userId
            };
        return {
          ...msg,
          'sender_name': userData['name'],
          'sender_avatar': userData['avatar_url'],
        };
      }).toList();

      if (mounted) setState(() => _isLoadingMessages = false);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_messageScrollController.hasClients && _messages.isNotEmpty) {
          _messageScrollController.jumpTo(_messageScrollController.position.maxScrollExtent);
        }
      });
    } catch (e) {
      setState(() => _isLoadingMessages = false);
      _showError('Error loading messages: $e');
    }
  }

  void _checkIfCreator() {
    final user = supabase.auth.currentUser;
    if (user != null && _creatorId != null) {
      setState(() => _isCreator = user.id == _creatorId);
    }
  }

  void _setupRealtimeSubscriptions() {
    supabase
        .channel('room_${widget.roomId}_messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'room_messages',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'room_id',
              value: widget.roomId),
          callback: (payload) async {
            try {
              if (!mounted) return;
              final userData = await _fetchUserData(payload.newRecord['user_id']);
              setState(() {
                _messages.add({
                  ...payload.newRecord,
                  'sender_name': userData['name'],
                  'sender_avatar': userData['avatar_url'],
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
            } catch (_) {}
          },
        )
        .subscribe();
  }

  Future<void> _fetchUserBatch(List<String> userIds) async {
    if (userIds.isEmpty) return;
    try {
      final profiles = await supabase
          .from('profiles_new')
          .select('id, username, avatar_url')
          .inFilter('id', userIds);

      for (var p in profiles) {
        _userData[p['id']] = {
          'name': p['username'] ?? 'Unknown User',
          'avatar_url': p['avatar_url'] ?? '',
          'id': p['id'],
        };
      }

      for (var userId in userIds) {
        _userData.putIfAbsent(userId, () => {
              'name': 'User ${userId.substring(0, 8)}',
              'avatar_url': '',
              'id': userId,
            });
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _fetchUserData(String userId) async {
    if (_userData.containsKey(userId)) return _userData[userId]!;

    try {
      final profile = await supabase
          .from('profiles_new')
          .select('username, avatar_url')
          .eq('id', userId)
          .maybeSingle();
      if (profile != null) {
        final data = {
          'name': profile['username'] ?? 'Unknown User',
          'avatar_url': profile['avatar_url'] ?? '',
          'id': userId,
        };
        _userData[userId] = data;
        return data;
      }
    } catch (_) {}
    final fallback = {'name': 'User ${userId.substring(0, 8)}', 'avatar_url': '', 'id': userId};
    _userData[userId] = fallback;
    return fallback;
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() {
      _messageController.clear();
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
    }
  }

  Future<void> _inviteMentor() async {
    setState(() => _isLoadingInvite = true);
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) return;

      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreateLiveLobby(
            menteeId: currentUser.id,
            menteeName: currentUser.email ?? 'Mentee', isMentor: false,
          ),
        ),
      );

      if (result != null && result is Map<String, dynamic>) {
        final String roomId = result['room_id'].toString();
        final String roomName = result['room_name'].toString();
        final String menteeId = result['mentee_id'].toString();
        final String mentorId = result['mentor_id'].toString();
        final bool isMentor = false;

        Navigator.pushReplacement(
          // ignore: use_build_context_synchronously
          context,
          MaterialPageRoute(
            builder: (_) => CollabRoomTabs(
              roomId: roomId,
              roomName: roomName,
              menteeId: menteeId,
              mentorId: mentorId,
              isMentor: isMentor,
            ),
          ),
        );
      }

      await _loadMembers();
    } catch (e) {
      _showError('Failed to invite mentor: $e');
    } finally {
      if (mounted) setState(() => _isLoadingInvite = false);
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString).toLocal();
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateString;
    }
  }

  Widget _buildAvatar(Map<String, dynamic> userData, {double radius = 20}) {
    final name = userData['name'] ?? 'User';
    final avatarUrl = userData['avatar_url'] as String?;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(avatarUrl));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.primaries[name.codeUnitAt(0) % Colors.primaries.length],
      child: Text(name[0].toUpperCase(), style: TextStyle(color: Colors.white, fontSize: radius * 0.6, fontWeight: FontWeight.bold)),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageScrollController.dispose();
    supabase.removeAllChannels();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = supabase.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo.shade400,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, 
          
          children: [
            Text(widget.roomName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
            GestureDetector(
              onTap: () => Clipboard.setData(ClipboardData(text: widget.roomId)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("ID: ${widget.roomId}", style: const TextStyle(fontSize: 12, color: Colors.white70)),
                  const SizedBox(width: 4),
                  const Icon(Icons.copy, size: 12, color: Colors.white70),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_isCreator)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: () => _deleteRoom(),
              tooltip: 'Delete Room',
            ),
          IconButton(
            icon: _isLoadingInvite
                ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                : const Icon(Icons.person_add),
            tooltip: 'Invite Mentor / Code Lobby',
            onPressed: _isLoadingInvite ? null : _inviteMentor,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  height: 70,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.indigo, 
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.indigo.shade700,
                        Colors.indigo.shade500,
                      ],
                    ),
                  ),
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _members.length,
                    itemBuilder: (context, index) {
                      final member = _members[index];
                      final userData = _userData[member['user_id']] ?? {'name': 'User', 'avatar_url': ''};
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
                                  const Positioned(right: 0, bottom: 0, child: Icon(Icons.star, size: 10, color: Colors.amber)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            SizedBox(
                              width: 44,
                              child: Text(
                                userData['name'], 
                                style: const TextStyle(
                                  fontSize: 9, 
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500
                                ), 
                                overflow: TextOverflow.ellipsis, 
                                textAlign: TextAlign.center
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _isLoadingMessages
                      ? const Center(child: CircularProgressIndicator())
                      : _messages.isEmpty
                          ? const Center(child: Text('No messages yet'))
                          : ListView.builder(
                              controller: _messageScrollController,
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final msg = _messages[index];
                                final isMe = msg['user_id'] == currentUserId;
                                final userData = {'name': msg['sender_name'], 'avatar_url': msg['sender_avatar'], 'id': msg['user_id']};
                                return Align(
                                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isMe ? Colors.indigo[100] : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        if (!isMe) Text(userData['name'] ?? 'Unknown User', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[700])),
                                        if (!isMe) const SizedBox(height: 4),
                                        Text((msg['content'] ?? '').toString(), style: const TextStyle(fontSize: 16)),
                                        const SizedBox(height: 4),
                                        Text(_formatDate((msg['created_at'] ?? '').toString()), style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            decoration: InputDecoration(
                              hintText: "Type a message...",
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(icon: const Icon(Icons.send, color: Colors.indigo), onPressed: _sendMessage),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _deleteRoom() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete room?'),
        content: const Text('Are you sure? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
  
      await supabase.from('live_sessions').delete().eq('room_id', widget.roomId);
      await supabase.from('room_members').delete().eq('room_id', widget.roomId);
      await supabase.from('room_messages').delete().eq('room_id', widget.roomId);

      await supabase.from('rooms').delete().eq('id', widget.roomId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Room deleted')));
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete room: $e')));
    }
  }
}