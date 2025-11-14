// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:codexhub01/collabscreen/collab_room_tabs.dart';
import '../services/live_lobby_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MentorInvites extends StatefulWidget {
  final String mentorId;
  const MentorInvites({super.key, required this.mentorId});

  @override
  State<MentorInvites> createState() => _MentorInvitesState();
}

class _MentorInvitesState extends State<MentorInvites> {
  final service = LiveLobbyService();
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> invites = [];
  bool isLoading = true;
  bool _isProcessing = false;
  String? _processingInviteId;
  RealtimeChannel? _invitesChannel;

  @override
  void initState() {
    super.initState();
    _loadInvites();
    _subscribeToRealtimeUpdates();
  }

  void _subscribeToRealtimeUpdates() {
    _invitesChannel = supabase
        .channel('mentor_invites_${widget.mentorId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_invitations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'mentor_id',
            value: widget.mentorId,
          ),
          callback: (payload) {
            debugPrint('🔄 Real-time update: ${payload.eventType}');
            if (mounted) {
              _loadInvites();
            }
          },
        )
        .subscribe((status, [_]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint('✅ Subscribed to real-time invites');
      }
    });
  }

  Future<void> _loadInvites() async {
    if (!mounted) return;
    
    setState(() => isLoading = true);
    
    try {
      final data = await service.fetchInvitesForMentor(widget.mentorId);
      
      // Debug: Check timestamps
      for (var invite in data) {
        final createdAt = invite['created_at']?.toString();
        if (createdAt != null) {
          debugPrint('📨 Invite ${invite['id']}: created_at = $createdAt');
        }
      }

      if (!mounted) return;

      setState(() {
        invites = data
            .where((invite) => invite['status']?.toString() == 'pending')
            .toList();
        isLoading = false;
      });
      
      debugPrint('📥 Loaded ${invites.length} pending invites');
    } catch (e) {
      debugPrint('❌ Error loading invites: $e');
      if (!mounted) return;
      setState(() => isLoading = false);
      _showErrorSnackBar('Failed to load invites');
    }
  }

  Future<void> _handleInvite(String inviteId, bool accept) async {
    if (_isProcessing) return;
    
    if (!mounted) return;
    setState(() {
      _isProcessing = true;
      _processingInviteId = inviteId;
    });

    // Remove from UI immediately for better UX
    final inviteIndex = invites.indexWhere((invite) => invite['id'] == inviteId);
    final removedInvite = inviteIndex != -1 ? invites[inviteIndex] : null;
    
    if (mounted) {
      setState(() {
        invites.removeWhere((invite) => invite['id'] == inviteId);
      });
    }

    try {
      debugPrint('🎯 Handling invite: $inviteId, accept: $accept');

      // 1. Update invitation status
      final updateResult = await supabase
          .from('live_invitations')
          .update({
            'status': accept ? 'accepted' : 'declined',
            'responded_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', inviteId)
          .select()
          .single()
          .timeout(const Duration(seconds: 10));

      debugPrint('✅ Invitation status updated to: ${updateResult['status']}');

      if (!mounted) return;
      
      _showSuccessSnackBar(
        accept ? '✅ Session accepted!' : '❌ Session declined.',
        accept ? Colors.green : Colors.red,
      );

      // If declined, stop here
      if (!accept) {
        debugPrint('❌ Invite declined - process complete');
        return;
      }

      // Continue with session setup for accepted invites
      await _setupAcceptedSession(inviteId);

    } catch (e, st) {
      debugPrint('❌ Error in _handleInvite: $e\n$st');
      
      // Add invite back if failed
      if (removedInvite != null && mounted) {
        setState(() {
          invites.insert(inviteIndex, removedInvite);
        });
      }
      
      if (mounted) {
        _showErrorSnackBar('Failed to process invite: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processingInviteId = null;
        });
      }
    }
  }

  Future<void> _setupAcceptedSession(String inviteId) async {
    debugPrint('🔄 Setting up accepted session for invite: $inviteId');
    
    try {
      // 1. Get invitation details
      final invitation = await supabase
          .from('live_invitations')
          .select('session_id, mentee_id, mentee_name, message')
          .eq('id', inviteId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (invitation == null) {
        throw Exception('Invitation not found: $inviteId');
      }

      final sessionId = invitation['session_id']?.toString();
      final menteeId = invitation['mentee_id']?.toString();
      final menteeName = invitation['mentee_name']?.toString() ?? 'Mentee';

      if (sessionId == null || menteeId == null) {
        throw Exception('Missing session_id or mentee_id in invitation');
      }

      debugPrint('🎯 Setting up session: $sessionId with mentee: $menteeName');

      // 2. Update live session with mentor
      await supabase
          .from('live_sessions')
          .update({
            'mentor_id': widget.mentorId,
            'is_live': true,
            'waiting': false,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', sessionId)
          .timeout(const Duration(seconds: 10));

      debugPrint('✅ Updated live_sessions with mentor_id');

      // 3. Get room details
      final sessionDetails = await supabase
          .from('live_sessions')
          .select('room_id')
          .eq('id', sessionId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (sessionDetails == null || sessionDetails['room_id'] == null) {
        throw Exception('No room_id found for session: $sessionId');
      }

      final roomId = sessionDetails['room_id'].toString();
      debugPrint('🎯 Room ID: $roomId');

      // 4. Auto-join mentor to room
      final existingMember = await supabase
          .from('room_members')
          .select('id')
          .eq('room_id', roomId)
          .eq('user_id', widget.mentorId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (existingMember == null) {
        await supabase.from('room_members').insert({
          'room_id': roomId,
          'user_id': widget.mentorId,
          'joined_at': DateTime.now().toUtc().toIso8601String(),
        }).timeout(const Duration(seconds: 10));
        debugPrint('✅ Mentor auto-joined to room_members');
      } else {
        debugPrint('✅ Mentor already in room_members');
      }

      // 5. Mark room as having active session
      await supabase
          .from('rooms')
          .update({'has_active_session': true})
          .eq('id', roomId)
          .timeout(const Duration(seconds: 10));

      debugPrint('✅ Room marked as having active session');

      // 6. Navigate to collaboration room
      if (!mounted) return;

      debugPrint('🚀 Navigating to CollabRoomTabs...');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CollabRoomTabs(
            roomId: roomId,
            roomName: 'Session with $menteeName',
            menteeId: menteeId,
            mentorId: widget.mentorId,
            isMentor: true,
            sessionId: sessionId,
          ),
        ),
      );

    } catch (e) {
      debugPrint('❌ Error in _setupAcceptedSession: $e');
      rethrow;
    }
  }

  String _calculateTimeAgo(String? createdAt) {
    if (createdAt == null || createdAt.isEmpty) return 'Just now';
    
    try {
      // Handle different timestamp formats
      DateTime dateTime;
      if (createdAt.endsWith('Z')) {
        dateTime = DateTime.parse(createdAt).toLocal();
      } else if (createdAt.contains('+')) {
        dateTime = DateTime.parse(createdAt).toLocal();
      } else {
        // Assume UTC if no timezone specified
        dateTime = DateTime.parse('${createdAt}Z').toLocal();
      }
      
      final now = DateTime.now().toLocal();
      final difference = now.difference(dateTime);
      
      if (difference.isNegative) {
        debugPrint('⚠️ Time appears to be in future: $createdAt');
        return 'Just now';
      }
      
      if (difference.inSeconds < 60) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        final minutes = difference.inMinutes;
        return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
      } else if (difference.inHours < 24) {
        final hours = difference.inHours;
        return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
      } else if (difference.inDays < 30) {
        final days = difference.inDays;
        return '$days ${days == 1 ? 'day' : 'days'} ago';
      } else {
        final months = (difference.inDays / 30).floor();
        return '$months ${months == 1 ? 'month' : 'months'} ago';
      }
    } catch (e) {
      debugPrint('❌ Error parsing date "$createdAt": $e');
      return 'Recently';
    }
  }

  void _showSuccessSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  Widget _buildActionButtons(String inviteId, bool isSmallScreen) {
    final isProcessingThis = _isProcessing && _processingInviteId == inviteId;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ElevatedButton.icon(
          onPressed: isProcessingThis ? null : () => _handleInvite(inviteId, false),
          icon: isProcessingThis 
              ? SizedBox(
                  width: isSmallScreen ? 16 : 18,
                  height: isSmallScreen ? 16 : 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.red,
                  ),
                )
              : Icon(
                  Icons.close,
                  size: isSmallScreen ? 16 : 18,
                ),
          label: Text(
            isProcessingThis ? 'Processing...' : 'Decline',
            style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[50],
            foregroundColor: Colors.red,
            elevation: 0,
          ),
        ),
        SizedBox(width: isSmallScreen ? 8 : 12),
        ElevatedButton.icon(
          onPressed: isProcessingThis ? null : () => _handleInvite(inviteId, true),
          icon: isProcessingThis 
              ? SizedBox(
                  width: isSmallScreen ? 16 : 18,
                  height: isSmallScreen ? 16 : 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.green,
                  ),
                )
              : Icon(
                  Icons.check,
                  size: isSmallScreen ? 16 : 18,
                ),
          label: Text(
            isProcessingThis ? 'Processing...' : 'Accept & Join',
            style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green[50],
            foregroundColor: Colors.green,
            elevation: 0,
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _invitesChannel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final isVerySmallScreen = screenSize.width < 400;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Session Invitations',
          style: TextStyle(fontSize: isSmallScreen ? 18 : 20),
        ),
        backgroundColor: Colors.indigo,
        actions: [
          if (_isProcessing)
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
              onPressed: _loadInvites,
              tooltip: 'Refresh invites',
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadInvites,
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : invites.isEmpty
                  ? _buildEmptyState(isSmallScreen)
                  : ListView.builder(
                      padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                      itemCount: invites.length,
                      itemBuilder: (context, index) {
                        final invite = invites[index];
                        final menteeName = invite['mentee_name']?.toString() ?? 'Unknown Mentee';
                        final message = invite['message']?.toString();
                        final createdAt = invite['created_at']?.toString();
                        final timeAgo = _calculateTimeAgo(createdAt);
                        
                        return _buildInviteCard(
                          invite, 
                          menteeName, 
                          message,
                          timeAgo, 
                          isSmallScreen, 
                          isVerySmallScreen
                        );
                      },
                    ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isSmallScreen) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 24 : 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: isSmallScreen ? 64 : 80,
              color: Colors.grey[400],
            ),
            SizedBox(height: isSmallScreen ? 16 : 20),
            Text(
              'No pending invites',
              style: TextStyle(
                fontSize: isSmallScreen ? 18 : 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: isSmallScreen ? 8 : 12),
            Text(
              'When mentees request live sessions,\ninvites will appear here',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                color: Colors.grey[500],
              ),
            ),
            SizedBox(height: isSmallScreen ? 16 : 20),
            ElevatedButton.icon(
              onPressed: _loadInvites,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteCard(
    Map<String, dynamic> invite, 
    String menteeName, 
    String? message,
    String timeAgo,
    bool isSmallScreen, 
    bool isVerySmallScreen
  ) {
    final inviteId = invite['id'].toString();
    final createdAt = invite['created_at']?.toString();

    return Card(
      margin: EdgeInsets.all(isSmallScreen ? 6 : 8),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.person,
                  color: Colors.indigo,
                  size: isSmallScreen ? 20 : 24,
                ),
                SizedBox(width: isSmallScreen ? 8 : 12),
                Expanded(
                  child: Text(
                    'Live Session Request',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isSmallScreen ? 16 : 18,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: isSmallScreen ? 12 : 14,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // Debug timestamp (visible in debug mode only)
                    if (createdAt != null)
                      Text(
                        '${createdAt.substring(11, 16)} UTC',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[400],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 8 : 12),
            Text(
              'From: $menteeName',
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: isSmallScreen ? 4 : 6),
            
            if (message != null && message.isNotEmpty) ...[
              SizedBox(height: isSmallScreen ? 8 : 12),
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[100]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.message,
                          size: isSmallScreen ? 14 : 16,
                          color: Colors.blue[700],
                        ),
                        SizedBox(width: isSmallScreen ? 6 : 8),
                        Text(
                          'Message from $menteeName:',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue[800],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isSmallScreen ? 4 : 6),
                    Text(
                      message,
                      style: TextStyle(
                        fontSize: isSmallScreen ? 13 : 15,
                        color: Colors.grey[800],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isSmallScreen ? 8 : 12),
            ] else ...[
              SizedBox(height: isSmallScreen ? 4 : 6),
              Text(
                'Tap buttons below to accept or decline',
                style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 14,
                  color: Colors.grey[500],
                ),
              ),
            ],
            
            SizedBox(height: isSmallScreen ? 12 : 16),
            _buildActionButtons(inviteId, isSmallScreen),
          ],
        ),
      ),
    );
  }
}