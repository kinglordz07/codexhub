import 'package:flutter/material.dart';
import '../services/live_lobby_service.dart';
import '../collabscreen/collab_room_tabs.dart';

class CreateLiveLobby extends StatefulWidget {
  final String menteeId;
  final String menteeName;
  
  final bool isMentor;

  const CreateLiveLobby({
    super.key,
    required this.menteeId,
    required this.menteeName, 
    required this.isMentor,
  });

  @override
  State<CreateLiveLobby> createState() => _CreateLiveLobbyState();
}

class _CreateLiveLobbyState extends State<CreateLiveLobby> {
  final service = LiveLobbyService();
  List<Map<String, dynamic>> mentors = [];
  String? selectedMentorId;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMentors();
  }

  Future<void> _loadMentors() async {
    try {
      final result = await service.fetchMentors();
      if (!mounted) return;

      setState(() => mentors = result);
    } catch (e) {
      debugPrint('❌ Error loading mentors: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load mentors')),
        );
      }
    }
  }

  Future<void> _createLobby() async {
    if (selectedMentorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a mentor')),
      );
      return;
    }

  setState(() => isLoading = true);
  debugPrint('🟡 _createLobby: Start');

    try {
      debugPrint('🟡 _createLobby: Calling createLiveSession');
      final sessionResult = await service.createLiveSession(
        widget.menteeId,
        selectedMentorId!,
        widget.menteeName,
      );
      debugPrint('🟢 _createLobby: createLiveSession result: $sessionResult');

      if (sessionResult == null) {
        debugPrint('🔴 _createLobby: sessionResult is null');
        throw Exception('Failed to create session');
      }

      final String roomId = sessionResult['roomId'] ?? '';
      final String roomName = sessionResult['roomName'] ?? 'Live Room';
      final String menteeId = widget.menteeId;

      debugPrint('🟢 _createLobby: roomId=$roomId, roomName=$roomName, menteeId=$menteeId');

      if (!mounted) {
        debugPrint('🔴 _createLobby: Not mounted after session creation');
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mentor invited successfully!')),
      );

      debugPrint('🟢 _createLobby: Navigating to CollabRoomTabs');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CollabRoomTabs(
            roomId: roomId,
            roomName: roomName,
            menteeId: menteeId,
            isMentor: false,
            mentorId: '', // or true, depending on context
          ),
        ),
      );
      setState(() => selectedMentorId = null);
    } catch (e) {
      debugPrint('❌ Error creating live session: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create live session: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invite a Mentor'),
        backgroundColor: Colors.indigo,
        elevation: 2,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: mentors.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select a Mentor:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Choose Mentor',
                    ),
                    initialValue: selectedMentorId,
                    items: mentors.map((mentor) {
                      return DropdownMenuItem<String>(
                        value: mentor['id'].toString(),
                        child: Text(
                          mentor['username'] ?? 'Unknown Mentor',
                          style: const TextStyle(fontSize: 15),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) =>
                        setState(() => selectedMentorId = value),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _createLobby,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 40,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Invite Mentor',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
