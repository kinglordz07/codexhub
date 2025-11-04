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

  int _pendingRequestsCount = 0;
  int _unreadMessagesCount = 0;
  int _missedCallsCount = 0;
  bool _hasNewNotifications = false;

  final TextEditingController _searchController = TextEditingController();
  StreamSubscription? _requestsSub;
  StreamSubscription? _friendsSub;
  StreamSubscription? _messagesSub;
  StreamSubscription? _callsSub;
  
  bool _isLoading = false;
  bool _isRefreshing = false;
  Timer? _debounceTimer;
  int _loadingRetryCount = 0;
  static const int maxRetries = 3;

  bool get isSmallScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width < 600;
  }

  bool get isVerySmallScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width < 400;
  }

  double get titleFontSize => isVerySmallScreen ? 14 : (isSmallScreen ? 16 : 18);
  double get bodyFontSize => isVerySmallScreen ? 12 : (isSmallScreen ? 14 : 16);
  double get iconSize => isVerySmallScreen ? 18 : (isSmallScreen ? 20 : 24);

  @override
  void initState() {
    super.initState();
    _initializeData();
    _setupMessageNotificationListener(); 
    _updateNotificationCounts();
  }

  @override
  void dispose() {
    _cleanupResources();
    super.dispose();
  }

  void _cleanupResources() {
    _requestsSub?.cancel();
    _friendsSub?.cancel();
    _messagesSub?.cancel();
    _callsSub?.cancel();
    _debounceTimer?.cancel();
    _searchController.dispose();
    debugPrint('🔄 Resources cleaned up');
  }

  Future<void> _updateNotificationCounts() async {
    await Future.wait([
      _checkPendingRequests(),
      _checkUnreadMessages(),
      _checkMissedCalls(),
    ]);
    
    final hasNotifications = _pendingRequestsCount > 0 || 
                            _unreadMessagesCount > 0 || 
                            _missedCallsCount > 0;
    
    if (mounted && _hasNewNotifications != hasNotifications) {
      setState(() {
        _hasNewNotifications = hasNotifications;
      });
    }
  }

  Future<void> _checkPendingRequests() async {
    try {
      final requests = await service.getPendingRequests();
      if (mounted) {
        setState(() {
          _pendingRequestsCount = requests.length;
        });
      }
    } catch (e) {
      debugPrint('❌ Error checking pending requests: $e');
    }
  }

  // Enhanced message notification tracking
final Map<String, int> _unreadMessagesByFriend = {};

Future<void> _checkUnreadMessages() async {
  try {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Get all unread messages
    final response = await supabase
        .from('mentor_messages')
        .select('sender_id')
        .eq('receiver_id', userId)
        .eq('is_read', false);

    if (mounted) {
      setState(() {
        _unreadMessagesByFriend.clear();
        _unreadMessagesCount = 0;
        
        // Manually group by sender_id
        final Map<String, int> messageCounts = {};
        for (final item in response) {
          final senderId = item['sender_id']?.toString();
          if (senderId != null) {
            messageCounts[senderId] = (messageCounts[senderId] ?? 0) + 1;
          }
        }
        
        _unreadMessagesByFriend.addAll(messageCounts);
        _unreadMessagesCount = response.length;
      });
    }
  } catch (e) {
    debugPrint('❌ Error checking unread messages: $e');
  }
}

void _setupMessageNotificationListener() {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return;

  // Cancel existing subscriptions if any
  _messagesSub?.cancel();
  _callsSub?.cancel();

  // Enhanced message listener that also listens for read status changes
  _messagesSub = supabase
      .from('mentor_messages')
      .stream(primaryKey: ['id'])
      .listen((List<Map<String, dynamic>> data) {
    bool shouldUpdate = false;
    
    for (final message in data) {
      final receiverId = message['receiver_id']?.toString();
      final senderId = message['sender_id']?.toString();
      final isRead = message['is_read'] ?? true;
      
      // If this message is for current user
      if (receiverId == userId) {
        if (!isRead) {
          // New unread message
          _handleNewMessageNotification(senderId, message);
          shouldUpdate = true;
        } else {
          // Message was marked as read (possibly from chat screen)
          debugPrint('📖 Message marked as read from $senderId');
          shouldUpdate = true;
        }
      }
    }
    
    // Refresh unread counts if any message status changed
    if (shouldUpdate) {
      _checkUnreadMessages();
    }
  }, onError: (error) {
    debugPrint('❌ Message stream error: $error');
  });

  // Call notification listener
  _callsSub = supabase
      .from('call_notifications') 
      .stream(primaryKey: ['id'])
      .listen((List<Map<String, dynamic>> data) {
    _checkMissedCalls();
  }, onError: (error) {
    debugPrint('❌ Call notifications stream error: $error');
  });

  // Periodic updates to ensure sync
  Timer.periodic(Duration(seconds: 30), (timer) {
    if (mounted) {
      _updateNotificationCounts();
    }
  });
}

void _handleNewMessageNotification(String? senderId, Map<String, dynamic> message) {
  if (senderId == null) return;
  
  // Update counts
  _checkUnreadMessages();
  
  // Show notification if app is in background
  _showMessageNotification(senderId, message);
}

void _showMessageNotification(String senderId, Map<String, dynamic> message) {
  final content = message['content']?.toString() ?? 'New message';
  final senderName = message['sender_username']?.toString() ?? 'Someone';
  
  // You can integrate with flutter_local_notifications package here
  debugPrint('🔔 New message from $senderName: $content');
  
  // Optional: Show in-app snackbar if user is on a different screen
  if (mounted && ModalRoute.of(context)?.settings.name != '/chat') {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.message, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    senderName,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    content.length > 50 ? '${content.substring(0, 50)}...' : content,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: Colors.indigo,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
        duration: Duration(seconds: 3),
        action: SnackBarAction(
          label: 'View',
          textColor: Colors.white,
          onPressed: () {
            _navigateToChatFromNotification(senderId, senderName);
          },
        ),
      ),
    );
  }
}
Future<void> _navigateToChatFromNotification(String userId, String userName) async {
  // Mark messages as read when navigating to chat
  await _markMessagesAsRead(userId);
  
  // Wait a brief moment for state to update
  await Future.delayed(Duration(milliseconds: 100));
  
  if (mounted) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MenteeMessagingScreen(
          otherUserId: userId,
          otherUserName: userName,
        ),
      ),
    );
  }
}

  Future<void> _markMessagesAsRead(String senderId) async {
  try {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    debugPrint('📖 Marking messages as read from sender: $senderId');
    
    // Update messages in database - CORRECTED SYNTAX
    final response = await supabase
        .from('mentor_messages')
        .update({'is_read': true})
        .eq('receiver_id', userId)
        .eq('sender_id', senderId)
        .eq('is_read', false);

    // Check for errors using the response
    if (response.error != null) {
      debugPrint('❌ Database error marking messages as read: ${response.error!.message}');
      return;
    }

    // Update local state immediately
    if (mounted) {
      setState(() {
        _unreadMessagesByFriend.remove(senderId);
        // Recalculate total unread count
        _unreadMessagesCount = _unreadMessagesByFriend.values.fold(0, (sum, count) => sum + count);
        _hasNewNotifications = _pendingRequestsCount > 0 || _unreadMessagesCount > 0 || _missedCallsCount > 0;
      });
    }
    
    debugPrint('✅ Messages marked as read from $senderId');
  } catch (e) {
    debugPrint('❌ Error marking messages as read: $e');
  }
}

  Future<void> _checkMissedCalls() async {
  try {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    final response = await supabase
        .from('call_notifications')
        .select()
        .eq('receiver_id', userId)
        .eq('status', 'missed')
        .eq('is_read', false);

    if (mounted) {
      setState(() {
        _missedCallsCount = response.length;
      });
    }
  } catch (e) {
    debugPrint('❌ Error checking missed calls: $e');
  }
}



  Future<void> _initializeData() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      _loadingRetryCount = 0;
    });

    await _loadDataWithRetry();
    _setupRealtimeListeners();
    await _updateNotificationCounts();
  }


  Future<void> _loadDataWithRetry() async {
    while (_loadingRetryCount < maxRetries) {
      try {
        await _loadData();
        break; 
      } catch (e) {
        _loadingRetryCount++;
        debugPrint('❌ Load attempt $_loadingRetryCount failed: $e');
        
        if (_loadingRetryCount >= maxRetries) {
          if (mounted) {
            setState(() => _isLoading = false);
            _showErrorSnack('Failed to load data after $maxRetries attempts');
          }
          return;
        }
        
        await Future.delayed(Duration(seconds: _loadingRetryCount));
      }
    }
  }

  Future<void> _loadData() async {
    debugPrint('🔄 Loading friend data...');
    
    try {
      final results = await Future.wait([
        service.getPendingRequests().timeout(const Duration(seconds: 10)),
        service.getFriends().timeout(const Duration(seconds: 10)),
        service.getSuggestions().timeout(const Duration(seconds: 10)),
      ], eagerError: true);

      if (!mounted) return;

      setState(() {
        requests = results[0];
        friends = results[1];
        suggestions = results[2];
        searchResults = [];
        _isLoading = false;
        _isRefreshing = false;
        _pendingRequestsCount = requests.length;
      });
      
      debugPrint('✅ Loaded: ${friends.length} friends, ${requests.length} requests, ${suggestions.length} suggestions');
    } catch (e) {
      debugPrint('❌ Error in _loadData: $e');
      rethrow;
    }
  }

  void _setupRealtimeListeners() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('⚠️ No user ID for real-time listeners');
      return;
    }

    try {
      _requestsSub = supabase
          .from('mentor_friend_requests')
          .stream(primaryKey: ['id'])
          .listen((List<Map<String, dynamic>> data) {
        final filteredData = data.where((item) => 
          item['receiver_id'] == userId
        ).toList();
        
        if (filteredData.isNotEmpty) {
          debugPrint('🔔 Friend requests updated: ${filteredData.length} changes');
          _debouncedReloadData();
          _checkPendingRequests();
        }
      }, onError: (error) {
        debugPrint('❌ Friend requests stream error: $error');
      });

      _friendsSub = supabase
          .from('mentor_friends')
          .stream(primaryKey: ['id'])
          .listen((List<Map<String, dynamic>> data) {
        final filteredData = data.where((item) => 
          item['user1_id'] == userId || item['user2_id'] == userId
        ).toList();
        
        if (filteredData.isNotEmpty) {
          debugPrint('🔔 Friendships updated: ${filteredData.length} changes');
          _debouncedReloadData();
        }
      }, onError: (error) {
        debugPrint('❌ Friendships stream error: $error');
      });

      debugPrint('✅ Real-time listeners setup complete');
    } catch (e) {
      debugPrint('❌ Error setting up real-time listeners: $e');
    }
  }

  void _debouncedReloadData() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && !_isLoading) {
        _loadDataWithRetry();
      }
    });
  }

  Future<void> searchUsers(String query) async {
    if (query.isEmpty) {
      setState(() => searchResults = []);
      return;
    }
    
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final res = await service.searchUsers(query).timeout(const Duration(seconds: 8));
        if (!mounted) return;
        
        setState(() {
          searchResults = res;
        });
      } catch (e) {
        debugPrint('❌ Error searching users: $e');
        if (mounted) {
          _showErrorSnack('Search failed. Please try again.');
        }
      }
    });
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    
    setState(() => _isRefreshing = true);
    await _loadDataWithRetry();
    await _updateNotificationCounts();
  }

  void _showErrorSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(fontSize: bodyFontSize),
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(fontSize: bodyFontSize),
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildNotificationBadge(int count, {double size = 16}) {
    if (count <= 0) return SizedBox.shrink();
    
    return Container(
      padding: EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      constraints: BoxConstraints(
        minWidth: size,
        minHeight: size,
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.6,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  /// ✅ NEW: Build notification indicator (red exclamation point)
  Widget _buildNotificationIndicator() {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Center(
        child: Text(
          '!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

   @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.indigo,
          title: Row(
            children: [
              Text(
                "Friends",
                style: TextStyle(fontSize: titleFontSize),
              ),
              SizedBox(width: 8),
              // ✅ NEW: Main notification indicator
              if (_hasNewNotifications) _buildNotificationIndicator(),
            ],
          ),
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.lightBlueAccent,
            indicatorColor: Colors.white,
            labelStyle: TextStyle(
              fontSize: isVerySmallScreen ? 12 : 14,
              fontWeight: FontWeight.w500,
            ),
            unselectedLabelStyle: TextStyle(
              fontSize: isVerySmallScreen ? 12 : 14,
            ),
            tabs: [
              Tab(
                icon: Stack(
                  children: [
                    Icon(Icons.person_add, size: iconSize - 4),
                    // ✅ NEW: Notification badge for requests tab
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _buildNotificationBadge(_pendingRequestsCount, size: 16),
                    ),
                  ],
                ),
                text: isVerySmallScreen ? 'Requests' : 'Requests',
              ),
              Tab(
                icon: Stack(
                  children: [
                    Icon(Icons.people, size: iconSize - 4),
                    // ✅ NEW: Notification badge for friends tab (messages)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _buildNotificationBadge(_unreadMessagesCount, size: 16),
                    ),
                  ],
                ),
                text: isVerySmallScreen ? 'Friends' : 'Friends',
              ),
              Tab(
                icon: Icon(Icons.person_search, size: iconSize - 4),
                text: isVerySmallScreen ? 'Discover' : 'Discover',
              ),
            ],
          ),
        ),
        body: Column(
          children: [
            // ✅ ENHANCED: Mobile-optimized search bar
            Padding(
              padding: EdgeInsets.all(isSmallScreen ? 8.0 : 12.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: searchUsers,
                  decoration: InputDecoration(
                    hintText: "Search users...",
                    hintStyle: TextStyle(fontSize: bodyFontSize),
                    prefixIcon: Icon(Icons.search, size: iconSize - 4),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 16 : 20,
                      vertical: isSmallScreen ? 12 : 16,
                    ),
                    isDense: true,
                  ),
                  style: TextStyle(fontSize: bodyFontSize),
                ),
              ),
            ),

            // ✅ ENHANCED: Better loading indicators
            if (_isLoading && !_isRefreshing)
              LinearProgressIndicator(
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
              ),

            
            // ✅ NEW: Notification summary bar
if (_hasNewNotifications && !_isLoading)
  GestureDetector(
    onTap: _showNotificationDetails,
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border.all(color: Colors.orange.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      margin: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 12, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active, size: 16, color: Colors.orange.shade700),
              SizedBox(width: 8),
              Text(
                'New notifications',
                style: TextStyle(
                  fontSize: bodyFontSize - 2,
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          Row(
            children: [
              if (_pendingRequestsCount > 0) 
                _buildNotificationSummaryItem('Requests', _pendingRequestsCount),
              if (_unreadMessagesCount > 0) 
                _buildNotificationSummaryItem('Messages', _unreadMessagesCount),
              if (_missedCallsCount > 0) 
                _buildNotificationSummaryItem('Calls', _missedCallsCount),
              Icon(Icons.arrow_forward_ios, size: 12, color: Colors.orange.shade700),
            ],
          ),
        ],
      ),
    ),
  ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _handleRefresh,
                color: Colors.indigo,
                backgroundColor: Colors.white,
                child: TabBarView(
                  children: [
                    _buildRequests(),
                    _buildFriends(),
                    _buildSuggestions(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationSummaryItem(String label, int count) {
  return Padding(
    padding: EdgeInsets.only(left: 12),
    child: Row(
      children: [
        _buildNotificationBadge(count, size: 14),
        SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: bodyFontSize - 2),
        ),
      ],
    ),
  );
}

void _showNotificationDetails() {
  showModalBottomSheet(
    context: context,
    builder: (context) {
      return Container(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notifications',
              style: TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            if (_pendingRequestsCount > 0)
              _buildNotificationDetailItem(
                Icons.person_add,
                'Friend Requests',
                '$_pendingRequestsCount pending',
                Colors.blue,
              ),
            if (_unreadMessagesCount > 0)
              _buildNotificationDetailItem(
                Icons.message,
                'Unread Messages',
                '$_unreadMessagesCount unread',
                Colors.green,
              ),
            if (_missedCallsCount > 0)
              _buildNotificationDetailItem(
                Icons.phone_missed,
                'Missed Calls',
                '$_missedCallsCount missed',
                Colors.red,
              ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
              ),
              child: Text('Close'),
            ),
          ],
        ),
      );
    },
  );
}

Widget _buildNotificationDetailItem(IconData icon, String title, String subtitle, Color color) {
  return ListTile(
    leading: Icon(icon, color: color),
    title: Text(title),
    subtitle: Text(subtitle),
    trailing: _buildNotificationBadge(
      title.contains('Requests') ? _pendingRequestsCount :
      title.contains('Messages') ? _unreadMessagesCount : _missedCallsCount,
      size: 20,
    ),
  );
}

  Widget _buildRequests() {
    if (_isLoading && requests.isEmpty) {
      return _buildLoadingState('Loading requests...');
    }

    if (requests.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_add_disabled,
        title: 'No Pending Requests',
        subtitle: 'Friend requests will appear here',
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
      itemCount: requests.length,
      itemBuilder: (context, index) {
        final req = requests[index];
        final user = req['profiles_new'];
        if (user == null) return const SizedBox.shrink();

        final requestId = req['id']?.toString();
        final senderId = req['sender_id']?.toString();
        final username = user['username']?.toString() ?? 'Unknown User';
        final avatarUrl = user['avatar_url'] ?? '';
        final role = user['role']?.toString() ?? 'User';

        if (requestId == null || senderId == null) return const SizedBox.shrink();

        return _buildRequestCard(
          username: username,
          role: role,
          avatarUrl: avatarUrl,
          onAccept: () => _handleAcceptRequest(requestId, senderId, username),
          onReject: () => _handleRejectRequest(requestId),
          onChat: () => _handleChatWithSender(senderId),
        );
      },
    );
  }

  Widget _buildFriends() {
    if (_isLoading && friends.isEmpty) {
      return _buildLoadingState('Loading friends...');
    }

    if (friends.isEmpty) {
      return _buildEmptyState(
        icon: Icons.people_outline,
        title: 'No Friends Yet',
        subtitle: 'Add friends to start chatting',
      );
    }

    return ListView.separated(
      padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
      itemCount: friends.length,
      separatorBuilder: (_, __) => SizedBox(height: isSmallScreen ? 8 : 12),
      itemBuilder: (context, index) {
        final friend = friends[index];

        final id = friend['id']?.toString();
        final username = friend['username']?.toString() ?? 'Unknown User';
        final avatarUrl = friend['avatar_url']?.toString() ?? '';
        final role = friend['role']?.toString() ?? 'User';

        if (id == null) return const SizedBox.shrink();

        return _buildFriendCard(
          username: username,
          role: role,
          avatarUrl: avatarUrl,
          friendId: id,
          onChat: () => _handleChatWithFriend(id),
        );
      },
    );
  }

  Widget _buildSuggestions() {

    final list = searchResults.isNotEmpty ? searchResults : suggestions;

    if (_isLoading && list.isEmpty) {
      return _buildLoadingState('Loading suggestions...');
    }

    if (list.isEmpty) {
      return _buildEmptyState(
        icon: Icons.person_search,
        title: 'No Suggestions',
        subtitle: searchResults.isNotEmpty 
            ? 'No users found'
            : 'Try searching for users',
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final user = list[index]['profiles_new'] ?? list[index];
        final avatarUrl = user['avatar_url'] ?? '';
        final id = user['id']?.toString();
        final username = user['username']?.toString() ?? 'Unknown User';
        final role = user['role']?.toString() ?? 'User';

        if (id == null) return const SizedBox.shrink();

        return _buildSuggestionCard(
          username: username,
          role: role,
          avatarUrl: avatarUrl,
          onAdd: () => _handleSendRequest(id, username),
        );
      },
    );
  }

  // ========== ✅ ENHANCED: MOBILE-OPTIMIZED CARD WIDGETS ==========

  Widget _buildRequestCard({
    required String username,
    required String role,
    required String avatarUrl,
    required VoidCallback onAccept,
    required VoidCallback onReject,
    required VoidCallback onChat,
  }) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: _buildUserAvatar(avatarUrl, username),
        title: Text(
          username,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: bodyFontSize,
          ),
        ),
        subtitle: Text(
          role,
          style: TextStyle(
            fontSize: isSmallScreen ? 11 : 12,
            color: Colors.grey[600],
          ),
        ),
        trailing: ConstrainedBox(
          constraints: BoxConstraints(
          maxWidth: isVerySmallScreen ? 90 : 110,),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: IconButton(
                icon: Icon(Icons.check, size: iconSize - 6),
                color: Colors.green,
                onPressed: onAccept,
                tooltip: 'Accept',
                padding: isVerySmallScreen ? EdgeInsets.all(4) : EdgeInsets.all(8),
                constraints: BoxConstraints(
                  minWidth: isVerySmallScreen ? 32 : 40,
                ),
              ),
              ),
              Flexible(
              child: IconButton(
                icon: Icon(Icons.close, size: iconSize - 6),
                color: Colors.red,
                onPressed: onReject,
                tooltip: 'Reject',
                padding: isVerySmallScreen ? EdgeInsets.all(4) : EdgeInsets.all(8),
                constraints: BoxConstraints(
                  minWidth: isVerySmallScreen ? 32 : 40,
                ),
              ),
            ),
            Flexible(
              child: IconButton(
                icon: Icon(Icons.chat, size: iconSize - 6),
                color: Colors.indigo,
                onPressed: onChat,
                tooltip: 'Chat',
                padding: isVerySmallScreen ? EdgeInsets.all(4) : EdgeInsets.all(8),
                constraints: BoxConstraints(
                  minWidth: isVerySmallScreen ? 32 : 40,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildFriendCard({
  required String username,
  required String role,
  required String avatarUrl,
  required String friendId,
  required VoidCallback onChat,
}) {
  final unreadCount = _unreadMessagesByFriend[friendId] ?? 0;
  
  return Card(
    elevation: unreadCount > 0 ? 3 : 2,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    color: unreadCount > 0 ? Colors.blue.shade50 : null,
    child: ListTile(
      leading: Stack(
        children: [
          _buildUserAvatar(avatarUrl, username),
          if (unreadCount > 0)
            Positioned(
              top: 0,
              right: 0,
              child: _buildNotificationBadge(unreadCount, size: 16),
            ),
        ],
      ),
      title: Text(
        username,
        style: TextStyle(
          fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
          fontSize: bodyFontSize,
          color: unreadCount > 0 ? Colors.indigo : null,
        ),
      ),
      subtitle: Text(
        role,
        style: TextStyle(
          fontSize: isSmallScreen ? 11 : 12,
          color: unreadCount > 0 ? Colors.indigo.shade600 : Colors.grey[600],
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unreadCount > 0)
            Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(
                '$unreadCount',
                style: TextStyle(
                  color: Colors.indigo,
                  fontWeight: FontWeight.bold,
                  fontSize: bodyFontSize - 2,
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              Icons.chat_bubble_outline,
              size: iconSize - 4,
              color: unreadCount > 0 ? Colors.indigo : Colors.grey,
            ),
            onPressed: () async {
              if (mounted) {
                setState(() {
                  _unreadMessagesByFriend.remove(friendId);
                });
              }
              
              onChat();
            },
            tooltip: 'Start Chat',
          ),
        ],
      ),
      onTap: () async {
        if (mounted && unreadCount > 0) {
          setState(() {
            _unreadMessagesByFriend.remove(friendId);
          });
        }
        
        onChat();
      },
    ),
  );
}

  Widget _buildSuggestionCard({
    required String username,
    required String role,
    required String avatarUrl,
    required VoidCallback onAdd,
  }) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: _buildUserAvatar(avatarUrl, username),
        title: Text(
          username,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: bodyFontSize,
          ),
        ),
        subtitle: Text(
          role,
          style: TextStyle(
            fontSize: isSmallScreen ? 11 : 12,
            color: Colors.grey[600],
          ),
        ),
        trailing: IconButton(
          icon: Icon(Icons.person_add_alt_1, size: iconSize - 4),
          color: Colors.blue,
          onPressed: onAdd,
          tooltip: 'Add Friend',
        ),
      ),
    );
  }

  Widget _buildUserAvatar(String avatarUrl, String username) {
    return CircleAvatar(
      radius: isSmallScreen ? 20 : 24,
      backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
      backgroundColor: avatarUrl.isEmpty 
          ? Colors.primaries[username.codeUnitAt(0) % Colors.primaries.length]
          : Colors.grey.shade200,
      child: avatarUrl.isEmpty
          ? Text(
              username[0].toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: isSmallScreen ? 14 : 16,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );
  }

  Widget _buildLoadingState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
          ),
          SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: bodyFontSize,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: isSmallScreen ? 48 : 64,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: bodyFontSize,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: isSmallScreen ? 12 : 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ========== ✅ ENHANCED: MORE STABLE ACTION HANDLERS ==========

  Future<void> _handleAcceptRequest(String requestId, String senderId, String username) async {
    try {
      debugPrint('✅ Accepting request from $username...');
      
      await service.acceptRequest(requestId, senderId).timeout(const Duration(seconds: 10));
      
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (!mounted) return;
      
      _showSuccessSnack("You are now friends with $username");
      
      await _loadDataWithRetry();
      await _updateNotificationCounts();
    } catch (e) {
      debugPrint('❌ Error accepting request: $e');
      if (!mounted) return;
      _showErrorSnack("Failed to accept request");
    }
  }

  Future<void> _handleRejectRequest(String requestId) async {
    try {
      await service.rejectRequest(requestId).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      await _loadDataWithRetry();
      await _updateNotificationCounts();
    } catch (e) {
      debugPrint('❌ Error rejecting request: $e');
      if (!mounted) return;
      _showErrorSnack("Failed to reject request");
    }
  }

  Future<void> _handleChatWithSender(String senderId) async {
  try {
    final friend = await service.startChatWithFriend(senderId).timeout(const Duration(seconds: 10));
    if (friend == null) {
      if (!mounted) return;
      _showErrorSnack("You can only chat with friends");
      return;
    }
    
    // Mark messages as read BEFORE navigating
    await _markMessagesAsRead(senderId);
    
    // Wait for state update
    await Future.delayed(Duration(milliseconds: 100));
    
    if (!mounted) return;
    _navigateToChat(friend['id']!, friend['username']!);
  } catch (e) {
    debugPrint('❌ Error starting chat: $e');
    if (!mounted) return;
    _showErrorSnack("Failed to start chat");
  }
}

  Future<void> _handleChatWithFriend(String id) async {
  try {
    final friend = await service.startChatWithFriend(id).timeout(const Duration(seconds: 10));
    if (friend == null) {
      if (!mounted) return;
      _showErrorSnack("You can only chat with friends");
      return;
    }
    
    // Mark messages as read BEFORE navigating
    await _markMessagesAsRead(id);
    
    // Wait for state update
    await Future.delayed(Duration(milliseconds: 100));
    
    if (!mounted) return;
    _navigateToChat(friend['id']!, friend['username']!);
  } catch (e) {
    debugPrint('❌ Error starting chat: $e');
    if (!mounted) return;
    _showErrorSnack("Failed to start chat");
  }
}

  Future<void> _handleSendRequest(String id, String username) async {
    try {
      await service.sendRequest(id).timeout(const Duration(seconds: 10));
      if (!mounted) return;
      _showSuccessSnack("Friend request sent to $username");
      await _loadDataWithRetry();
    } catch (e) {
      debugPrint('❌ Error sending request: $e');
      if (!mounted) return;
      _showErrorSnack("Failed to send request");
    }
  }

  void _navigateToChat(String userId, String userName) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MenteeMessagingScreen(
        otherUserId: userId,
        otherUserName: userName,
      ),
    ),
  );
}}