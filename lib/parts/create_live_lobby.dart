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

  bool get isSmallScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width < 600;
  }

  bool get isVerySmallScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width < 400;
  }

  bool get isTablet {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width >= 600 && mediaQuery.size.width < 1200;
  }

  double get titleFontSize => isVerySmallScreen ? 14 : (isSmallScreen ? 16 : (isTablet ? 18 : 20));
  double get bodyFontSize => isVerySmallScreen ? 12 : (isSmallScreen ? 14 : 16);
  double get iconSize => isVerySmallScreen ? 18 : (isSmallScreen ? 20 : 24);
  double get buttonPadding => isVerySmallScreen ? 8 : (isSmallScreen ? 12 : 16);

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
        _showErrorSnack('Failed to load mentors');
      }
    }
  }

  Future<void> _createLobby() async {
    if (selectedMentorId == null) {
      _showErrorSnack('Please select a mentor');
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
      final String sessionId = sessionResult['sessionId'] ?? '';

      debugPrint('🟢 _createLobby: roomId=$roomId, roomName=$roomName, menteeId=$menteeId, sessionId=$sessionId');

      if (roomId.isEmpty || sessionId.isEmpty) {
        throw Exception('Room ID or Session ID is empty');
      }

      if (!mounted) {
        debugPrint('🔴 _createLobby: Not mounted after session creation');
        return;
      }

      _showSuccessSnack('Mentor invited successfully!');

      debugPrint('🟢 _createLobby: Navigating to CollabRoomTabs');
      
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CollabRoomTabs(
            roomId: roomId,
            roomName: roomName,
            menteeId: menteeId,
            mentorId: selectedMentorId!,
            isMentor: false,
            sessionId: sessionId,
          ),
        ),
      );
      
    } catch (e, stack) {
      debugPrint('❌ Error creating live session: $e');
      debugPrint('Stack trace: $stack');
      if (mounted) {
        _showErrorSnack('Failed to create live session: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showErrorSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(fontSize: bodyFontSize),
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(fontSize: bodyFontSize),
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(
        'Invite a Mentor',
        style: TextStyle(fontSize: titleFontSize),
      ),
      backgroundColor: Colors.indigo,
      elevation: 2,
      foregroundColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 12.0 : 16.0),
          child: _isLoadingMentors
              ? _buildLoadingState()
              : mentors.isEmpty
                  ? _buildEmptyState()
                  : _buildContent(),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.indigo),
          ),
          SizedBox(height: 16),
          Text(
            'Loading available mentors...',
            style: TextStyle(
              fontSize: bodyFontSize,
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Please wait',
            style: TextStyle(
              fontSize: isSmallScreen ? 12 : 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_off,
              size: isSmallScreen ? 48 : 64,
              color: Colors.grey[400],
            ),
            SizedBox(height: 16),
            Text(
              'No mentors available',
              style: TextStyle(
                fontSize: bodyFontSize,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 20 : 40),
              child: Text(
                'Please check back later or contact support.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 14,
                  color: Colors.grey[500],
                ),
              ),
            ),
            SizedBox(height: 24),
            SizedBox(
              width: isVerySmallScreen ? double.infinity : null,
              child: ElevatedButton(
                onPressed: _loadMentors,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 24 : 32,
                    vertical: isSmallScreen ? 12 : 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  minimumSize: isVerySmallScreen 
                      ? const Size(double.infinity, 48)
                      : null,
                ),
                child: Text(
                  'Retry',
                  style: TextStyle(fontSize: bodyFontSize),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Select a Mentor:',
        style: TextStyle(
          fontSize: isSmallScreen ? 14 : 16,
          fontWeight: FontWeight.w600,
          color: Colors.grey[800],
        ),
      ),
      SizedBox(height: isSmallScreen ? 10 : 12),

      Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 14 : 16),
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
              SizedBox(height: isSmallScreen ? 10 : 12),
              
              ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: isSmallScreen ? 52 : 58,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: true,
                      fillColor: Colors.grey[50],
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 14 : 16,
                        vertical: isSmallScreen ? 15 : 17,
                      ),
                      errorStyle: TextStyle(
                        fontSize: isSmallScreen ? 12 : 14,
                      ),
                    ),
                    initialValue: selectedMentorId,
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text(
                          'Select a mentor...',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
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
                          child: Container(
                            constraints: BoxConstraints(
                              minHeight: isSmallScreen ? 44 : 50,
                            ),
                            child: Row(
                              children: [

                                Container(
                                  width: isSmallScreen ? 36 : 40,
                                  height: isSmallScreen ? 36 : 40,
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade100,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.person,
                                    size: isSmallScreen ? 18 : 20,
                                    color: Colors.indigo,
                                  ),
                                ),
                                SizedBox(width: isSmallScreen ? 10 : 12),
                                
                                Expanded(
  child: SizedBox( // ✅ ADDED: SizedBox to provide enough height
    height: isSmallScreen ? 28 : 32, // ✅ Give it enough vertical space
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center, // ✅ Center vertically
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          username,
          style: TextStyle(
            fontSize: isSmallScreen ? 12 : 14, // ✅ Slightly smaller
            fontWeight: FontWeight.w500,
            height: 1.0, // ✅ Normal line height
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: 1), // ✅ Reduced spacing
        Text(
          role,
          style: TextStyle(
            fontSize: isSmallScreen ? 10 : 12, // ✅ Slightly smaller
            color: Colors.grey[600],
            height: 1.0, // ✅ Normal line height
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  ),
),
                                
                                SizedBox(width: isSmallScreen ? 6 : 8),
                                
                                if (isOnline)
                                  Container(
                                    width: isSmallScreen ? 10 : 12,
                                    height: isSmallScreen ? 10 : 12,
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
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
                    iconSize: isSmallScreen ? 22 : 24,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      color: Colors.black,
                    ),
                    dropdownColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      SizedBox(height: isSmallScreen ? 16 : 20),

      if (selectedMentorId != null) _buildSelectedMentorInfo(),

      const Spacer(),

      _buildActionButton(),

      if (isVerySmallScreen) SizedBox(height: MediaQuery.of(context).padding.bottom),
    ],
  );
}
Widget _buildSelectedMentorInfo() {
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
    margin: EdgeInsets.only(bottom: 8),
    padding: EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.indigo.withAlpha(20),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.indigo.withAlpha(76)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Stack(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.indigo.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person,
                color: Colors.indigo,
                size: 22,
              ),
            ),
            if (isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Selected:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 3),
              Text(
                username,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.indigo,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (role.isNotEmpty && role != 'mentor') ...[
                SizedBox(height: 2),
                Text(
                  role.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

  Widget _buildActionButton() {
    return Center(
      child: SizedBox(
        width: isVerySmallScreen ? double.infinity : null,
        child: ElevatedButton(
          onPressed: isLoading ? null : _createLobby,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 24 : 32,
              vertical: isSmallScreen ? 14 : 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 2,
            shadowColor: Color.fromRGBO(75, 0, 130, 0.3), 
            minimumSize: isVerySmallScreen 
                ? const Size(double.infinity, 56)
                : Size(isSmallScreen ? 160 : 200, 56),
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
                      Icons.person_add_alt_1,
                      size: isSmallScreen ? 18 : 20,
                    ),
                    SizedBox(width: isSmallScreen ? 8 : 12),
                    Flexible(
                      child: Text(
                        'Invite Mentor',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 15 : 17,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}