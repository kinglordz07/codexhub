import 'dart:async';
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
  RealtimeChannel? _messageChannel;

  // ✅ ENHANCED: Mobile responsive detection
  bool get isSmallScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width < 600;
  }

  bool get isVerySmallScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width < 400;
  }

  bool get isTablet {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width >= 600 && mediaQuery.size.width < 1200;
  }

  // ✅ ENHANCED: Dynamic sizing for mobile
  double get titleFontSize => isVerySmallScreen ? 14 : (isSmallScreen ? 16 : (isTablet ? 18 : 20));
  double get bodyFontSize => isVerySmallScreen ? 12 : (isSmallScreen ? 14 : 16);
  double get iconSize => isVerySmallScreen ? 18 : (isSmallScreen ? 20 : 24);
  double get buttonPadding => isVerySmallScreen ? 8 : (isSmallScreen ? 12 : 16);

  @override
  void initState() {
    super.initState();
    _initializeRoom();
  }

  Future<void> _initializeRoom() async {
    try {
      await _loadRoomDetails();
      await _loadMembers();
      _setupRealtimeSubscriptions(); // ✅ FIXED: Setup real-time BEFORE loading messages
      await _loadMessages();
      _checkIfCreator();
    } catch (e) {
      debugPrint('Failed to initialize room: $e');
      _showError('Failed to initialize room. Please check your connection.');
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
          .maybeSingle()
          .timeout(const Duration(seconds: 10));
      if (room != null) _creatorId = room['creator_id'];
    } catch (e) {
      debugPrint('Failed to load room details: $e');
    }
  }

  Future<void> _loadMembers() async {
    try {
      final members = await supabase
          .from('room_members')
          .select('user_id, joined_at')
          .eq('room_id', widget.roomId)
          .timeout(const Duration(seconds: 10));

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
      debugPrint('Failed to load members: $e');
      // Don't show error for members loading - it's not critical
    }
  }

  Future<void> _loadMessages() async {
    try {
      setState(() => _isLoadingMessages = true);
      final messages = await supabase
          .from('room_messages')
          .select('*')
          .eq('room_id', widget.roomId)
          .order('created_at', ascending: true)
          .timeout(const Duration(seconds: 15));

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
  debugPrint('🔄 Setting up real-time subscriptions for room: ${widget.roomId}');
  
  // Unsubscribe from existing channel if any
  _messageChannel?.unsubscribe();

  _messageChannel = supabase.channel('room_${widget.roomId}_messages');
  
  _messageChannel!
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'room_messages',
        callback: (payload) async {
          if (!mounted) return;
          
          final newMessage = payload.newRecord;
          
          // Filter by room_id
          if (newMessage['room_id'] != widget.roomId) return;
          
          final userId = newMessage['user_id'] as String;
          final userData = await _fetchUserData(userId);
          
          if (mounted) {
            setState(() {
              _messages.add({
                ...newMessage,
                'sender_name': userData['name'],
                'sender_avatar': userData['avatar_url'],
              });
            });
            
            // Auto-scroll to bottom
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_messageScrollController.hasClients) {
                _messageScrollController.animateTo(
                  _messageScrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              }
            });
          }
        },
      )
      .subscribe();

  debugPrint('✅ Real-time subscription setup completed');
}

  Future<void> _fetchUserBatch(List<String> userIds) async {
    if (userIds.isEmpty) return;
    try {
      final profiles = await supabase
          .from('profiles_new')
          .select('id, username, avatar_url')
          .inFilter('id', userIds)
          .timeout(const Duration(seconds: 10));

      for (var p in profiles) {
        _userData[p['id']] = {
          'name': p['username'] ?? 'Unknown User',
          'avatar_url': p['avatar_url'] ?? '',
          'id': p['id'],
        };
      }

      // Add fallback for any missing users
      for (var userId in userIds) {
        _userData.putIfAbsent(userId, () => {
              'name': 'User ${userId.substring(0, 8)}',
              'avatar_url': '',
              'id': userId,
            });
      }
    } catch (e) {
      debugPrint('Error fetching user batch: $e');
    }
  }

  Future<Map<String, dynamic>> _fetchUserData(String userId) async {
    if (_userData.containsKey(userId)) return _userData[userId]!;

    try {
      final profile = await supabase
          .from('profiles_new')
          .select('username, avatar_url')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
          
      if (profile != null) {
        final data = {
          'name': profile['username'] ?? 'Unknown User',
          'avatar_url': profile['avatar_url'] ?? '',
          'id': userId,
        };
        _userData[userId] = data;
        return data;
      }
    } catch (e) {
      debugPrint('Error fetching user data: $e');
    }
    
    // Fallback data
    final fallback = {
      'name': 'User ${userId.substring(0, 8)}', 
      'avatar_url': '', 
      'id': userId
    };
    _userData[userId] = fallback;
    return fallback;
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty) return;

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // ✅ IMPROVED: Store message temporarily for better UX
    final tempMessage = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'room_id': widget.roomId,
      'user_id': userId,
      'content': content,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'sender_name': _getCurrentUserName(supabase.auth.currentUser!),
      'sender_avatar': '',
    };

    // Clear input immediately for better UX
    setState(() {
      _messageController.clear();
      _messages.add(tempMessage);
      
      // Scroll to bottom
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

    try {
      await supabase.from('room_messages').insert({
        'room_id': widget.roomId,
        'user_id': userId,
        'content': content,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }).timeout(const Duration(seconds: 10));
      
      // ✅ Remove temporary message - real-time will add the actual one
      setState(() {
        _messages.removeWhere((msg) => msg['id'].toString().startsWith('temp_'));
      });
      
    } catch (e) {
      if (!mounted) return;
      
      // ✅ Show error and restore message
      setState(() {
        _messages.removeWhere((msg) => msg['id'].toString().startsWith('temp_'));
        _messageController.text = content; // Restore message
      });
      
      _showError('Failed to send message. Please check your connection.');
    }
  }

  Future<void> _inviteMentor() async {
    if (_isLoadingInvite) return;
    setState(() => _isLoadingInvite = true);
    
    try {
      final currentUser = supabase.auth.currentUser;
      if (currentUser == null) {
        _showError('You must be logged in to invite a mentor');
        return;
      }

      final userName = _getCurrentUserName(currentUser);
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CreateLiveLobby(
            menteeId: currentUser.id,
            menteeName: userName,
            isMentor: false,
          ),
        ),
      );

      await _handleInviteResult(result, currentUser);

    } catch (e, stack) {
      debugPrint('Error inviting mentor: $e\n$stack');
      _showError('Failed to invite mentor. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoadingInvite = false);
    }
  }

  // ✅ ADD: Helper method to get current user name
  String _getCurrentUserName(User user) {
    try {
      final username = user.userMetadata?['username']?.toString();
      final emailName = user.email?.split('@').first;
      final name = user.userMetadata?['name']?.toString();
      
      if (username != null && username.isNotEmpty) return username;
      if (name != null && name.isNotEmpty) return name;
      if (emailName != null && emailName.isNotEmpty) return emailName;
      return 'User';
    } catch (e) {
      return 'User';
    }
  }

  Future<void> _handleInviteResult(dynamic result, User currentUser) async {
    if (result == null || result is! Map<String, dynamic>) {
      debugPrint('Mentor invitation cancelled');
      return;
    }

    try {
      final String roomId = result['roomId']?.toString() ?? '';
      final String roomName = result['roomName']?.toString() ?? 'Live Session';

      if (roomId.isEmpty) {
        _showError('Failed to create collaboration room');
        return;
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CollabRoomTabs(
            roomId: roomId,
            roomName: roomName,
            menteeId: currentUser.id,
            mentorId: result['mentorId']?.toString() ?? '',
            isMentor: false, 
            sessionId: roomId,
          ),
        ),
      );

    } catch (e, stack) {
      debugPrint('Error handling invite result: $e\n$stack');
      if (mounted) {
        _showError('Failed to process invitation.');
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(fontSize: bodyFontSize),
          ), 
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
        ),
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
      return CircleAvatar(
        radius: radius, 
        backgroundImage: NetworkImage(avatarUrl),
        onBackgroundImageError: (exception, stackTrace) {
          debugPrint('Failed to load avatar: $exception');
        },
      );
    }
    
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.primaries[name.codeUnitAt(0) % Colors.primaries.length],
      child: Text(
        name[0].toUpperCase(), 
        style: TextStyle(
          color: Colors.white, 
          fontSize: radius * 0.6, 
          fontWeight: FontWeight.bold
        ),
      ),
    );
  }

  // ✅ ENHANCED: Mobile-optimized app bar
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.indigo.shade400,
      elevation: 2,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, 
        children: [
          Text(
            widget.roomName, 
            style: TextStyle(
              fontSize: titleFontSize,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ), 
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: widget.roomId));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Room ID copied to clipboard',
                    style: TextStyle(fontSize: bodyFontSize),
                  ),
                  behavior: SnackBarBehavior.floating,
                  margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
                )
              );
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Text(
                    "ID: ${widget.roomId}", 
                    style: TextStyle(
                      fontSize: isVerySmallScreen ? 9 : 11,
                      color: Colors.white70,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.copy, 
                  size: isVerySmallScreen ? 10 : 12,
                  color: Colors.white70,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (_isCreator)
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: iconSize,
              color: Colors.white,
            ),
            onPressed: () => _deleteRoom(),
            tooltip: 'Delete Room',
          ),
        IconButton(
          icon: _isLoadingInvite
              ? SizedBox(
                  width: isSmallScreen ? 16 : 20,
                  height: isSmallScreen ? 16 : 20,
                  child: CircularProgressIndicator(
                    color: Colors.white, 
                    strokeWidth: 2,
                  ),
                )
              : Icon(
                  Icons.person_add_alt_rounded,
                  size: iconSize,
                  color: Colors.white,
                ),
          tooltip: 'Invite Mentor / Create Code Lobby',
          onPressed: _isLoadingInvite ? null : _inviteMentor,
        ),
      ],
    );
  }

  // ✅ ENHANCED: Mobile-optimized loading state
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
          ),
          SizedBox(height: 16),
          Text(
            'Loading chat room...',
            style: TextStyle(
              fontSize: bodyFontSize,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ ENHANCED: Mobile-optimized empty state
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline, 
            size: isSmallScreen ? 48 : 64, 
            color: Colors.grey[400]
          ),
          SizedBox(height: 16),
          Text(
            'No messages yet',
            style: TextStyle(
              fontSize: bodyFontSize,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Start the conversation!',
            style: TextStyle(
              fontSize: isSmallScreen ? 12 : 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

 Widget _buildMessageInput() {
  return SafeArea(
    top: false,
    child: Container(
      padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey.shade300, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: BoxConstraints(
                maxHeight: 120, 
              ),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: "Type a message...",
                  hintStyle: TextStyle(fontSize: bodyFontSize),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 16 : 20, 
                    vertical: isSmallScreen ? 12 : 16,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                ),
                style: TextStyle(fontSize: bodyFontSize),
                maxLines: null, // Grow as needed
                minLines: 1,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          SizedBox(width: isSmallScreen ? 8 : 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.indigo,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                Icons.send_rounded, 
                color: Colors.white,
                size: iconSize - 2,
              ), 
              onPressed: _sendMessage,
              padding: EdgeInsets.all(isSmallScreen ? 8 : 10),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildMembersSection() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 12 : 16,
        vertical: isSmallScreen ? 8 : 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.indigo.shade700,
            Colors.indigo.shade500,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(
            'Room Members',
            style: TextStyle(
              color: Colors.white,
              fontSize: bodyFontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      _members.isEmpty
          ? SizedBox(
                height: 40,
                child: Center(
              child: Text(
                'No members yet',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: bodyFontSize,
                ),
              ),),
            )
            : SizedBox(
                height: isVerySmallScreen ? 60 : (isSmallScreen ? 70 : 80),
                child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _members.length,
              itemBuilder: (context, index) {
                final member = _members[index];
                final userData = _userData[member['user_id']] ?? {
                  'name': 'User', 
                  'avatar_url': ''
                };
                final isCreator = member['user_id'] == _creatorId;
                
                return Container(
                  margin: EdgeInsets.only(right: isSmallScreen ? 12 : 16),
                  constraints: BoxConstraints( 
                  maxWidth: isVerySmallScreen ? 60 : (isSmallScreen ? 70 : 80),
                ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        children: [
                          _buildAvatar(
                            userData, 
                            radius: isVerySmallScreen ? 18 : (isSmallScreen ? 20 : 24)
                          ),
                          if (isCreator)
                            Positioned(
                              right: 0, 
                              bottom: 0, 
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.star_rounded, 
                                  size: isVerySmallScreen ? 10 : 12,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                        ],
                      ),
                      SizedBox(height: 6),
                      SizedBox( 
                      width: isVerySmallScreen ? 50 : (isSmallScreen ? 60 : 70),
                        child: Text(
                          userData['name'], 
                          style: TextStyle(
                            fontSize: isVerySmallScreen ? 9 : 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ), 
                          overflow: TextOverflow.ellipsis, 
                          textAlign: TextAlign.center,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                );
              },
                ),
                ),
      ],
            ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isMe) {
    final userData = {
      'name': msg['sender_name'], 
      'avatar_url': msg['sender_avatar'], 
      'id': msg['user_id']
    };
    
    return Container(
      margin: EdgeInsets.symmetric(
        vertical: 4,
        horizontal: isSmallScreen ? 8 : 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMe) 
            Padding(
              padding: EdgeInsets.only(
                right: isSmallScreen ? 8 : 12, 
                top: 2
              ),
              child: _buildAvatar(
                userData, 
                radius: isSmallScreen ? 16 : 18
              ),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isMe)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 8),
                    child: Text(
                      userData['name'] ?? 'Unknown User', 
                      style: TextStyle(
                        fontSize: isSmallScreen ? 11 : 12, 
                        fontWeight: FontWeight.w600, 
                        color: Colors.grey[700],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Container(
                  constraints: BoxConstraints(
                    maxWidth: isSmallScreen 
                        ? MediaQuery.of(context).size.width * 0.75 
                        : MediaQuery.of(context).size.width * 0.65,
                  ),
                  padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                  decoration: BoxDecoration(
                    color: isMe ? Colors.indigo.shade100 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SelectableText(
                        (msg['content'] ?? '').toString(), 
                        style: TextStyle(
                          fontSize: bodyFontSize,
                          color: Colors.grey[800],
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        _formatDate((msg['created_at'] ?? '').toString()), 
                        style: TextStyle(
                          fontSize: isSmallScreen ? 9 : 10, 
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (isMe) 
            Padding(
              padding: EdgeInsets.only(
                left: isSmallScreen ? 8 : 12, 
                top: 2
              ),
              child: _buildAvatar(
                userData, 
                radius: isSmallScreen ? 16 : 18
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _messageScrollController.dispose();
    _messageChannel?.unsubscribe(); // ✅ FIXED: Remove removeAllChannels()
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
  final currentUserId = supabase.auth.currentUser?.id;

  return Scaffold(
    appBar: _buildAppBar(),
    body: _isLoading
        ? _buildLoadingState()
        : Column(
            children: [

              _buildMembersSection(),
              
              Expanded(
                child: _isLoadingMessages
                    ? _buildLoadingState()
                    : _messages.isEmpty
                        ? _buildEmptyState()
                        : ListView.builder(
                            controller: _messageScrollController,
                            itemCount: _messages.length,
                            padding: EdgeInsets.only(
                              bottom: isSmallScreen ? 8 : 12,
                            ),
                            itemBuilder: (context, index) {
                              final msg = _messages[index];
                              final isMe = msg['user_id'] == currentUserId;
                              return _buildMessageBubble(msg, isMe);
                            },
                          ),
              ),
              
              _buildMessageInput(),
            ],
          ),
  );
}

  Future<void> _deleteRoom() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          'Delete Room?',
          style: TextStyle(fontSize: titleFontSize),
        ),
        content: Text(
          'Are you sure you want to delete this room? This action cannot be undone.',
          style: TextStyle(fontSize: bodyFontSize),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), 
            child: Text(
              'Cancel',
              style: TextStyle(fontSize: bodyFontSize),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              'Delete',
              style: TextStyle(fontSize: bodyFontSize),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Delete related data first (foreign key constraints)
      await supabase.from('live_sessions').delete().eq('room_id', widget.roomId);
      await supabase.from('room_members').delete().eq('room_id', widget.roomId);
      await supabase.from('room_messages').delete().eq('room_id', widget.roomId);

      // Finally delete the room
      await supabase.from('rooms').delete().eq('id', widget.roomId);
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Room deleted successfully',
            style: TextStyle(fontSize: bodyFontSize),
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
        )
      );
      
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      _showError('Failed to delete room: $e');
    }
  }
}