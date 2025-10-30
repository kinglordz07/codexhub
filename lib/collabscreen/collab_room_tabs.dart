import 'dart:async';
import 'dart:math';

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
  bool isViewer = false;
  bool _isInitializing = true;
  StreamSubscription<List<Map<String, dynamic>>>? _subscriptionListener;

  final TextEditingController _mentorUsernameController = TextEditingController();
  bool _isInvitingMentor = false;

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
    _initUserAndListen();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _subscriptionListener?.cancel();
    _mentorUsernameController.dispose();
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

  // ✅ ENHANCED: Better initialization with mobile optimization
  Future<void> _initUserAndListen() async {
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
          .timeout(const Duration(seconds: 10)); // ✅ ADDED: Timeout for mobile

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

      await _checkIfViewer();

      // ✅ ENHANCED: Better real-time subscription with mobile optimization
      _subscriptionListener = supabase
          .from('live_sessions')
          .stream(primaryKey: ['id'])
          .eq('id', liveSessionId!)
          .listen(
        (payload) {
          if (payload.isNotEmpty && mounted) {
            final data = payload.first;
            debugPrint("🔄 Live session update - mentor: ${data['mentor_id']}");
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  mentorId = data['mentor_id'] as String?;
                  currentMenteeId = data['mentee_id'] as String?;
                });
              }
            });
          }
        },
        onError: (error) {
          debugPrint("❌ Live session stream error: $error");
        },
        cancelOnError: true,
      );

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

  bool get _amMentee =>
      currentUserId != null &&
      currentMenteeId != null &&
      currentUserId == currentMenteeId;
      
  bool get _amMentor =>
      currentUserId != null && 
      mentorId != null && 
      currentUserId == mentorId;
      
  bool get canEdit => _amMentee || _amMentor;

  Future<void> _checkIfViewer() async {
    try {
      final response = await supabase
          .from('room_members')
          .select('user_id')
          .eq('room_id', widget.roomId)
          .timeout(const Duration(seconds: 5));

      final members = List<Map<String, dynamic>>.from(response);
      final isMember = members.any((m) => m['user_id'] == currentUserId);
      if (mounted) {
        setState(() => isViewer = isMember && !_amMentee && !_amMentor);
      }
    } catch (e) {
      debugPrint("⚠️ Error checking room membership: $e");
    }
  }

  // ✅ ENHANCED: Mobile-optimized mentor invitation
  Future<void> inviteMentorByUsername(String username) async {
    if (currentUserId == null || !_amMentee) {
      _showSnack('Only the room creator (mentee) can invite a mentor.');
      return;
    }

    try {
      debugPrint('🔍 Searching for mentor with username: $username');

      final userResp = await supabase
          .from('profiles_new')
          .select('id, username, role')
          .eq('username', username.trim())
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (userResp == null) {
        _showSnack('Mentor not found. Please check the username.');
        return;
      }

      final targetMentorId = userResp['id'] as String?;
      final userRole = userResp['role'] as String?;

      if (targetMentorId == null) {
        _showSnack('Mentor ID not found.');
        return;
      }

      if (userRole != 'mentor') {
        _showSnack('This user is not a mentor. Only mentors can be invited.');
        return;
      }

      if (targetMentorId == currentUserId) {
        _showSnack('You cannot invite yourself as a mentor.');
        return;
      }

      debugPrint('✅ Found mentor: $targetMentorId, role: $userRole');
      await _inviteMentorById(targetMentorId);

    } catch (e, stack) {
      debugPrint('❌ Error inviting mentor by username: $e\n$stack');
      _showSnack('Failed to invite mentor. Please check your connection.');
    }
  }

  Future<void> _inviteMentorById(String targetMentorId) async {
    try {
      final session = await supabase
          .from('live_sessions')
          .select()
          .eq('room_id', widget.roomId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (session == null) {
        _showSnack('No live session found.');
        return;
      }

      final isLive = session['is_live'] as bool? ?? false;
      final sessionMenteeId = session['mentee_id'] as String? ?? '';

      if (isLive && sessionMenteeId == currentUserId) {
        await _autoKickCreator();
        return;
      }

      await supabase.from('live_sessions').update({
        'mentor_id': targetMentorId,
        'is_live': true,
        'last_editor': currentUserId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('room_id', widget.roomId);

      _showSnack('🎉 Mentor invited successfully! Session is now live.');
      
      if (mounted) {
        setState(() {
          mentorId = targetMentorId;
        });
      }

    } catch (e, stack) {
      debugPrint('❌ Error in _inviteMentorById: $e\n$stack');
      _showSnack('Failed to invite mentor. Please try again.');
    }
  }

  // ✅ ENHANCED: Mobile-optimized dialog
  Future<void> _showInviteMentorDialog() async {
    if (!_amMentee) {
      _showSnack('Only mentees can invite mentors.');
      return;
    }

    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Invite Mentor',
                style: TextStyle(fontSize: titleFontSize),
              ),
              content: SizedBox(
                width: double.maxFinite, // ✅ FIXED: Better mobile width
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Enter the username of the mentor you want to invite:',
                      style: TextStyle(
                        fontSize: bodyFontSize,
                        color: Colors.grey[700],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _mentorUsernameController,
                      decoration: InputDecoration(
                        labelText: 'Mentor Username',
                        hintText: 'Enter username...',
                        border: const OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(buttonPadding),
                      ),
                      style: TextStyle(fontSize: bodyFontSize),
                      onSubmitted: (_) {
                        if (!_isInvitingMentor) {
                          _inviteMentorFromDialog(setDialogState);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isInvitingMentor
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          _mentorUsernameController.clear();
                        },
                  child: Text(
                    'Cancel',
                    style: TextStyle(fontSize: bodyFontSize),
                  ),
                ),
                ElevatedButton(
                  onPressed: _isInvitingMentor
                      ? null
                      : () {
                          _inviteMentorFromDialog(setDialogState);
                        },
                  child: _isInvitingMentor
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        )
                      : Text(
                          'Invite',
                          style: TextStyle(fontSize: bodyFontSize),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _inviteMentorFromDialog(void Function(void Function()) setDialogState) async {
    final username = _mentorUsernameController.text.trim();
    
    if (username.isEmpty) {
      _showSnack('Please enter a username.');
      return;
    }

    setDialogState(() {
      _isInvitingMentor = true;
    });

    try {
      await inviteMentorByUsername(username);
      if (mounted) {
        Navigator.of(context).pop();
        _mentorUsernameController.clear();
      }
    } finally {
      setDialogState(() {
        _isInvitingMentor = false;
      });
    }
  }

  Future<void> _autoKickCreator() async {
    if (currentUserId == null) return;

    try {
      await supabase
          .from('room_members')
          .delete()
          .eq('room_id', widget.roomId)
          .eq('user_id', currentUserId!);

      final remainingResp = await supabase
          .from('room_members')
          .select('user_id')
          .eq('room_id', widget.roomId);

      final remaining = (remainingResp as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();

      if (remaining.isNotEmpty) {
        final rnd = Random();
        final choice = remaining[rnd.nextInt(remaining.length)];
        final newCreatorId = choice['user_id'] as String;

        await supabase
            .from('rooms')
            .update({'creator_id': newCreatorId})
            .eq('id', widget.roomId);

        await supabase.from('live_sessions').update({
          'mentee_id': newCreatorId,
          'is_live': false
        }).eq('room_id', widget.roomId);

        _showSnack('👋 You were removed. Room ownership transferred.');
      } else {
        await supabase
            .from('live_sessions')
            .delete()
            .eq('room_id', widget.roomId);
        await supabase
            .from('room_members')
            .delete()
            .eq('room_id', widget.roomId);
        await supabase.from('rooms').delete().eq('id', widget.roomId);

        _showSnack('👋 You were removed. Room was deleted.');
      }

      await _initUserAndListen();
    } catch (e) {
      debugPrint('❌ Error in _autoKickCreator: $e');
      _showSnack('Error transferring room ownership.');
    }
  }

  Future<void> acceptInviteAsMentor() async {
    if (currentUserId == null) return;
    try {
      await supabase.from('live_sessions').update({
        'mentor_id': currentUserId,
        'is_live': true,
        'last_editor': currentUserId
      }).eq('room_id', widget.roomId);

      _showSnack('🎯 You joined as mentor.');
      await _initUserAndListen();
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
      await _initUserAndListen();
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

  // ✅ ENHANCED: Mobile-optimized role indicator
  Widget _buildRoleIndicator() {
    String roleText;
    Color roleColor;
    String emoji;

    if (_amMentor) {
      roleText = 'Mentor';
      roleColor = Colors.green;
      emoji = '👨‍🏫';
    } else if (_amMentee) {
      roleText = 'Mentee';
      roleColor = Colors.blue;
      emoji = '👨‍🎓';
    } else {
      roleText = 'Viewer';
      roleColor = Colors.grey;
      emoji = '👀';
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isVerySmallScreen ? 6 : 8,
        vertical: isVerySmallScreen ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: roleColor.withAlpha(30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: roleColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isVerySmallScreen) Text(emoji),
          if (!isVerySmallScreen) SizedBox(width: 4),
          Text(
            roleText,
            style: TextStyle(
              color: roleColor,
              fontSize: isVerySmallScreen ? 10 : 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ✅ ENHANCED: Mobile-optimized mentor invite button
  Widget _buildMentorInviteButton() {
    if (_amMentee && mentorId == null) {
      return IconButton(
        icon: Icon(
          Icons.person_add_alt_rounded,
          size: iconSize,
          color: Colors.white,
        ),
        tooltip: 'Invite Mentor',
        onPressed: _showInviteMentorDialog,
      );
    }
    return const SizedBox.shrink();
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

  // ✅ ENHANCED: Mobile-optimized app bar
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.indigo,
      elevation: 2,
      title: Row(
        children: [
          Expanded(
            child: Text(
              widget.roomName,
              style: TextStyle(
                color: Colors.white,
                fontSize: titleFontSize,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          SizedBox(width: isVerySmallScreen ? 4 : 8),
          _buildRoleIndicator(),
        ],
      ),
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
      actions: [
        _buildMentorInviteButton(),
        if (_amMentor)
          IconButton(
            icon: Icon(
              Icons.logout,
              size: iconSize,
              color: Colors.white,
            ),
            tooltip: 'Leave as Mentor',
            onPressed: mentorLeave,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.indigo,
          title: Text(
            widget.roomName,
            style: TextStyle(fontSize: titleFontSize),
          ),
        ),
        body: _buildLoadingState(),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: SafeArea(
        bottom: false, // ✅ IMPORTANT: Better mobile safe area handling
        child: TabBarView(
          controller: _tabController,
          children: [
            // Chat Tab
            CollabRoomScreen(
              roomId: widget.roomId,
              roomName: widget.roomName,
              isMentor: widget.isMentor,
            ),
            // Code Editor Tab
            CollabCodeEditorScreen(
              roomId: widget.roomId,
              isReadOnly: !canEdit,
              isMentor: _amMentor,
              liveSessionId: liveSessionId ?? widget.sessionId,
            ),
          ],
        ),
      ),
    );
  }
}