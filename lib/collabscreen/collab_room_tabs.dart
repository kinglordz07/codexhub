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
  final String sessionId; // ✅ ADDED: Critical for live_sessions updates

  const CollabRoomTabs({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.menteeId,
    required this.mentorId,
    required this.isMentor,
    required this.sessionId, // ✅ ADDED
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

  // For mentor invitation dialog
  final TextEditingController _mentorUsernameController = TextEditingController();
  bool _isInvitingMentor = false;

  // Responsive layout detection
  bool get isSmallScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width < 600;
  }

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

  // FIXED: UUID validation helper
  bool _isValidUUID(String? uuid) {
    if (uuid == null || uuid.isEmpty) return false;
    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );
    return uuidRegex.hasMatch(uuid);
  }

  // ✅ IMPROVED: Better initialization using existing session
Future<void> _initUserAndListen() async {
  currentUserId = supabase.auth.currentUser?.id;

  // ✅ USE THE PROVIDED SESSION ID FROM MENTOR INVITES
  liveSessionId = widget.sessionId;

  // FIXED: Better validation for roomId
  if (widget.roomId.isEmpty || !_isValidUUID(widget.roomId)) {
    debugPrint("❌ Error: roomId is empty or invalid UUID: ${widget.roomId}");
    if (mounted) {
      setState(() => _isInitializing = false);
    }
    return;
  }

  // ✅ ADDED: Validate sessionId before proceeding
  if (liveSessionId == null || liveSessionId!.isEmpty) {
    debugPrint("❌ Error: sessionId is null or empty");
    if (mounted) {
      setState(() => _isInitializing = false);
    }
    return;
  }

  try {
    debugPrint("🟡 Initializing room: ${widget.roomId}, session: $liveSessionId");

    // ✅ CHECK IF SESSION EXISTS AND GET LATEST DATA
    final session = await supabase
        .from('live_sessions')
        .select()
        .eq('id', liveSessionId!)
        .maybeSingle();

    if (session != null) {
      debugPrint("✅ Found existing live session");
      mentorId = session['mentor_id'] as String?;
      currentMenteeId = session['mentee_id'] as String?;
      
      // ✅ ENSURE CURRENT USER IS IN ROOM_MEMBERS
      await _ensureUserInRoom();
    } else {
      debugPrint("❌ Session not found: $liveSessionId");
      if (mounted) {
        setState(() => _isInitializing = false);
      }
      return;
    }

    await _checkIfViewer();

    // ✅ FIXED: Real-time updates with null safety
    _subscriptionListener = supabase
        .from('live_sessions')
        .stream(primaryKey: ['id'])
        .eq('id', liveSessionId!) // ✅ FIX: Add ! to assert not null
        .listen(
      (payload) {
        if (payload.isNotEmpty) {
          final data = payload.first;
          debugPrint("🔄 Live session update - mentor: ${data['mentor_id']}");
          if (mounted) {
            setState(() {
              mentorId = data['mentor_id'] as String?;
              currentMenteeId = data['mentee_id'] as String?;
            });
          }
        }
      },
      onError: (error) {
        debugPrint("❌ Live session stream error: $error");
      },
      cancelOnError: false,
    );

  } catch (e, st) {
    debugPrint("❌ Error in _initUserAndListen: $e\n$st");
  } finally {
    if (mounted) {
      setState(() => _isInitializing = false);
    }
  }
}

  // ✅ NEW: Ensure user is in room_members
  Future<void> _ensureUserInRoom() async {
    if (currentUserId == null) return;

    try {
      final existing = await supabase
          .from('room_members')
          .select('id')
          .eq('room_id', widget.roomId)
          .eq('user_id', currentUserId!)
          .maybeSingle();

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
          .eq('room_id', widget.roomId);

      final members = List<Map<String, dynamic>>.from(response);
      final isMember = members.any((m) => m['user_id'] == currentUserId);
      if (mounted) {
        setState(() => isViewer = isMember && !_amMentee && !_amMentor);
      }
    } catch (e) {
      debugPrint("⚠️ Error checking room membership: $e");
    }
  }

  /// =============================
  /// FIXED: Invite Mentor by Username
  /// =============================
  Future<void> inviteMentorByUsername(String username) async {
    if (currentUserId == null || !_amMentee) {
      _showSnack('Only the room creator (mentee) can invite a mentor.');
      return;
    }

    try {
      debugPrint('🔍 Searching for mentor with username: $username');

      // FIXED: Use profiles_new table with proper error handling
      final userResp = await supabase
          .from('profiles_new')
          .select('id, username, role')
          .eq('username', username.trim())
          .maybeSingle();

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

      // Check if the user is actually a mentor
      if (userRole != 'mentor') {
        _showSnack('This user is not a mentor. Only mentors can be invited.');
        return;
      }

      // Check if mentor is trying to invite themselves
      if (targetMentorId == currentUserId) {
        _showSnack('You cannot invite yourself as a mentor.');
        return;
      }

      debugPrint('✅ Found mentor: $targetMentorId, role: $userRole');

      // Proceed with mentor invitation
      await _inviteMentorById(targetMentorId);

    } catch (e, stack) {
      debugPrint('❌ Error inviting mentor by username: $e');
      debugPrint('Stack trace: $stack');
      _showSnack('Failed to invite mentor. Please try again.');
    }
  }

  /// =============================
  /// FIXED: Invite Mentor by User ID
  /// =============================
  Future<void> _inviteMentorById(String targetMentorId) async {
    try {
      final session = await supabase
          .from('live_sessions')
          .select()
          .eq('room_id', widget.roomId)
          .maybeSingle();

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

      // FIXED: Update live session with proper timestamp
      await supabase.from('live_sessions').update({
        'mentor_id': targetMentorId,
        'is_live': true,
        'last_editor': currentUserId,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('room_id', widget.roomId);

      _showSnack('Mentor invited successfully! Session is now live.');
      
      // Refresh the state
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

  /// =============================
  /// Show Mentor Invitation Dialog
  /// =============================
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
              title: const Text('Invite Mentor'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter the username of the mentor you want to invite:',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _mentorUsernameController,
                    decoration: const InputDecoration(
                      labelText: 'Mentor Username',
                      hintText: 'Enter username...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) {
                      if (!_isInvitingMentor) {
                        _inviteMentorFromDialog(setDialogState);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: _isInvitingMentor
                      ? null
                      : () {
                          Navigator.of(context).pop();
                        },
                  child: const Text('Cancel'),
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
                      : const Text('Invite'),
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
      // Remove current user from room_members
      await supabase
          .from('room_members')
          .delete()
          .eq('room_id', widget.roomId)
          .eq('user_id', currentUserId!);

      // Fetch remaining members
      final remainingResp = await supabase
          .from('room_members')
          .select('user_id')
          .eq('room_id', widget.roomId);

      final remaining = (remainingResp as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .toList();

      if (remaining.isNotEmpty) {
        // Pick a random member as the new creator
        final rnd = Random();
        final choice = remaining[rnd.nextInt(remaining.length)];
        final newCreatorId = choice['user_id'] as String;

        // Update rooms.creator_id
        await supabase
            .from('rooms')
            .update({'creator_id': newCreatorId})
            .eq('id', widget.roomId);

        // Update live_sessions. Mentee changes to new creator
        await supabase.from('live_sessions').update({
          'mentee_id': newCreatorId,
          'is_live': false
        }).eq('room_id', widget.roomId);

        _showSnack('You were removed. Room ownership transferred.');
      } else {
        // No members left — delete everything
        await supabase
            .from('live_sessions')
            .delete()
            .eq('room_id', widget.roomId);
        await supabase
            .from('room_members')
            .delete()
            .eq('room_id', widget.roomId);
        await supabase.from('rooms').delete().eq('id', widget.roomId);

        _showSnack('You were removed. Room was deleted.');
      }

      // Refresh local state
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

      _showSnack('You joined as mentor.');
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
      _showSnack('You left the mentoring session.');
      await _initUserAndListen();
    } catch (e) {
      debugPrint('❌ Error leaving as mentor: $e');
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
      ),
    );
  }

  Widget _buildRoleIndicator() {
    if (_amMentor) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 8 : 12,
          vertical: isSmallScreen ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: Colors.green.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green),
        ),
        child: Text(
          'Mentor',
          style: TextStyle(
            color: Colors.green,
            fontSize: isSmallScreen ? 12 : 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    } else if (_amMentee) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 8 : 12,
          vertical: isSmallScreen ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: Colors.blue.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue),
        ),
        child: Text(
          'Mentee',
          style: TextStyle(
            color: Colors.blue,
            fontSize: isSmallScreen ? 12 : 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    } else {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 8 : 12,
          vertical: isSmallScreen ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: Colors.grey.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey),
        ),
        child: Text(
          'Viewer',
          style: TextStyle(
            color: Colors.grey,
            fontSize: isSmallScreen ? 12 : 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
  }

  Widget _buildMentorInviteButton() {
    if (_amMentee && mentorId == null) {
      return IconButton(
        icon: Icon(
          Icons.person_add,
          size: isSmallScreen ? 20 : 24,
        ),
        tooltip: 'Invite Mentor',
        onPressed: _showInviteMentorDialog,
      );
    }
    return const SizedBox.shrink();
  }

  // FIXED: Loading state
  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading collaboration room...'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // FIXED: Show loading state while initializing
    if (_isInitializing) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.indigo,
          title: Text(widget.roomName),
        ),
        body: _buildLoadingState(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.roomName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _buildRoleIndicator(),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
            fontWeight: FontWeight.w500,
          ),
          unselectedLabelStyle: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
          ),
          tabs: [
            Tab(
              icon: Icon(
                Icons.chat,
                size: isSmallScreen ? 20 : 24,
              ),
              text: 'Chat',
            ),
            Tab(
              icon: Icon(
                Icons.code,
                size: isSmallScreen ? 20 : 24,
              ),
              text: 'Code Review',
            ),
          ],
        ),
        actions: [
          _buildMentorInviteButton(),
          if (_amMentor)
            IconButton(
              icon: Icon(
                Icons.exit_to_app,
                size: isSmallScreen ? 20 : 24,
              ),
              tooltip: 'Leave as Mentor',
              onPressed: mentorLeave,
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          CollabRoomScreen(
            roomId: widget.roomId,
            roomName: widget.roomName,
            isMentor: widget.isMentor,
          ),
          CollabCodeEditorScreen(
            roomId: widget.roomId,
            isReadOnly: !canEdit,
            isMentor: _amMentor,
            liveSessionId: liveSessionId ?? widget.sessionId, // ✅ CRITICAL: Use the session ID
          ),
        ],
      ),
    );
  }
}