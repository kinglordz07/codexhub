// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:codexhub01/collabscreen/collab_room_tabs.dart';
import '../services/live_lobby_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MentorInvites extends StatefulWidget {
  final String mentorId; // ✅ UUID string
  const MentorInvites({super.key, required this.mentorId});

  @override
  State<MentorInvites> createState() => _MentorInvitesState();
}

class _MentorInvitesState extends State<MentorInvites> {
  final service = LiveLobbyService();
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> invites = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  /// 🔹 Load all invites for this mentor (only pending ones)
  Future<void> _loadInvites() async {
    setState(() => isLoading = true);
    try {
      final data = await service.fetchInvitesForMentor(widget.mentorId);

      if (!mounted) return;

      setState(() {
        invites = data
            .where((invite) => invite['status']?.toString() == 'pending')
            .toList();
        isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading invites: $e');
      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load invites')),
      );
    }
  }

  /// 🔹 FIXED: Accept or decline an invite with proper flow
  Future<void> _handleInvite(String inviteId, bool accept) async {
    try {
      debugPrint('🎯 Handling invite: $inviteId, accept: $accept');

      // 1️⃣ Update the invitation status first
      await supabase
          .from('live_invitations')
          .update({
            'status': accept ? 'accepted' : 'declined',
            'responded_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', inviteId);

      // 2️⃣ Remove invite locally IMMEDIATELY
      setState(() {
        invites.removeWhere((invite) => invite['id'] == inviteId);
      });

      // 3️⃣ Show feedback
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? '✅ Session accepted!' : '❌ Session declined.'),
        ),
      );

      debugPrint('[INVITE] accept=$accept, inviteId=$inviteId');

      if (!accept) {
        // ❌ DECLINED: Just remove the invite and stop here
        debugPrint('❌ Invite declined, stopping here');
        return;
      }

      // ✅ ACCEPTED: Continue with session setup
      debugPrint('✅ Invite accepted, setting up session...');

      // 4️⃣ Get the session details from the invitation
      final invitation = await supabase
          .from('live_invitations')
          .select('session_id, mentee_id, mentee_name')
          .eq('id', inviteId)
          .maybeSingle();

      if (invitation == null) {
        debugPrint('❌ Invitation not found: $inviteId');
        return;
      }

      final sessionId = invitation['session_id']?.toString();
      final menteeId = invitation['mentee_id']?.toString();
      final menteeName = invitation['mentee_name']?.toString() ?? 'Mentee';

      if (sessionId == null || menteeId == null) {
        debugPrint('❌ Missing session_id or mentee_id in invitation');
        return;
      }

      debugPrint('🎯 Session ID: $sessionId, Mentee ID: $menteeId');

      // 5️⃣ Update the live_sessions table with mentor_id
      await supabase
          .from('live_sessions')
          .update({
            'mentor_id': widget.mentorId,
            'is_live': true,
            'waiting': false,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', sessionId);

      debugPrint('✅ Updated live_sessions with mentor_id');

      // 6️⃣ Get room_id from live_sessions
      final sessionDetails = await supabase
          .from('live_sessions')
          .select('room_id')
          .eq('id', sessionId)
          .maybeSingle();

      if (sessionDetails == null || sessionDetails['room_id'] == null) {
        debugPrint('❌ No room_id found for session: $sessionId');
        return;
      }

      final roomId = sessionDetails['room_id'].toString();
      debugPrint('🎯 Room ID: $roomId');

      // 7️⃣ Auto-join mentor to room_members
      final existing = await supabase
          .from('room_members')
          .select('id')
          .eq('room_id', roomId)
          .eq('user_id', widget.mentorId)
          .maybeSingle();

      if (existing == null) {
        await supabase.from('room_members').insert({
          'room_id': roomId,
          'user_id': widget.mentorId,
          'joined_at': DateTime.now().toUtc().toIso8601String(),
        });
        debugPrint('✅ Mentor auto-joined to room_members');
      } else {
        debugPrint('✅ Mentor already in room_members');
      }

      // 8️⃣ Update room to mark as active session
      await supabase
          .from('rooms')
          .update({'has_active_session': true})
          .eq('id', roomId);

      debugPrint('✅ Room marked as having active session');

      // 9️⃣ Navigate to CollabRoomTabs
      if (!mounted) return;

      debugPrint('🚀 Navigating to CollabRoomTabs...');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CollabRoomTabs(
            roomId: roomId,
            roomName: 'Session with $menteeName',
            menteeId: menteeId,
            mentorId: widget.mentorId,
            isMentor: true,
            sessionId: sessionId, // ✅ CRITICAL: Add sessionId
          ),
        ),
      );

    } catch (e, st) {
      debugPrint('❌ Error in _handleInvite: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to process invite: ${e.toString()}'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final isVerySmallScreen = screenSize.width < 400;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Mentor Invites',
          style: TextStyle(fontSize: isSmallScreen ? 18 : 20),
        ),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadInvites,
            tooltip: 'Refresh invites',
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadInvites,
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : invites.isEmpty
                  ? _buildEmptyState(isSmallScreen)
                  : ListView.builder(
                      padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                      itemCount: invites.length,
                      itemBuilder: (context, index) {
                        final invite = invites[index];
                        final menteeName = invite['mentee_name']?.toString() ?? 'Unknown Mentee';
                        final createdAt = _getInviteTime(invite);
                        return _buildInviteCard(
                          invite, 
                          menteeName, 
                          createdAt, 
                          isSmallScreen, 
                          isVerySmallScreen
                        );
                      },
                    ),
        ),
      ),
    );
  }

  String _getInviteTime(Map<String, dynamic> invite) {
    final createdAt = invite['created_at'];
    if (createdAt == null) return 'Recently';
    
    try {
      final dateTime = DateTime.parse(createdAt.toString());
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inMinutes < 1) return 'Just now';
      if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
      if (difference.inHours < 24) return '${difference.inHours}h ago';
      return '${difference.inDays}d ago';
    } catch (e) {
      return 'Recently';
    }
  }

  Widget _buildEmptyState(bool isSmallScreen) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 24 : 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: isSmallScreen ? 64 : 80,
              color: Colors.grey[400],
            ),
            SizedBox(height: isSmallScreen ? 16 : 20),
            Text(
              'No pending invites',
              style: TextStyle(
                fontSize: isSmallScreen ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: isSmallScreen ? 8 : 12),
            Text(
              'When mentees request live sessions,\ninvites will appear here',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                color: Colors.grey[500],
              ),
            ),
            SizedBox(height: isSmallScreen ? 16 : 20),
            ElevatedButton.icon(
              onPressed: _loadInvites,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteCard(
    Map<String, dynamic> invite, 
    String menteeName, 
    String timeAgo,
    bool isSmallScreen, 
    bool isVerySmallScreen
  ) {
    final inviteId = invite['id'].toString();

    return Card(
      margin: EdgeInsets.all(isSmallScreen ? 6 : 8),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person,
                  color: Colors.indigo,
                  size: isSmallScreen ? 20 : 24,
                ),
                SizedBox(width: isSmallScreen ? 8 : 12),
                Expanded(
                  child: Text(
                    'Live Session Request',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isSmallScreen ? 16 : 18,
                    ),
                  ),
                ),
                Text(
                  timeAgo,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 12 : 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 8 : 12),
            Text(
              'From: $menteeName',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                color: Colors.grey[700],
              ),
            ),
            SizedBox(height: isSmallScreen ? 4 : 6),
            Text(
              'Tap buttons below to accept or decline',
              style: TextStyle(
                fontSize: isSmallScreen ? 12 : 14,
                color: Colors.grey[500],
              ),
            ),
            SizedBox(height: isSmallScreen ? 12 : 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _handleInvite(inviteId, false),
                  icon: Icon(
                    Icons.close,
                    size: isSmallScreen ? 16 : 18,
                  ),
                  label: Text(
                    'Decline',
                    style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[50],
                    foregroundColor: Colors.red,
                    elevation: 0,
                  ),
                ),
                SizedBox(width: isSmallScreen ? 8 : 12),
                ElevatedButton.icon(
                  onPressed: () => _handleInvite(inviteId, true),
                  icon: Icon(
                    Icons.check,
                    size: isSmallScreen ? 16 : 18,
                  ),
                  label: Text(
                    'Accept & Join',
                    style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[50],
                    foregroundColor: Colors.green,
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}