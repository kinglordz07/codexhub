// ignore_for_file: deprecated_member_use

import 'dart:async'; // ✅ ADD THIS IMPORT
import 'package:flutter/material.dart';
import '../services/live_lobby_service.dart';
import '../collabscreen/collab_room_tabs.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateLiveLobby extends StatefulWidget {
  final String menteeId;
  final String menteeName;
  final bool isMentor;
  final String? existingRoomId;
  final String? existingRoomName;

  const CreateLiveLobby({
    super.key,
    required this.menteeId,
    required this.menteeName,
    required this.isMentor,
    this.existingRoomId,
    this.existingRoomName,
  });

  @override
  State<CreateLiveLobby> createState() => _CreateLiveLobbyState();
}

class _CreateLiveLobbyState extends State<CreateLiveLobby> {
  final service = LiveLobbyService();
  final SupabaseClient supabase = Supabase.instance.client;
  List<Map<String, dynamic>> mentors = [];
  String? selectedMentorId;
  bool isLoading = false;
  bool _isLoadingMentors = true;
  int _retryCount = 0;
  final int _maxRetries = 3;
  final TextEditingController _messageController = TextEditingController();
  RealtimeChannel? _mentorsChannel;

  // Responsive design helpers
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
    _loadMentorsWithRetry();
    _subscribeToMentorUpdates();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _mentorsChannel?.unsubscribe();
    super.dispose();
  }

  void _subscribeToMentorUpdates() {
    _mentorsChannel = supabase
        .channel('mentors_status_${widget.menteeId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles_new',
          callback: (payload) {
            debugPrint('🔄 Mentor status update received');
            if (mounted) {
              _loadMentors(); // Refresh mentor list on status changes
            }
          },
        )
        .subscribe((status, [_]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint('✅ Subscribed to mentor status updates');
      }
    });
  }

  Future<void> _loadMentorsWithRetry() async {
    try {
      await _loadMentors();
      _retryCount = 0; // Reset on success
    } catch (e) {
      _retryCount++;
      if (_retryCount <= _maxRetries && mounted) {
        debugPrint('🔄 Retry $_retryCount/$_maxRetries after error: $e');
        await Future.delayed(Duration(seconds: _retryCount * 2));
        await _loadMentorsWithRetry();
      } else if (mounted) {
        setState(() => _isLoadingMentors = false);
      }
    }
  }

  Future<void> _loadMentors() async {
    try {
      if (mounted) {
        setState(() => _isLoadingMentors = true);
      }

      debugPrint('🟡 Loading mentors...');
      final result = await service.fetchMentors().timeout(
        const Duration(seconds: 15),
      );

      if (!mounted) return;

      debugPrint('✅ Loaded ${result.length} mentors');
      if (result.isNotEmpty) {
        debugPrint('🔍 First mentor: ${result.first['username']}');
      }

      setState(() {
        mentors = result;
        _isLoadingMentors = false;
      });
    } on TimeoutException catch (e) { // ✅ FIXED: Use TimeoutException directly
      debugPrint('❌ Timeout loading mentors: $e');
      if (mounted) {
        setState(() => _isLoadingMentors = false);
        _showErrorSnack('Connection timeout. Please check your internet.');
      }
    } catch (e, stack) {
      debugPrint('❌ Error loading mentors: $e');
      debugPrint('Stack trace: $stack');
      if (mounted) {
        setState(() => _isLoadingMentors = false);
        _showErrorSnack('Failed to load mentors. Please try again.');
      }
    }
  }

  Future<void> _createLobby() async {
    // Validate mentor selection
    if (selectedMentorId == null || selectedMentorId!.isEmpty) {
      _showErrorSnack('Please select a mentor');
      return;
    }

    // Validate mentor existence
    final selectedMentor = mentors.firstWhere(
      (mentor) => mentor['id'].toString() == selectedMentorId,
      orElse: () => {},
    );

    if (selectedMentor.isEmpty) {
      _showErrorSnack('Selected mentor not found. Please refresh the list.');
      return;
    }

    // Show confirmation dialog
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Invite Mentor?',
          style: TextStyle(fontSize: bodyFontSize),
        ),
        content: Text(
          'Are you sure you want to invite ${selectedMentor['username']} to your session?',
          style: TextStyle(fontSize: bodyFontSize),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(fontSize: bodyFontSize),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
            ),
            child: Text(
              'Invite',
              style: TextStyle(
                fontSize: bodyFontSize,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );

    if (shouldProceed != true) return;

    setState(() => isLoading = true);
    debugPrint('🟡 Creating lobby with mentor: $selectedMentorId');

    try {
      if (widget.existingRoomId != null && widget.existingRoomId!.isNotEmpty) {
        debugPrint('🎯 USING EXISTING ROOM: ${widget.existingRoomId}');

        final sessionResult = await service.updateExistingRoomSession(
          widget.existingRoomId!,
          widget.menteeId,
          selectedMentorId!,
          widget.existingRoomName ?? 'Live Session',
          message: _messageController.text.trim(),
        );

        debugPrint('🟢 Update existing room result: $sessionResult');

        if (sessionResult == null) {
          throw Exception('Failed to update existing session');
        }

        await _handleSuccessfulInvite(
          roomId: widget.existingRoomId!,
          roomName: widget.existingRoomName ?? 'Live Session',
          sessionId: sessionResult['sessionId'] ?? '',
          isExisting: true,
        );
      } else {
        debugPrint('🆕 CREATING NEW ROOM');

        final sessionResult = await service.createLiveSession(
          widget.menteeId,
          selectedMentorId!,
          widget.menteeName,
          message: _messageController.text.trim(),
        );

        debugPrint('🟢 Create new session result: $sessionResult');

        if (sessionResult == null) {
          throw Exception('Failed to create session');
        }

        await _handleSuccessfulInvite(
          roomId: sessionResult['roomId'] ?? '',
          roomName: sessionResult['roomName'] ?? 'Live Room',
          sessionId: sessionResult['sessionId'] ?? '',
          isExisting: false,
        );
      }
    } catch (e, stack) {
      debugPrint('❌ Error creating/updating live session: $e');
      debugPrint('Stack trace: $stack');
      if (mounted) {
        _showErrorSnack('Failed to create live session: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _handleSuccessfulInvite({
    required String roomId,
    required String roomName,
    required String sessionId,
    required bool isExisting,
  }) async {
    if (roomId.isEmpty || sessionId.isEmpty) {
      throw Exception('Room ID or Session ID is empty');
    }

    if (!mounted) {
      debugPrint('🔴 Not mounted after session creation');
      return;
    }

    _showSuccessSnack(
      isExisting
          ? 'Mentor invited to existing room!'
          : 'Mentor invited successfully!',
    );

    debugPrint('🟢 Navigating to CollabRoomTabs...');

    try {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CollabRoomTabs(
            roomId: roomId,
            roomName: roomName,
            menteeId: widget.menteeId,
            mentorId: selectedMentorId!,
            isMentor: false,
            sessionId: sessionId,
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ Navigation error: $e');
      if (mounted) {
        _showErrorSnack('Failed to navigate to session. Please try again.');
      }
    }
  }

  String? _getProfilePictureUrl(Map<String, dynamic> mentor) {
    final possibleFields = [
      'profile_picture',
      'profilePicture',
      'avatar',
      'avatarUrl',
      'avatar_url',
      'image',
      'imageUrl',
      'photo',
      'photoUrl',
    ];

    for (var field in possibleFields) {
      final value = mentor[field];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  Widget _buildProfilePicture(String? profilePictureUrl, double size) {
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Colors.grey[200],
        child: profilePictureUrl != null
            ? Image.network(
                profilePictureUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.person,
                    size: size * 0.5,
                    color: Colors.grey[500],
                  );
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                    ),
                  );
                },
              )
            : Icon(
                Icons.person,
                size: size * 0.5,
                color: Colors.grey[500],
              ),
      ),
    );
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
        duration: const Duration(seconds: 4),
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
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _contactSupport() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Contact Support',
          style: TextStyle(fontSize: bodyFontSize),
        ),
        content: Text(
          'Please email support@codexhub.com for assistance with mentor invitations.',
          style: TextStyle(fontSize: bodyFontSize),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: TextStyle(fontSize: bodyFontSize),
            ),
          ),
        ],
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
      actions: [
        if (_isLoadingMentors)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMentors,
            tooltip: 'Refresh mentors',
          ),
      ],
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
              Icons.group_off,
              size: isSmallScreen ? 64 : 80,
              color: Colors.grey[400],
            ),
            SizedBox(height: 16),
            Text(
              'No Mentors Available',
              style: TextStyle(
                fontSize: isSmallScreen ? 18 : 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 20 : 40),
              child: Text(
                'All mentors might be busy or offline. You can:',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  color: Colors.grey[500],
                ),
              ),
            ),
            SizedBox(height: 16),
            _buildEmptyStateOption(
              icon: Icons.refresh,
              text: 'Refresh List',
              onTap: _loadMentors,
            ),
            SizedBox(height: 8),
            _buildEmptyStateOption(
              icon: Icons.schedule,
              text: 'Try Again Later',
              onTap: () => Navigator.maybePop(context),
            ),
            SizedBox(height: 8),
            _buildEmptyStateOption(
              icon: Icons.help,
              text: 'Contact Support',
              onTap: _contactSupport,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStateOption({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: isSmallScreen ? 20 : 32),
      child: ListTile(
        leading: Icon(icon, color: Colors.indigo, size: iconSize),
        title: Text(
          text,
          style: TextStyle(fontSize: bodyFontSize),
        ),
        onTap: onTap,
        trailing: Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }

  Widget _buildContent() {
  return ListView(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20),
    children: [
      if (widget.existingRoomId != null && widget.existingRoomId!.isNotEmpty)
        Container(
          width: double.infinity,
          margin: EdgeInsets.only(bottom: isSmallScreen ? 16 : 20),
          padding: EdgeInsets.all(isSmallScreen ? 14 : 16),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.meeting_room, color: Colors.blue, size: iconSize),
              SizedBox(width: isSmallScreen ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, 
                  children: [
                    Text(
                      'Using Existing Room',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade800,
                        fontSize: bodyFontSize,
                      ),
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Room: ${widget.existingRoomName ?? 'Live Session'}',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 12 : 14,
                        color: Colors.blue.shade700,
                      ),
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis, 
                    ),
                    SizedBox(height: 2),
                    Text(
                      'ID: ${widget.existingRoomId!.substring(0, 8)}...',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 10 : 12,
                        color: Colors.blue.shade600,
                      ),
                      maxLines: 1, 
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

      Text(
        'Select a Mentor:',
        style: TextStyle(
          fontSize: isSmallScreen ? 16 : 18,
          fontWeight: FontWeight.w600,
          color: Colors.grey[800],
        ),
      ),
      SizedBox(height: isSmallScreen ? 12 : 16),

      // Mentors Dropdown
      Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 14 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Available Mentors (${mentors.length})',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
                maxLines: 1, 
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              
              Container(
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
                  ),
                  value: selectedMentorId,
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
  final isOnline = mentor['online_status'] == true;
  
  return DropdownMenuItem<String>(
    value: mentor['id'].toString(),
    child: SizedBox(
      height: 32, 
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: isOnline ? Colors.green : Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              username,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
                  isExpanded: true,
                  iconSize: isSmallScreen ? 22 : 24,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 16,
                    color: Colors.black,
                  ),
                  dropdownColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),

      SizedBox(height: isSmallScreen ? 16 : 20),

      // Message Input
      Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 14 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Add a Message (Optional)',
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: isSmallScreen ? 10 : 12),
              TextFormField(
                controller: _messageController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Add a personal message for the mentor...',
                  hintStyle: TextStyle(
                    fontSize: isSmallScreen ? 13 : 14,
                    color: Colors.grey[500],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.indigo),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: EdgeInsets.all(isSmallScreen ? 14 : 16),
                ),
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 15,
                ),
                maxLength: 200,
              ),
            ],
          ),
        ),
      ),

      SizedBox(height: isSmallScreen ? 16 : 20),

      if (selectedMentorId != null) _buildSelectedMentorInfo(),

      SizedBox(height: isSmallScreen ? 20 : 24),

      _buildActionButton(),

      SizedBox(height: isSmallScreen ? 16 : 20),
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
  final profilePictureUrl = _getProfilePictureUrl(selectedMentor);

  return Container(
    width: double.infinity,
    padding: EdgeInsets.all(isSmallScreen ? 12 : 14),
    margin: EdgeInsets.only(bottom: 8), // ✅ ADD MARGIN FOR BETTER SPACING
    decoration: BoxDecoration(
      color: Colors.indigo.withAlpha(20),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.indigo.withAlpha(76)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start, // ✅ CHANGE TO START
      children: [
        Stack(
          children: [
            _buildProfilePicture(profilePictureUrl, isSmallScreen ? 44 : 48),
            if (isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(width: isSmallScreen ? 12 : 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Selected Mentor:',
                style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 14,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 4),
              Text(
                username,
                style: TextStyle(
                  fontSize: isSmallScreen ? 16 : 18,
                  color: Colors.indigo,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (role.isNotEmpty) ...[
                SizedBox(height: 2),
                Text(
                  role,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 12 : 14,
                    color: Colors.grey[600],
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
    final isEnabled = selectedMentorId != null && !isLoading;

    return Center(
      child: SizedBox(
        width: isVerySmallScreen ? double.infinity : null,
        child: ElevatedButton(
          onPressed: isEnabled ? _createLobby : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: isEnabled ? Colors.indigo : Colors.grey[400],
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 24 : 32,
              vertical: isSmallScreen ? 14 : 16,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 2,
            shadowColor: Color.lerp(Colors.indigo, Colors.transparent, 0.7), // ✅ FIXED: Replace withOpacity
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
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}