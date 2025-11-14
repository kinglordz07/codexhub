import 'package:codexhub01/collabscreen/collab_room_tabs.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RoomListScreen extends StatefulWidget {
  const RoomListScreen({super.key});

  @override
  State<RoomListScreen> createState() => _RoomListScreenState();
}

class _RoomListScreenState extends State<RoomListScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _roomController = TextEditingController();
  final TextEditingController _roomIdController = TextEditingController();
  
  List<Map<String, dynamic>> _rooms = [];
  bool _isLoading = true;
  bool _isCreatingRoom = false;
  bool _isJoiningRoom = false;

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
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    try {
      setState(() => _isLoading = true);
      final response = await supabase
          .from('rooms')
          .select()
          .order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          _rooms = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('Failed to load rooms: $e');
      }
    }
  }

  Future<void> _createRoom() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showError('Please sign in to create a room');
      return;
    }

    final roomName = _roomController.text.trim();
    if (roomName.isEmpty) {
      _showError('Please enter a room name');
      return;
    }

    setState(() => _isCreatingRoom = true);

    try {
      // Generate unique room ID
      final roomId = _generateRoomId();
      
      // Create room
      await supabase
          .from('rooms')
          .insert({
            'id': roomId,
            'name': roomName,
            'creator_id': user.id,
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      // Add creator as room member
      await supabase.from('room_members').insert({
        'room_id': roomId,
        'user_id': user.id,
      });

      // Create live session for the room
      final session = await supabase
          .from('live_sessions')
          .insert({
            'room_id': roomId,
            'mentee_id': user.id, // Creator is the mentee
            'code': '// Welcome to your new collaboration room!\n// Start coding with your team...',
            'is_live': false,
            'language': 'python',
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      _roomController.clear();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollabRoomTabs(
              roomId: roomId,
              roomName: roomName,
              menteeId: user.id,
              mentorId: '', // No mentor yet
              isMentor: false,
              sessionId: session['id'].toString(),
            ),
          ),
        );
      }
    } catch (e) {
      _showError('Failed to create room: $e');
    } finally {
      if (mounted) {
        setState(() => _isCreatingRoom = false);
      }
    }
  }

  String _generateRoomId() {
    // Generate a unique room ID (you can use UUID package if preferred)
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch % 10000;
    return 'room_${timestamp}_$random';
  }

  Future<void> _joinRoomById() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showError('Please sign in to join a room');
      return;
    }

    final roomId = _roomIdController.text.trim();
    if (roomId.isEmpty) {
      _showError('Please enter a room ID');
      return;
    }

    setState(() => _isJoiningRoom = true);

    try {
      // Check if room exists
      final room = await supabase
          .from('rooms')
          .select()
          .eq('id', roomId)
          .maybeSingle();

      if (room == null) {
        _showError('Room with ID $roomId not found');
        return;
      }

      // Check if user is already a member
      final existingMembership = await supabase
          .from('room_members')
          .select()
          .eq('room_id', room['id'])
          .eq('user_id', user.id)
          .maybeSingle();

      // If not a member, add them
      if (existingMembership == null) {
        await supabase.from('room_members').insert({
          'room_id': room['id'],
          'user_id': user.id,
        });
      }

      // ✅ GET OR CREATE LIVE SESSION
      final session = await supabase
          .from('live_sessions')
          .select()
          .eq('room_id', room['id'])
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
              'room_id': room['id'],
              'mentee_id': room['creator_id'], // Room creator is mentee
              'code': '// Welcome to collaboration room!\n// Start coding...',
              'is_live': false,
              'language': 'python',
            })
            .select()
            .single();
        
        sessionId = newSession['id'].toString();
        menteeId = newSession['mentee_id']?.toString() ?? '';
      }

      _roomIdController.clear();

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollabRoomTabs(
              roomId: room['id'].toString(),
              roomName: room['name'].toString(),
              menteeId: menteeId,
              mentorId: mentorId,
              isMentor: user.id == mentorId,
              sessionId: sessionId, // ✅ ADDED
            ),
          ),
        );
      }
    } catch (e) {
      _showError('Failed to join room: $e');
    } finally {
      if (mounted) {
        setState(() => _isJoiningRoom = false);
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
        ),
      );
    }
  }

  Future<void> _joinRoom(Map<String, dynamic> room) async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showError('Please sign in to join a room');
      return;
    }

    try {
      // Check if user is already a member
      final existingMembership = await supabase
          .from('room_members')
          .select()
          .eq('room_id', room['id'])
          .eq('user_id', user.id)
          .maybeSingle();

      // If not a member, add them
      if (existingMembership == null) {
        await supabase.from('room_members').insert({
          'room_id': room['id'],
          'user_id': user.id,
        });
      }

      // ✅ GET LIVE SESSION
      final session = await supabase
          .from('live_sessions')
          .select()
          .eq('room_id', room['id'])
          .maybeSingle();

      if (session == null) {
        _showError('No live session found for this room');
        return;
      }

      final sessionId = session['id'].toString();
      final mentorId = session['mentor_id']?.toString() ?? '';
      final menteeId = session['mentee_id']?.toString() ?? '';

      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollabRoomTabs(
              roomId: room['id'].toString(),
              roomName: room['name'].toString(),
              menteeId: menteeId,
              mentorId: mentorId,
              isMentor: user.id == mentorId,
              sessionId: sessionId, // ✅ ADDED
            ),
          ),
        );
      }
    } catch (e) {
      _showError('Failed to join room: $e');
    }
  }

  Widget _buildRoomList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_rooms.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.meeting_room_outlined,
                size: isSmallScreen ? 64 : 80,
                color: Colors.grey.shade400,
              ),
              SizedBox(height: isSmallScreen ? 16 : 20),
              Text(
                'No rooms available',
                style: TextStyle(
                  fontSize: isSmallScreen ? 18 : 20,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
              SizedBox(height: isSmallScreen ? 8 : 12),
              Text(
                'Create the first room to get started!',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  color: Colors.grey.shade500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
      itemCount: _rooms.length,
      itemBuilder: (context, index) {
        final room = _rooms[index];
        return Card(
          elevation: 2,
          margin: EdgeInsets.symmetric(
            vertical: isSmallScreen ? 4 : 6,
            horizontal: isSmallScreen ? 0 : 4,
          ),
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
              'ID: ${room['id']}',
              style: TextStyle(
                fontSize: isSmallScreen ? 12 : 14,
                color: Colors.grey.shade600,
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios,
              size: isSmallScreen ? 16 : 18,
              color: Colors.grey.shade500,
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 16 : 20,
              vertical: isSmallScreen ? 8 : 12,
            ),
            onTap: () => _joinRoom(room),
          ),
        );
      },
    );
  }

  Widget _buildRoomCreationSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 8 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.add_circle_outline, 
                  color: Colors.indigo, 
                  size: isSmallScreen ? 18 : 24
                ),
                SizedBox(width: isSmallScreen ? 6 : 8),
                Text(
                  'Create Room',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 8 : 16),
            TextField(
              controller: _roomController,
              decoration: InputDecoration(
                labelText: "Room Name",
                hintText: "Enter room name...",
                border: const OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 10 : 16,
                  vertical: isSmallScreen ? 10 : 16,
                ),
                isDense: isSmallScreen,
              ),
              onSubmitted: (_) => _createRoom(),
              style: TextStyle(fontSize: isSmallScreen ? 14 : 18),
            ),
            SizedBox(height: isSmallScreen ? 8 : 16),
            SizedBox(
              width: double.infinity,
              child: _isCreatingRoom
                  ? Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _createRoom,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: isSmallScreen ? 10 : 14,
                        ),
                      ),
                      child: Text(
                        'Create Room',
                        style: TextStyle(fontSize: isSmallScreen ? 12 : 16),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildJoinByIdSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 8 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.meeting_room, 
                  color: Colors.green, 
                  size: isSmallScreen ? 18 : 24
                ),
                SizedBox(width: isSmallScreen ? 6 : 8),
                Text(
                  'Join by ID',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 8 : 16),
            TextField(
              controller: _roomIdController,
              decoration: InputDecoration(
                labelText: "Room ID",
                hintText: "Enter room ID...",
                border: const OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 10 : 16,
                  vertical: isSmallScreen ? 10 : 16,
                ),
                isDense: isSmallScreen,
              ),
              onSubmitted: (_) => _joinRoomById(),
              style: TextStyle(fontSize: isSmallScreen ? 14 : 18),
            ),
            SizedBox(height: isSmallScreen ? 8 : 16),
            SizedBox(
              width: double.infinity,
              child: _isJoiningRoom
                  ? Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _joinRoomById,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: isSmallScreen ? 10 : 14,
                        ),
                      ),
                      child: Text(
                        'Join Room',
                        style: TextStyle(fontSize: isSmallScreen ? 12 : 16),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionSections() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildRoomCreationSection(),
        ),
        SizedBox(width: isSmallScreen ? 8 : 16),
        Expanded(
          child: _buildJoinByIdSection(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Collaboration Rooms",
          style: TextStyle(
            fontSize: isSmallScreen ? 18 : 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh,
              size: isSmallScreen ? 20 : 24,
            ),
            onPressed: _loadRooms,
            tooltip: 'Refresh Rooms',
          ),
        ],
      ),
      body: Column(
        children: [
          // Action sections (Create Room + Join by ID)
          Padding(
            padding: EdgeInsets.all(isSmallScreen ? 8 : 16),
            child: _buildActionSections(),
          ),
          
          // Room list header
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 12 : 20),
            child: Row(
              children: [
                Icon(
                  Icons.list, 
                  color: Colors.indigo, 
                  size: isSmallScreen ? 18 : 24
                ),
                SizedBox(width: isSmallScreen ? 6 : 8),
                Text(
                  'Available Rooms',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 16 : 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Spacer(),
                Text(
                  '${_rooms.length} room${_rooms.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: isSmallScreen ? 12 : 14,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: isSmallScreen ? 6 : 12),
          
          // Room list
          Expanded(
            child: _buildRoomList(),
          ),
        ],
      ),
    );
  }
}