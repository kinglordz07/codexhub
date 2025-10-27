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
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final isVerySmallScreen = screenSize.width < 400;
    final isLandscape = screenSize.width > screenSize.height;

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
          child: mentors.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(screenSize, isSmallScreen, isVerySmallScreen, isLandscape),
        ),
      ),
    );
  }

  Widget _buildContent(Size screenSize, bool isSmallScreen, bool isVerySmallScreen, bool isLandscape) {
    return SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: screenSize.height - 
                    (isSmallScreen ? 150 : 200), // Account for app bar and padding
        ),
        child: Column(
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
                    color: Color.lerp(Colors.black, Colors.transparent, 0.9)!,
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
                      'Available Mentors',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 14 : 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 8 : 12),
                    
                    // Dropdown with improved styling
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
                      ),
                      initialValue: selectedMentorId,
                      items: mentors.map((mentor) {
                        return DropdownMenuItem<String>(
                          value: mentor['id'].toString(),
                          child: Text(
                            mentor['username'] ?? 'Unknown Mentor',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 14 : 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => selectedMentorId = value),
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

            const Spacer(),

            // Action Button
            Center(
              child: SizedBox( // FIXED: Use SizedBox instead of Container for layout
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
        ),
      ),
    );
  }

  Widget _buildSelectedMentorInfo(bool isSmallScreen) {
    final selectedMentor = mentors.firstWhere(
      (mentor) => mentor['id'].toString() == selectedMentorId,
      orElse: () => {},
    );

    if (selectedMentor.isEmpty) return const SizedBox();

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
          Icon(
            Icons.person,
            color: Colors.indigo,
            size: isSmallScreen ? 20 : 24,
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
                  selectedMentor['username'] ?? 'Unknown Mentor',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 16,
                    color: Colors.indigo,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}