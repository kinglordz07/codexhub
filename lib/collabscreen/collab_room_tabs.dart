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

  const CollabRoomTabs({
    super.key,
    required this.roomId,
    required this.roomName,
    required this.menteeId,
    required this.mentorId,
    required this.isMentor,
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
  StreamSubscription<List<Map<String, dynamic>>>? _subscriptionListener;

  // Responsive layout detection
  bool get isSmallScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width < 600;
  }

  bool get isMediumScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width >= 600 && mediaQuery.size.width < 1024;
  }

  bool get isLargeScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width >= 1024;
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
    super.dispose();
  }

  Future<void> _initUserAndListen() async {
    currentUserId = supabase.auth.currentUser?.id;

    if (widget.roomId.isEmpty) {
      debugPrint("❌ Error: roomId is empty.");
      return;
    }

    try {
      // Load or create live session
      final session = await supabase
          .from('live_sessions')
          .select()
          .eq('room_id', widget.roomId)
          .maybeSingle();

      if (session != null) {
        liveSessionId = session['id'] as String?;
        mentorId = session['mentor_id'] as String?;
        currentMenteeId = session['mentee_id'] as String?;
      } else {
        final created = await supabase.from('live_sessions').insert({
          'room_id': widget.roomId,
          'mentee_id': widget.menteeId,
          'mentor_id': null,
          'code': '',
          'is_live': false,
          'waiting': false,
          'language': 'python',
        }).select().maybeSingle();

        if (created != null) {
          liveSessionId = created['id'] as String?;
          mentorId = created['mentor_id'] as String?;
          currentMenteeId = created['mentee_id'] as String?;
        }
      }

      await _checkIfViewer();

      // Realtime subscription for live_sessions
      _subscriptionListener = supabase
          .from('live_sessions')
          .stream(primaryKey: ['id'])
          .eq('room_id', widget.roomId)
          .listen((payload) {
        if (payload.isNotEmpty) {
          final data = payload.first;
          if (mounted) {
            setState(() {
              mentorId = data['mentor_id'] as String?;
              liveSessionId = data['id'] as String?;
              currentMenteeId = data['mentee_id'] as String?;
            });
          }
        }
      });
    } catch (e, st) {
      debugPrint("❌ Error in _initUserAndListen: $e\n$st");
    }
  }

  bool get _amMentee =>
      currentUserId != null &&
      currentMenteeId != null &&
      currentUserId == currentMenteeId;
  bool get _amMentor =>
      currentUserId != null && mentorId != null && currentUserId == mentorId;
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
  /// Invite Mentor by User ID
  /// =============================
  Future<void> inviteMentor(String targetMentorId) async {
    if (currentUserId == null || !_amMentee) {
      _showSnack('Only the room creator (mentee) can invite a mentor.');
      return;
    }

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

      await supabase.from('live_sessions').update({
        'mentor_id': targetMentorId,
        'is_live': true,
        'last_editor': currentUserId
      }).eq('room_id', widget.roomId);

      _showSnack('Mentor invited — session is now live.');
      await _initUserAndListen();
    } catch (e, st) {
      debugPrint('❌ Error inviting mentor: $e\n$st');
      _showSnack('Failed to invite mentor.');
    }
  }

  Future<void> _autoKickCreator() async {
    if (currentUserId == null) return;

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
  }

  /// =============================
  /// Invite Mentor by Username
  /// =============================
  Future<void> inviteMentorByUsername(String username) async {
    try {
      final userResp = await supabase
          .from('users')
          .select('id')
          .eq('username', username)
          .maybeSingle();
      final targetMentorId = userResp?['id'] as String?;
      if (targetMentorId == null) {
        _showSnack('User not found.');
        return;
      }
      await inviteMentor(targetMentorId);
    } catch (e) {
      debugPrint('❌ Error inviting mentor by username: $e');
      _showSnack('Failed to invite mentor.');
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

  @override
  Widget build(BuildContext context) {
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
            liveSessionId: liveSessionId ?? '',
          ),
        ],
      ),
    );
  }
}