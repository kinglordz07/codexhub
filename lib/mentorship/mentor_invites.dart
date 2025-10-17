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
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mentor Invites'),
        backgroundColor: Colors.indigo,
      ),
      body: RefreshIndicator(
        onRefresh: _loadInvites,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : invites.isEmpty
                ? const Center(child: Text('No pending invites'))
                : ListView.builder(
                    itemCount: invites.length,
                    itemBuilder: (context, index) {
                      final invite = invites[index];
                      final menteeName = invite['mentee_name']?.toString() ?? 'Unknown';
                      return Card(
                        margin: const EdgeInsets.all(8),
                        child: ListTile(
                          leading: const Icon(Icons.person, color: Colors.indigo),
                          title: Text('Mentee: $menteeName'),
                          subtitle: const Text('Tap to accept or decline'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check, color: Colors.green),
                                onPressed: () => _handleInvite(
                                  invite['id'].toString(),
                                  true,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.red),
                                onPressed: () => _handleInvite(
                                  invite['id'].toString(),
                                  false,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
  final service = LiveLobbyService();
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

  /// 🔹 Accept or decline an invite
 Future<void> _handleInvite(String inviteId, bool accept) async {
  try {
    // 1️⃣ Update the session status (returns session ID)
    final sessionIdRaw = await service.updateSessionStatus(inviteId, accept);

    if (!mounted) return;

    // 2️⃣ Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(accept ? '✅ Session accepted!' : '❌ Session declined.'),
      ),
    );

    // 3️⃣ Remove invite locally
    setState(() {
      invites.removeWhere((invite) => invite['id'] == inviteId);
    });

    debugPrint('[INVITE] accept=$accept, inviteId=$inviteId, session=$sessionIdRaw');

    if (!accept || sessionIdRaw == null) return;

    final supabase = Supabase.instance.client;

    // 4️⃣ Convert session ID safely (Supabase UUIDs are Strings)
    final sessionId = sessionIdRaw.toString();

    // ✅ Update mentor_id in live_sessions
    await supabase
        .from('live_sessions')
        .update({'mentor_id': widget.mentorId})
        .eq('id', sessionId);

    // ✅ Fetch updated session details
    final sessionDetails = await supabase
    .from('live_sessions')
    .select('id, room_id, mentee_id, mentor_id, code, is_live, waiting')
    .eq('id', sessionId)
    .maybeSingle();
final menteeName = 'Session'; // fallback
    if (sessionDetails == null ||
        sessionDetails['room_id'] == null ||
        sessionDetails['mentee_id'] == null) {
      debugPrint('⚠️ Missing required session data: $sessionDetails');
      return;
    }

    final roomId = sessionDetails['room_id'].toString();
    final menteeId = sessionDetails['mentee_id'].toString();
    final mentorId = sessionDetails['mentor_id']?.toString() ?? widget.mentorId;

    // ✅ Auto-join mentor to room_members
    final existing = await supabase
        .from('room_members')
        .select('id')
        .eq('room_id', roomId)
        .eq('user_id', mentorId)
        .maybeSingle();

    if (existing == null) {
      await supabase.from('room_members').insert({
        'room_id': roomId,
        'user_id': mentorId,
      });
      debugPrint('[INVITE] Mentor auto-joined to room_members.');
    } else {
      debugPrint('[INVITE] Mentor already in room_members.');
    }

    // ✅ Navigate to CollabRoomTabs
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => CollabRoomTabs(
          roomId: roomId,
          roomName: menteeName,
          menteeId: menteeId,
          mentorId: mentorId,
          isMentor: true,
        ),
      ),
    );
  } catch (e, st) {
    debugPrint('❌ Error updating session status: $e\n$st');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Failed to process invite.')),
    );
  }
}
}
