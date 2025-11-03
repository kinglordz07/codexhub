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

      // ✅ CREATE LIVE SESSION FOR THE ROOM
      final session = await supabase
          .from('live_sessions')
          .insert({
            'room_id': room['id'],
            'mentee_id': user.id, // Creator becomes mentee by default
            'code': '// Welcome to the collaboration room!\n// Start coding together...',
            'is_live': false,
            'language': 'python',
          })
          .select()
          .single();

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CollabRoomTabs(
            roomId: room['id'].toString(),
            roomName: room['name'].toString(),
            isMentor: false, // Creator is mentee by default
            mentorId: '', // No mentor initially
            menteeId: user.id,
            sessionId: session['id'].toString(), // ✅ ADDED: Critical parameter
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating room: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
        ),
      );
    }
  }

  // Fetch rooms
  Future<void> _fetchRooms() async {
    if (mounted) {
      setState(() => isLoading = true);
    }
    
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
          SnackBar(
            content: Text('Error fetching rooms: ${e.toString()}'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
          ),
        );
      }
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
        SnackBar(
          content: const Text("Please sign in to join a room"),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
        ),
      );
      return;
    }

    final roomIdController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "Join Room",
          style: TextStyle(fontSize: isSmallScreen ? 18 : 20),
        ),
        content: TextField(
          controller: roomIdController,
          decoration: InputDecoration(
            hintText: "Enter Room ID",
            border: const OutlineInputBorder(),
            contentPadding: EdgeInsets.all(isSmallScreen ? 12 : 16),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              "Cancel",
              style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              "Join",
              style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
            ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Room not found"),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
          ),
        );
        return;
      }

      // Add user if not already a member
      final existing = await supabase
          .from('room_members')
          .select()
          .eq('room_id', roomId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (existing == null) {
        await supabase.from('room_members').insert({
          'room_id': roomId,
          'user_id': user.id,
        });
      }

      // ✅ GET OR CREATE LIVE SESSION
      final session = await supabase
          .from('live_sessions')
          .select()
          .eq('room_id', roomId)
          .maybeSingle();

      String sessionId;
      String mentorId = '';
      String menteeId = '';

      if (session != null) {
        // Use existing session
        sessionId = session['id'].toString();
        mentorId = session['mentor_id']?.toString() ?? '';
        menteeId = session['mentee_id']?.toString() ?? '';
      } else {
        // Create new session if none exists
        final newSession = await supabase
            .from('live_sessions')
            .insert({
              'room_id': roomId,
              'mentee_id': room['creator_id'], // Room creator is mentee
              'code': '// Welcome to the collaboration room!\n// Start coding together...',
              'is_live': false,
              'language': 'python',
            })
            .select()
            .single();
        
        sessionId = newSession['id'].toString();
        menteeId = newSession['mentee_id']?.toString() ?? '';
      }

      // ✅ DETERMINE USER ROLE
      final bool isMentor = user.id == mentorId;

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CollabRoomTabs(
            roomId: roomId,
            roomName: room['name'].toString(),
            isMentor: isMentor,
            mentorId: mentorId,
            menteeId: menteeId,
            sessionId: sessionId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error joining room: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
        ),
      );
    }
  }

  // Join room from list (updated)
  Future<void> _joinRoomFromList(String roomId) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Check if room exists
      final room = await supabase
          .from('rooms')
          .select()
          .eq('id', roomId)
          .maybeSingle();

      if (room == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Room not found"),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
          ),
        );
        return;
      }

      // Add user if not already a member
      final existing = await supabase
          .from('room_members')
          .select()
          .eq('room_id', roomId)
          .eq('user_id', user.id)
          .maybeSingle();

      if (existing == null) {
        await supabase.from('room_members').insert({
          'room_id': roomId,
          'user_id': user.id,
        });
      }

      // ✅ GET LIVE SESSION
      final session = await supabase
          .from('live_sessions')
          .select()
          .eq('room_id', roomId)
          .maybeSingle();

      if (session == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Error: No live session found for this room"),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
          ),
        );
        return;
      }

      final sessionId = session['id'].toString();
      final mentorId = session['mentor_id']?.toString() ?? '';
      final menteeId = session['mentee_id']?.toString() ?? '';
      final bool isMentor = user.id == mentorId;

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CollabRoomTabs(
            roomId: roomId,
            roomName: room['name'].toString(),
            isMentor: isMentor,
            mentorId: mentorId,
            menteeId: menteeId,
            sessionId: sessionId, // ✅ ADDED: Critical parameter
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error joining room: ${e.toString()}'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
        ),
      );
    }
  }

  Future<void> _showCreateRoomDialog() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Please sign in to create a room"),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
        ),
      );
      return;
    }

    final roomNameController = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          "Create Room",
          style: TextStyle(fontSize: isSmallScreen ? 18 : 20),
        ),
        content: TextField(
          controller: roomNameController,
          decoration: InputDecoration(
            hintText: "Enter room name",
            border: const OutlineInputBorder(),
            contentPadding: EdgeInsets.all(isSmallScreen ? 12 : 16),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              "Cancel",
              style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              "Create",
              style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
            ),
          ),
        ],
      ),
    );

    if (result != true) return;

    final name = roomNameController.text.trim();
    if (name.isEmpty) return;

    await _createRoom(name);
  }

  Widget _buildActionButtons() {
    if (isLargeScreen) {
      return Row(
        children: [
          Expanded(
            child: _buildCreateRoomButton(),
          ),
          SizedBox(width: isSmallScreen ? 12 : 16),
          Expanded(
            child: _buildJoinRoomButton(),
          ),
        ],
      );
    } else {
      return Column(
        children: [
          _buildCreateRoomButton(),
          SizedBox(height: isSmallScreen ? 12 : 16),
          _buildJoinRoomButton(),
        ],
      );
    }
  }

  Widget _buildCreateRoomButton() {
    return ElevatedButton.icon(
      onPressed: _showCreateRoomDialog,
      icon: Icon(Icons.add, size: isSmallScreen ? 20 : 24),
      label: Text(
        "Create Room",
        style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
      ),
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 16 : 20,
          vertical: isSmallScreen ? 12 : 16,
        ),
      ),
    );
  }

  Widget _buildJoinRoomButton() {
    return ElevatedButton.icon(
      onPressed: _showJoinRoomDialog,
      icon: Icon(Icons.login, size: isSmallScreen ? 20 : 24),
      label: Text(
        "Join by ID",
        style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
      ),
      style: ElevatedButton.styleFrom(
        padding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 16 : 20,
          vertical: isSmallScreen ? 12 : 16,
        ),
      ),
    );
  }

  Widget _buildRoomList() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (rooms.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.meeting_room_outlined,
                size: isSmallScreen ? 48 : 64,
                color: Colors.grey.shade400,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              Text(
                "No rooms available",
                style: TextStyle(
                  fontSize: isSmallScreen ? 16 : 18,
                  color: Colors.grey.shade600,
                ),
              ),
              SizedBox(height: isSmallScreen ? 8 : 12),
              Text(
                "Create one to get started!",
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: rooms.length,
      itemBuilder: (context, index) {
        final room = rooms[index];
        return Card(
          margin: EdgeInsets.only(bottom: isSmallScreen ? 8 : 12),
          elevation: 2,
          child: ListTile(
            leading: Icon(
              Icons.meeting_room,
              size: isSmallScreen ? 24 : 28,
              color: Colors.indigo,
            ),
            title: Text(
              room['name'].toString(),
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            subtitle: Text(
              "ID: ${room['id']}",
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                color: Colors.grey.shade600,
              ),
            ),
            trailing: IconButton(
              icon: Icon(
                Icons.arrow_forward,
                size: isSmallScreen ? 20 : 24,
              ),
              onPressed: () => _joinRoomFromList(room['id'].toString()), // ✅ UPDATED
              tooltip: "Join Room",
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 16 : 20,
              vertical: isSmallScreen ? 8 : 12,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.indigo,
        title: Text(
          "Collaboration Lobby",
          style: TextStyle(
            fontSize: isSmallScreen ? 18 : 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh,
              size: isSmallScreen ? 20 : 24,
            ),
            onPressed: _fetchRooms,
            tooltip: "Refresh rooms",
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 16.0 : 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildActionButtons(),
              SizedBox(height: isSmallScreen ? 16 : 24),
              const Divider(),
              SizedBox(height: isSmallScreen ? 16 : 24),
              Text(
                "Available Rooms:",
                style: TextStyle(
                  fontSize: isSmallScreen ? 18 : 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              Expanded(
                child: _buildRoomList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}