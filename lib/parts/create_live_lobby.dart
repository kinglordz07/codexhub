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
  bool _isLoadingMentors = true;

  @override
  void initState() {
    super.initState();
    _loadMentors();
  }

  Future<void> _loadMentors() async {
    try {
      debugPrint('🟡 Loading mentors...');
      final result = await service.fetchMentors();
      if (!mounted) return;

      debugPrint('✅ Loaded ${result.length} mentors');
      setState(() {
        mentors = result;
        _isLoadingMentors = false;
      });
    } catch (e, stack) {
      debugPrint('❌ Error loading mentors: $e');
      debugPrint('Stack trace: $stack');
      if (mounted) {
        setState(() => _isLoadingMentors = false);
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
    debugPrint('🟡 _createLobby: Start with mentor: $selectedMentorId');

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
      final String sessionId = sessionResult['sessionId'] ?? ''; // ✅ ADDED: Get sessionId

      debugPrint('🟢 _createLobby: roomId=$roomId, roomName=$roomName, menteeId=$menteeId, sessionId=$sessionId');

      // FIXED: Validate the roomId and sessionId before navigation
      if (roomId.isEmpty || sessionId.isEmpty) {
        throw Exception('Room ID or Session ID is empty');
      }

      if (!mounted) {
        debugPrint('🔴 _createLobby: Not mounted after session creation');
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mentor invited successfully!')),
      );

      debugPrint('🟢 _createLobby: Navigating to CollabRoomTabs');
      
      // ✅ FIXED: Added sessionId parameter
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CollabRoomTabs(
            roomId: roomId,
            roomName: roomName,
            menteeId: menteeId,
            mentorId: selectedMentorId!, // Use the selected mentor ID
            isMentor: false,
            sessionId: sessionId, // ✅ CRITICAL: Add sessionId parameter
          ),
        ),
      );
      
    } catch (e, stack) {
      debugPrint('❌ Error creating live session: $e');
      debugPrint('Stack trace: $stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create live session: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
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
          'Invite a Mentor',
          style: TextStyle(fontSize: isSmallScreen ? 18 : 20),
        ),
        backgroundColor: Colors.indigo,
        elevation: 2,
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 12.0 : 16.0),
          child: _isLoadingMentors
              ? _buildLoadingState()
              : mentors.isEmpty
                  ? _buildEmptyState()
                  : _buildContent(isSmallScreen, isVerySmallScreen),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading available mentors...'),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.person_off,
            size: 64,
            color: Colors.grey[400],
          ),
          SizedBox(height: 16),
          Text(
            'No mentors available',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Please check back later or contact support.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
          SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadMentors,
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool isSmallScreen, bool isVerySmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Text(
          'Select a Mentor:',
          style: TextStyle(
            fontSize: isSmallScreen ? 16 : 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: isSmallScreen ? 8 : 12),

        // Mentor Selection
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Available Mentors (${mentors.length})',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: isSmallScreen ? 8 : 12),
                
                // Dropdown for mentor selection
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[400]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey[400]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.indigo),
                    ),
                    filled: true,
                    fillColor: Colors.grey[50],
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 12 : 16,
                      vertical: isSmallScreen ? 14 : 16,
                    ),
                    errorStyle: TextStyle(
                      fontSize: isSmallScreen ? 12 : 14,
                    ),
                  ),
                  initialValue: selectedMentorId,
                  items: [
                    // Placeholder item
                    DropdownMenuItem<String>(
                      value: null,
                      child: Text(
                        'Select a mentor...',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 14 : 15,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                    ...mentors.map((mentor) {
                      final username = mentor['username'] ?? 'Unknown Mentor';
                      final role = mentor['role'] ?? 'unknown';
                      final isOnline = mentor['online_status'] == true;
                      
                      return DropdownMenuItem<String>(
                        value: mentor['id'].toString(),
                        child: Row(
                          children: [
                            Icon(
                              Icons.person,
                              size: isSmallScreen ? 16 : 18,
                              color: isOnline ? Colors.green : Colors.grey,
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    username,
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 14 : 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    role,
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 12 : 13,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (isOnline)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() => selectedMentorId = value);
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Please select a mentor';
                    }
                    return null;
                  },
                  isExpanded: true,
                  iconSize: isSmallScreen ? 20 : 24,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 15,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: isSmallScreen ? 16 : 24),

        // Selected Mentor Info (if any)
        if (selectedMentorId != null) _buildSelectedMentorInfo(isSmallScreen),

        // Flexible space
        Flexible(
          child: Container(),
        ),

        // Action Button
        Center(
          child: SizedBox(
            width: isVerySmallScreen ? double.infinity : null,
            child: ElevatedButton(
              onPressed: isLoading ? null : _createLobby,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 24 : 40,
                  vertical: isSmallScreen ? 14 : 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
                minimumSize: isVerySmallScreen 
                    ? Size(double.infinity, isSmallScreen ? 48 : 52)
                    : Size(isSmallScreen ? 140 : 160, isSmallScreen ? 48 : 52),
              ),
              child: isLoading
                  ? SizedBox(
                      width: isSmallScreen ? 20 : 24,
                      height: isSmallScreen ? 20 : 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.person_add,
                          size: isSmallScreen ? 18 : 20,
                        ),
                        SizedBox(width: isSmallScreen ? 6 : 8),
                        Flexible(
                          child: Text(
                            'Invite Mentor',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 14 : 16,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),

        // Additional spacing for very small screens
        if (isVerySmallScreen) SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSelectedMentorInfo(bool isSmallScreen) {
    final selectedMentor = mentors.firstWhere(
      (mentor) => mentor['id'].toString() == selectedMentorId,
      orElse: () => {},
    );

    if (selectedMentor.isEmpty) return const SizedBox();

    final username = selectedMentor['username'] ?? 'Unknown Mentor';
    final role = selectedMentor['role'] ?? 'mentor';
    final isOnline = selectedMentor['online_status'] == true;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        color: Colors.indigo.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.withAlpha(76)),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              Icon(
                Icons.person,
                color: Colors.indigo,
                size: isSmallScreen ? 20 : 24,
              ),
              if (isOnline)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(width: isSmallScreen ? 8 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected Mentor:',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 12 : 14,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  username,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 16,
                    color: Colors.indigo,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (role.isNotEmpty)
                  Text(
                    role.toUpperCase(),
                    style: TextStyle(
                      fontSize: isSmallScreen ? 10 : 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}