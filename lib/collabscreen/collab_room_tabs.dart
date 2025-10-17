import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'collabeditorscreen.dart';
import 'room.dart';

class CollabRoomTabs extends StatefulWidget {
  final String roomId;
  final String roomName;
  final String menteeId; // initial creator/mentee who created the room
  final String mentorId; // may be empty string if none
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
  String? currentMenteeId; // the mentee (creator) tracked from live_sessions
  bool isViewer = false;
  StreamSubscription<List<Map<String, dynamic>>>? _subscriptionListener;

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
      // load current live_session for this room (if exists)
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
        // ensure there is a live_sessions row for this room — create lightweight row if absent
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

      // Determine viewer status quickly (if user is member but not mentor/mentee)
      await _checkIfViewer();

      // Subscribe to realtime changes for live_sessions of this room (so code tab updates immediately)
      _subscriptionListener = supabase
          .from('live_sessions')
          .stream(primaryKey: ['id'])
          .eq('room_id', widget.roomId)
          .listen((payload) {
        if (payload.isNotEmpty) {
          final data = payload.first;
          setState(() {
            mentorId = data['mentor_id'] as String?;
            liveSessionId = data['id'] as String?;
            currentMenteeId = data['mentee_id'] as String?;
          });
        }
      });
    } catch (e, st) {
      debugPrint("❌ Error in _initUserAndListen: $e\n$st");
    }
  }

  /// Returns true if current user is the mentee/creator for this session
  bool get _amMentee =>
      currentUserId != null && currentMenteeId != null && currentUserId == currentMenteeId;

  bool get _amMentor => currentUserId != null && mentorId != null && currentUserId == mentorId;

  /// Editing allowed only for mentee (creator) and mentor
  bool get canEdit => _amMentee || _amMentor;

  /// Check if current user exists in room_members but is not mentor/mentee => viewer
  Future<void> _checkIfViewer() async {
    try {
      final response = await supabase
          .from('room_members')
          .select('user_id, role')
          .eq('room_id', widget.roomId);

      final members = List<Map<String, dynamic>>.from(response);
      final isMember = members.any((m) => m['user_id'] == currentUserId);

      if (isMember && !_amMentee && !_amMentor) {
        setState(() => isViewer = true);
      } else {
        setState(() => isViewer = false);
      }
    } catch (e) {
      debugPrint("⚠️ Error checking room membership: $e");
    }
  }

  // ===========================
  // Invite logic + Auto-kick
  // ===========================
  /// Called when the creator (mentee) tries to invite a mentor.
  /// If there's an active session and the same mentee tries to invite again -> auto-kick the mentee
  Future<void> inviteMentor(String targetMentorId) async {
    if (currentUserId == null) return;
    // Only the current mentee (creator) can invite a mentor
    if (!_amMentee) {
      _showSnack('Only the room creator (mentee) can invite a mentor.');
      return;
    }

    try {
      // fetch the live session again to have authoritative state
      final session = await supabase
          .from('live_sessions')
          .select()
          .eq('room_id', widget.roomId)
          .maybeSingle();

      if (session == null) {
        _showSnack('No live session found for this room.');
        return;
      }

      final bool isLive = session['is_live'] as bool? ?? false;
      final String sessionMenteeId = session['mentee_id'] as String? ?? '';

      // If the session is live and the creator tries to invite again -> auto-kick the creator (themself)
      if (isLive && sessionMenteeId == currentUserId) {
        debugPrint('⚠️ Creator attempted to re-invite while session active — auto-kicking creator.');

        // 1) remove creator from room_members
        if (currentUserId != null) {
  final delResp = await supabase
      .from('room_members')
      .delete()
      .eq('room_id', widget.roomId)
      .eq('user_id', currentUserId!);

  debugPrint('🗑️ Removed creator from room_members: $delResp');
} else {
  debugPrint('⚠️ currentUserId is null, skipping room member deletion.');
}
        // 2) find remaining members (excluding kicked creator)
        final remResp = await supabase
            .from('room_members')
            .select('user_id')
            .eq('room_id', widget.roomId);

        final remaining = List<Map<String, dynamic>>.from(remResp);
        if (remaining.isNotEmpty) {
          // pick random member to become new creator/mentee
          final rnd = Random();
          final choice = remaining[rnd.nextInt(remaining.length)];
          final newCreatorId = choice['user_id'] as String;

          // update rooms.creator_id
          await supabase
              .from('rooms')
              .update({'creator_id': newCreatorId})
              .eq('id', widget.roomId);

          // transfer mentee role in live_sessions to newCreatorId
          await supabase
              .from('live_sessions')
              .update({'mentee_id': newCreatorId, 'is_live': false})
              .eq('room_id', widget.roomId);

          debugPrint('🔁 Transferred room creator to $newCreatorId and set session inactive.');
          _showSnack('You were removed. Room ownership transferred to another member.');
        } else {
          // no members left -> delete everything related to room
          debugPrint('💀 No remaining members — deleting room and session.');

          // delete live_sessions row(s)
          await supabase.from('live_sessions').delete().eq('room_id', widget.roomId);
          // delete room_members (should be none)
          await supabase.from('room_members').delete().eq('room_id', widget.roomId);
          // delete room
          await supabase.from('rooms').delete().eq('id', widget.roomId);

          _showSnack('You were removed. Room was deleted because it is empty.');
        }

        // after auto-kick, leave the screen or refresh state
        // here we refresh local state
        await _initUserAndListen();
        return;
      }

      // If not live or mentee different, proceed normally: assign mentor and mark session live
      final updateResp = await supabase
          .from('live_sessions')
          .update({'mentor_id': targetMentorId, 'is_live': true, 'last_editor': currentUserId})
          .eq('room_id', widget.roomId);

      debugPrint('✅ Invite processed, session updated: $updateResp');
      _showSnack('Mentor invited — session is now live.');

      // refresh state
      await _initUserAndListen();
    } catch (e, st) {
      debugPrint('❌ Error inviting mentor: $e\n$st');
      _showSnack('Failed to invite mentor.');
    }
  }

  // Utility: show quick snackbar
  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // Exposed action: allow a mentor to accept invitation (optional)
  Future<void> acceptInviteAsMentor() async {
    if (currentUserId == null) return;
    try {
      // mark mentor as accepted by setting mentor_id in live_sessions (if not already)
      await supabase
          .from('live_sessions')
          .update({'mentor_id': currentUserId, 'is_live': true, 'last_editor': currentUserId})
          .eq('room_id', widget.roomId);

      _showSnack('You joined as mentor.');
      await _initUserAndListen();
    } catch (e) {
      debugPrint('❌ Error accepting invite as mentor: $e');
      _showSnack('Failed to join as mentor.');
    }
  }

  // Optional: allow mentor to leave (clears mentor_id and sets is_live false)
  Future<void> mentorLeave() async {
    if (currentUserId == null) return;
    if (!_amMentor) return;

    try {
      await supabase
          .from('live_sessions')
          .update({'mentor_id': null, 'is_live': false})
          .eq('room_id', widget.roomId);

      _showSnack('You left the mentoring session.');
      await _initUserAndListen();
    } catch (e) {
      debugPrint('❌ Error leaving as mentor: $e');
    }
  }

  // ===========================
  // UI
  // ===========================
  @override
  Widget build(BuildContext context) {
    // re-evaluate viewer state every build (lightweight)
    _checkIfViewer();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomName),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.chat), text: 'Chat'),
            Tab(icon: Icon(Icons.code), text: 'Code Review'),
          ],
        ),
        actions: [
          // if current user is creator (mentee), show "Invite Mentor" button for demo/testing
          if (_amMentee)
            IconButton(
              icon: const Icon(Icons.person_add),
              tooltip: 'Invite Mentor (test)',
              onPressed: () async {
                // For demo purposes: prompt input for mentor id
                final id = await _promptForId(context, 'Enter mentor user id to invite');
                if (id != null && id.isNotEmpty) {
                  await inviteMentor(id.trim());
                }
              },
            ),

          // if current user is mentor and is in session, offer leave action
          if (_amMentor)
            IconButton(
              icon: const Icon(Icons.exit_to_app),
              tooltip: 'Leave as Mentor',
              onPressed: mentorLeave,
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Chat tab (you already have CollabRoomScreen)
          CollabRoomScreen(
            roomId: widget.roomId,
            roomName: widget.roomName,
            isMentor: widget.isMentor,
          ),

          // Code editor always visible. Editing allowed only for mentee & mentor.
          CollabCodeEditorScreen(
            roomId: widget.roomId,
            isReadOnly: !canEdit,
            isMentor: _amMentor,
            liveSessionId: liveSessionId ?? '',
          ),
        ],
      ),
      floatingActionButton: _amMentee
          ? FloatingActionButton.extended(
              label: const Text('Invite Mentor'),
              icon: const Icon(Icons.person_add),
              onPressed: () async {
                final id = await _promptForId(context, 'Enter mentor user id to invite');
                if (id != null && id.isNotEmpty) {
                  await inviteMentor(id.trim());
                }
              },
            )
          : null,
    );
  }

  // simple helper to ask for mentor id (for demo/testing)
  Future<String?> _promptForId(BuildContext ctx, String title) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: 'user id (uuid)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dctx).pop(null), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dctx).pop(controller.text), child: const Text('OK')),
        ],
      ),
    );
  }
}
