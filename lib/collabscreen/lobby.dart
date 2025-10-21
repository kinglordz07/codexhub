import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'collab_room_tabs.dart';

class CollabLobbyScreen extends StatefulWidget {
  const CollabLobbyScreen({super.key});

  @override
  State<CollabLobbyScreen> createState() => _CollabLobbyScreenState();
}

class _CollabLobbyScreenState extends State<CollabLobbyScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> rooms = [];
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  // Create room
  Future<void> _createRoom(String name) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final room = await supabase
          .from('rooms')
          .insert({
            'name': name,
            'creator_id': user.id,
          })
          .select()
          .single();

      // Auto-join creator
      await supabase.from('room_members').insert({
        'room_id': room['id'],
        'user_id': user.id,
      });

      if (!mounted) return;

      // Check if there's a live session
      final session = await supabase
          .from('live_sessions')
          .select()
          .eq('room_id', room['id'])
          .maybeSingle();

      String mentorId = '';
      String menteeId = '';

      if (session != null) {
        mentorId = session['mentor_id'] ?? '';
        menteeId = session['mentee_id'] ?? '';
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CollabRoomTabs(
            roomId: room['id'].toString(),
            roomName: room['name'].toString(),
            isMentor: user.id == mentorId,
            mentorId: mentorId,
            menteeId: menteeId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating room: ${e.toString()}')),
      );
    }
  }

  // Fetch rooms
  Future<void> _fetchRooms() async {
    setState(() => isLoading = true);
    try {
      final response = await supabase
          .from('rooms')
          .select('id, name, creator_id, created_at, is_public')
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          rooms = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching rooms: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _showJoinRoomDialog() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in to join a room")),
      );
      return;
    }

    final roomIdController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Join Room"),
        content: TextField(
          controller: roomIdController,
          decoration: const InputDecoration(
            hintText: "Enter Room ID",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Join"),
          ),
        ],
      ),
    );

    if (result != true) return;

    final roomId = roomIdController.text.trim();
    if (roomId.isEmpty) return;

    await _joinRoom(roomId);
  }

  // Join room
  Future<void> _joinRoom(String roomId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Check if room exists
      final room =
          await supabase.from('rooms').select().eq('id', roomId).maybeSingle();

      if (room == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Room not found")));
        return;
      }

      // Add user if not already a member
      final existing = await supabase
          .from('room_members')
          .select()
          .eq('room_id', roomId)
          .eq('user_id', user.id);

      if (existing.isEmpty) {
        await supabase.from('room_members').insert({
          'room_id': roomId,
          'user_id': user.id,
        });
      }

      // Fetch live session
      final session = await supabase
          .from('live_sessions')
          .select()
          .eq('room_id', roomId)
          .maybeSingle();

      String mentorId = '';
      String menteeId = '';

      if (session != null) {
        mentorId = session['mentor_id'] ?? '';
        menteeId = session['mentee_id'] ?? '';
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CollabRoomTabs(
            roomId: roomId,
            roomName: room['name'],
            isMentor: user.id == mentorId,
            mentorId: mentorId,
            menteeId: menteeId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error joining room: ${e.toString()}')),
      );
    }
  }

  Future<void> _showCreateRoomDialog() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in to create a room")),
      );
      return;
    }

    final roomNameController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Create Room"),
        content: TextField(
          controller: roomNameController,
          decoration: const InputDecoration(
            hintText: "Enter room name",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Create"),
          ),
        ],
      ),
    );

    if (result != true) return;

    final name = roomNameController.text.trim();
    if (name.isEmpty) return;

    await _createRoom(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Collaboration Lobby"),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchRooms,
            tooltip: "Refresh rooms",
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showCreateRoomDialog,
                    icon: const Icon(Icons.add),
                    label: const Text("Create Room"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _showJoinRoomDialog,
                    icon: const Icon(Icons.login),
                    label: const Text("Join by ID"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              "Available Rooms:",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : rooms.isEmpty
                      ? const Center(child: Text("No rooms available. Create one!"))
                      : ListView.builder(
                          itemCount: rooms.length,
                          itemBuilder: (context, index) {
                            final room = rooms[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: const Icon(Icons.meeting_room),
                                title: Text(room['name']),
                                subtitle: Text("ID: ${room['id']}"),
                                trailing: IconButton(
                                  icon: const Icon(Icons.arrow_forward),
                                  onPressed: () => _joinRoom(room['id']),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
