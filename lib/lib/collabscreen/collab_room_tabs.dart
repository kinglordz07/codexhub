import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'collabeditorscreen.dart';
import 'room.dart';

class CollabRoomTabs extends StatefulWidget {
  final String roomId;
  final String roomName;
  final String menteeId;
  final String mentorId;
  final bool isMentor;
  final String sessionId;

  const CollabRoomTabs({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.menteeId,
    required this.mentorId,
    required this.isMentor,
    required this.sessionId,
  });

  @override
  State<CollabRoomTabs> createState() => _CollabRoomTabsState();
}

class _CollabRoomTabsState extends State<CollabRoomTabs>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final SupabaseClient supabase = Supabase.instance.client;

  String? currentUserId;
  String? mentorId;
  String? liveSessionId;
  String? currentMenteeId;
  bool _isInitializing = true;

  // ✅ REMOVED: _mentorUsernameController and _isInvitingMentor

  // ✅ REMOVED: All permission-related variables

  // ✅ ENHANCED: Better responsive detection
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

  // ✅ ENHANCED: Dynamic font sizes for mobile
  double get titleFontSize => isVerySmallScreen ? 14 : (isSmallScreen ? 16 : (isTablet ? 18 : 20));
  double get bodyFontSize => isVerySmallScreen ? 12 : (isSmallScreen ? 14 : 16);
  double get iconSize => isVerySmallScreen ? 18 : (isSmallScreen ? 20 : 24);
  double get buttonPadding => isVerySmallScreen ? 8 : (isSmallScreen ? 12 : 16);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initUserAndSession();
  }

  @override
  void dispose() {
    _tabController.dispose();
    // ✅ REMOVED: _mentorUsernameController disposal
    super.dispose();
  }

  bool _isValidUUID(String? uuid) {
    if (uuid == null || uuid.isEmpty) return false;
    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    return uuidRegex.hasMatch(uuid);
  }

  // ✅ SIMPLIFIED: Initialize user and session only
  Future<void> _initUserAndSession() async {
    currentUserId = supabase.auth.currentUser?.id;
    liveSessionId = widget.sessionId;

    // ✅ IMPROVED: Better validation
    if (widget.roomId.isEmpty || !_isValidUUID(widget.roomId)) {
      debugPrint("❌ Error: roomId is empty or invalid UUID: ${widget.roomId}");
      if (mounted) {
        setState(() => _isInitializing = false);
      }
      return;
    }

    if (liveSessionId == null || liveSessionId!.isEmpty) {
      debugPrint("❌ Error: sessionId is null or empty");
      if (mounted) {
        setState(() => _isInitializing = false);
      }
      return;
    }

    try {
      debugPrint("🟡 Initializing room: ${widget.roomId}, session: $liveSessionId");

      final session = await supabase
          .from('live_sessions')
          .select()
          .eq('id', liveSessionId!)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (session != null) {
        debugPrint("✅ Found existing live session");
        mentorId = session['mentor_id'] as String?;
        currentMenteeId = session['mentee_id'] as String?;
        
        await _ensureUserInRoom();
      } else {
        debugPrint("❌ Session not found: $liveSessionId");
        if (mounted) {
          setState(() => _isInitializing = false);
        }
        return;
      }

    } catch (e, st) {
      debugPrint("❌ Error in _initUserAndListen: $e\n$st");
      if (mounted) {
        _showSnack('Connection error. Please check your internet.');
      }
    } finally {
      if (mounted) {
        setState(() => _isInitializing = false);
      }
    }
  }

  // ✅ SIMPLIFIED: Just ensure user is in room
  Future<void> _ensureUserInRoom() async {
    if (currentUserId == null) return;

    try {
      final existing = await supabase
          .from('room_members')
          .select('id')
          .eq('room_id', widget.roomId)
          .eq('user_id', currentUserId!)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (existing == null) {
        debugPrint("👤 Adding user to room_members...");
        await supabase.from('room_members').insert({
          'room_id': widget.roomId,
          'user_id': currentUserId!,
          'role': 'member',
          'joined_at': DateTime.now().toUtc().toIso8601String(),
        });
        debugPrint("✅ User added to room_members");
      }
    } catch (e) {
      debugPrint("⚠️ Error ensuring user in room: $e");
    }
  }

  // ✅ SIMPLIFIED: Basic role checks
  bool get _amMentee =>
      currentUserId != null &&
      currentMenteeId != null &&
      currentUserId == currentMenteeId;
      
  bool get _amMentor =>
      currentUserId != null && 
      mentorId != null && 
      currentUserId == mentorId;

  // ✅ REMOVED: All mentor invitation methods
  // - inviteMentorByUsername
  // - _inviteMentorById
  // - _showInviteMentorDialog
  // - _inviteMentorFromDialog
  // - _autoKickCreator

  Future<void> acceptInviteAsMentor() async {
    if (currentUserId == null) return;
    try {
      await supabase.from('live_sessions').update({
        'mentor_id': currentUserId,
        'is_live': true,
        'last_editor': currentUserId
      }).eq('room_id', widget.roomId);

      _showSnack('🎯 You joined as mentor.');
      await _initUserAndSession();
    } catch (e) {
      debugPrint('❌ Error accepting invite as mentor: $e');
      _showSnack('Failed to join as mentor.');
    }
  }

  Future<void> mentorLeave() async {
    if (!_amMentor || currentUserId == null) return;
    try {
      await supabase.from('live_sessions').update({
        'mentor_id': null,
        'is_live': false
      }).eq('room_id', widget.roomId);
      _showSnack('👋 You left the mentoring session.');
      await _initUserAndSession();
    } catch (e) {
      debugPrint('❌ Error leaving as mentor: $e');
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: TextStyle(fontSize: bodyFontSize),
        ),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ✅ REMOVED: _buildRoleIndicator method

  // ✅ REMOVED: _buildMentorInviteButton method

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
            'Loading collaboration room...',
            style: TextStyle(
              fontSize: bodyFontSize,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Please wait',
            style: TextStyle(
              fontSize: isSmallScreen ? 12 : 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  // ✅ SIMPLIFIED: Clean app bar without room name and role indicators
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.indigo,
      elevation: 2,
      // ✅ REMOVED: title with room name
      // ✅ REMOVED: role indicator from title
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(isSmallScreen ? 40 : 48),
        child: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          labelStyle: TextStyle(
            fontSize: isVerySmallScreen ? 12 : 14,
            fontWeight: FontWeight.w500,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: isVerySmallScreen ? 12 : 14,
          ),
          tabs: [
            Tab(
              icon: Icon(
                Icons.chat_bubble_outline,
                size: isVerySmallScreen ? 18 : 20,
              ),
              text: isVerySmallScreen ? 'Chat' : 'Chat Room',
            ),
            Tab(
              icon: Icon(
                Icons.code,
                size: isVerySmallScreen ? 18 : 20,
              ),
              text: isVerySmallScreen ? 'Code' : 'Code Editor',
            ),
          ],
        ),
      ),
      // ✅ REMOVED: All actions (mentor invite button, leave button, etc.)
      actions: const [], // Empty actions
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        // ✅ SIMPLIFIED: Loading app bar without room name
        appBar: AppBar(
          backgroundColor: Colors.indigo,
          // ✅ REMOVED: title with room name
        ),
        body: _buildLoadingState(),
      );
    }

    // ✅ SIMPLIFIED: Just pass basic info to CodeEditor
    debugPrint("🎯 BUILD - Current User: $currentUserId");
    debugPrint("🎯 BUILD - Roles - Mentor: $_amMentor, Mentee: $_amMentee");

    return Scaffold(
      appBar: _buildAppBar(),
      body: SafeArea(
        bottom: false,
        child: TabBarView(
          controller: _tabController,
          children: [
            // Chat Tab
            CollabRoomScreen(
              roomId: widget.roomId,
              roomName: widget.roomName,
              isMentor: widget.isMentor,
            ),
            // Code Editor Tab - ✅ ALL PERMISSION LOGIC HANDLED IN CODE EDITOR
            CollabCodeEditorScreen(
              roomId: widget.roomId,
              isReadOnly: false, // ✅ Let CodeEditor handle permissions
              isMentor: _amMentor,
              liveSessionId: liveSessionId ?? widget.sessionId,
            ),
          ],
        ),
      ),
    );
  }
}