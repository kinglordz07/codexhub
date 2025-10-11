import 'package:flutter/material.dart';
import '../services/live_lobby_service.dart';
import '../collabscreen/collabeditorscreen.dart';

class MentorInvites extends StatefulWidget {
  final String mentorId;
  const MentorInvites({super.key, required this.mentorId});

  @override
  State<MentorInvites> createState() => _MentorInvitesState();
}

class _MentorInvitesState extends State<MentorInvites> {
  final service = LiveLobbyService();
  List<Map<String, dynamic>> invites = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInvites();
  }

  Future<void> _loadInvites() async {
    setState(() => isLoading = true);
    try {
      final data = await service.fetchInvitesForMentor(widget.mentorId);
      if (!mounted) return;

      // Only show pending invites
      setState(() {
        invites =
            data.where((invite) => invite['status'] == 'pending').toList();
        isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading invites: $e');
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> _handleInvite(String inviteId, bool accept) async {
    try {
      final sessionId = await service.updateSessionStatus(inviteId, accept);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(accept ? 'Session accepted!' : 'Session declined.'),
        ),
      );

      // Remove processed invite from list
      setState(() => invites.removeWhere((invite) => invite['id'] == inviteId));

      // Navigate if accepted
      if (accept && sessionId != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder:
                (_) =>
                    CollabCodeEditorScreen(roomId: sessionId, isMentor: true),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error updating session status: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to process invite.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mentor Invites')),
      body: RefreshIndicator(
        onRefresh: _loadInvites, // pull to refresh pending invites
        child:
            isLoading
                ? const Center(child: CircularProgressIndicator())
                : invites.isEmpty
                ? const Center(child: Text('No pending invites'))
                : ListView.builder(
                  itemCount: invites.length,
                  itemBuilder: (context, index) {
                    final invite = invites[index];
                    final menteeName = invite['mentee_name'] ?? 'Unknown';

                    return Card(
                      margin: const EdgeInsets.all(8),
                      child: ListTile(
                        title: Text('Mentee: $menteeName'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.check,
                                color: Colors.green,
                              ),
                              onPressed:
                                  () => _handleInvite(invite['id'], true),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed:
                                  () => _handleInvite(invite['id'], false),
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
}
