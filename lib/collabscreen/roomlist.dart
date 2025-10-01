import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:codexhub01/collabscreen/room.dart';

class RoomListScreen extends StatefulWidget {
  const RoomListScreen({super.key});

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _rooms = [];
  final TextEditingController _roomController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    final response = await supabase.from('rooms').select().order('created_at');
    setState(() {
      _rooms = List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> _createRoom() async {
    final user = supabase.auth.currentUser;
    if (user == null || _roomController.text.trim().isEmpty) return;

    await supabase.from('rooms').insert({
      'name': _roomController.text.trim(),
      'created_by': user.id,
    });

    _roomController.clear();
    _loadRooms();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Collaboration Rooms")),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _rooms.length,
              itemBuilder: (context, index) {
                final room = _rooms[index];
                return ListTile(
                  title: Text(room['name']),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (_) => CollabRoomScreen(
                              roomId: room['id'],
                              roomName: room['name'],
                            ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _roomController,
                    decoration: const InputDecoration(
                      labelText: "New Room",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.add), onPressed: _createRoom),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
