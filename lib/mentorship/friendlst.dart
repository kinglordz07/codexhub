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
  bool _isRefreshing = false;
  Timer? _debounceTimer;
  int _loadingRetryCount = 0;
  static const int maxRetries = 3;

  // ✅ ENHANCED: Mobile responsive detection
  bool get isSmallScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width < 600;
  }

  bool get isVerySmallScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width < 400;
  }

  // ✅ ENHANCED: Dynamic sizing for mobile
  double get titleFontSize => isVerySmallScreen ? 14 : (isSmallScreen ? 16 : 18);
  double get bodyFontSize => isVerySmallScreen ? 12 : (isSmallScreen ? 14 : 16);
  double get iconSize => isVerySmallScreen ? 18 : (isSmallScreen ? 20 : 24);

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _cleanupResources();
    super.dispose();
  }

  void _cleanupResources() {
    _requestsSub?.cancel();
    _friendsSub?.cancel();
    _debounceTimer?.cancel();
    _searchController.dispose();
    debugPrint('🔄 Resources cleaned up');
  }

  /// ✅ ENHANCED: Better initialization with retry logic
  Future<void> _initializeData() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
      _loadingRetryCount = 0;
    });

    await _loadDataWithRetry();
    _setupRealtimeListeners();
  }

  /// ✅ ENHANCED: Retry logic for unstable connections
  Future<void> _loadDataWithRetry() async {
    while (_loadingRetryCount < maxRetries) {
      try {
        await _loadData();
        break; // Success, exit retry loop
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
        
        // Wait before retry
        await Future.delayed(Duration(seconds: _loadingRetryCount));
      }
    }
  }

  /// ✅ ENHANCED: More stable data loading
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
      });
      
      debugPrint('✅ Loaded: ${friends.length} friends, ${requests.length} requests, ${suggestions.length} suggestions');
    } catch (e) {
      debugPrint('❌ Error in _loadData: $e');
      rethrow;
    }
  }

  /// ✅ FIXED: Correct Supabase stream implementation
  void _setupRealtimeListeners() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('⚠️ No user ID for real-time listeners');
      return;
    }

    try {
      // ✅ FIXED: Correct stream filtering for friend requests
      _requestsSub = supabase
          .from('mentor_friend_requests')
          .stream(primaryKey: ['id'])
          .listen((List<Map<String, dynamic>> data) {
        // Filter by receiver_id on the client side
        final filteredData = data.where((item) => 
          item['receiver_id'] == userId
        ).toList();
        
        if (filteredData.isNotEmpty) {
          debugPrint('🔔 Friend requests updated: ${filteredData.length} changes');
          _debouncedReloadData();
        }
      }, onError: (error) {
        debugPrint('❌ Friend requests stream error: $error');
      });

      // ✅ FIXED: Correct stream filtering for friendships
      _friendsSub = supabase
          .from('mentor_friends')
          .stream(primaryKey: ['id'])
          .listen((List<Map<String, dynamic>> data) {
        // Filter by user1_id or user2_id on the client side
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

  /// ✅ ENHANCED: Better debouncing with cancellation
  void _debouncedReloadData() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted && !_isLoading) {
        _loadDataWithRetry();
      }
    });
  }

  /// ✅ ENHANCED: Search with better error handling
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

  /// ✅ ENHANCED: Pull-to-refresh with visual feedback
  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    
    setState(() => _isRefreshing = true);
    await _loadDataWithRetry();
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.indigo,
          title: Text(
            "Friends",
            style: TextStyle(fontSize: titleFontSize),
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
                icon: Icon(Icons.person_add, size: iconSize - 4),
                text: isVerySmallScreen ? 'Requests' : 'Requests',
              ),
              Tab(
                icon: Icon(Icons.people, size: iconSize - 4),
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

            // ✅ ENHANCED: Tab content with pull-to-refresh
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

  /// ✅ ENHANCED: More stable requests tab
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

  /// ✅ ENHANCED: More stable friends tab
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
          onChat: () => _handleChatWithFriend(id),
        );
      },
    );
  }

  /// ✅ ENHANCED: More stable suggestions tab
  Widget _buildSuggestions() {
    // Use search results if available, otherwise use suggestions
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
        trailing: SizedBox(
          width: isVerySmallScreen ? 100 : 120,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.check, size: iconSize - 6),
                color: Colors.green,
                onPressed: onAccept,
                tooltip: 'Accept',
              ),
              IconButton(
                icon: Icon(Icons.close, size: iconSize - 6),
                color: Colors.red,
                onPressed: onReject,
                tooltip: 'Reject',
              ),
              IconButton(
                icon: Icon(Icons.chat, size: iconSize - 6),
                color: Colors.indigo,
                onPressed: onChat,
                tooltip: 'Chat',
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
        trailing: IconButton(
          icon: Icon(Icons.chat_bubble_outline, size: iconSize - 4),
          color: Colors.indigo,
          onPressed: onChat,
          tooltip: 'Start Chat',
        ),
        onTap: onChat,
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
      
      // Wait for database propagation
      await Future.delayed(const Duration(milliseconds: 300));
      
      if (!mounted) return;
      
      _showSuccessSnack("You are now friends with $username");
      
      // Reload data to update UI
      await _loadDataWithRetry();
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
  }
}