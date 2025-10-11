import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:codexhub01/collabscreen/room.dart';

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

  Future<void> _fetchRooms() async {
    setState(() => isLoading = true);
    try {
      final response = await supabase
          .from('rooms')
          .select('id, name, owner_id, created_at');

      if (!mounted) return;
      setState(() {
        rooms = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error fetching rooms: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
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
      builder:
          (context) => AlertDialog(
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

  Future<void> _joinRoom(String roomId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Check if room exists
      final room =
          await supabase.from('rooms').select().eq('id', roomId).maybeSingle();

      if (room == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Room not found")));
        return;
      }

      // Check if user is already a member
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

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) =>
                  CollabRoomScreen(roomId: roomId, roomName: room['name']),
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
      builder:
          (context) => AlertDialog(
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

  Future<void> _createRoom(String name) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      final room =
          await supabase
              .from('rooms')
              .insert({'name': name, 'owner_id': user.id})
              .select()
              .single();

      // Auto-join owner
      await supabase.from('room_members').insert({
        'room_id': room['id'],
        'user_id': user.id,
      });

      if (!mounted) return;

      // Navigate to the new room
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (context) =>
                  CollabRoomScreen(roomId: room['id'], roomName: room['name']),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error creating room: ${e.toString()}')),
      );
    }
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
              child:
                  isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : rooms.isEmpty
                      ? const Center(
                        child: Text("No rooms available. Create one!"),
                      )
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
