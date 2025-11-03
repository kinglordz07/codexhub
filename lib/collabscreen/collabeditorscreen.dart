import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class CollabCodeEditorScreen extends StatefulWidget {
  final String roomId;
  final bool isMentor;
  final bool isReadOnly;
  final String? liveSessionId;

  const CollabCodeEditorScreen({
    required this.roomId,
    required this.isMentor,
    required this.isReadOnly,
    this.liveSessionId,
    super.key,
  });

  @override
  State<CollabCodeEditorScreen> createState() => _CollabCodeEditorScreenState();
}

class _CollabCodeEditorScreenState extends State<CollabCodeEditorScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _feedbackController = TextEditingController();
  final ScrollController _codeScrollController = ScrollController();
  final ScrollController _contentScrollController = ScrollController();

  bool _isSaving = false;
  bool _isLoading = true;
  bool _canEdit = false;
  bool _isLocalEdit = false;
  bool _isConnected = true;
  bool _isExecuting = false;

  String _selectedLanguage = 'python';
  String _output = '';
  String? _mentorId;
  String? _currentUserId;

  // ✅ OPTIMIZED: Faster timers for real-time typing
  Timer? _typingTimer;
  Timer? _cursorTimer;
  Timer? _reconnectTimer;
  Timer? _autoSaveTimer;
  Timer? _languageChangeTimer;
  Timer? _feedbackTimer;
  Timer? _permissionMonitorTimer;
  RealtimeChannel? _channel;

  String? _lastLocalCode;
  String? _lastLocalFeedback;

  // ✅ NEW: Permission management
  List<String> _allowedUsers = [];
  List<Map<String, dynamic>> _roomMembers = [];
  Map<String, dynamic> _currentSession = {};

  // ✅ FIXED: Simple text-based snippets
  final Map<String, String> _defaultSnippets = {
    'python': '''# Welcome to Python Collaboration!
# You can see real-time changes from other users
# Try editing this code and see others see your changes instantly!

def greet(name):
    return f"Hello, {name}!"

# Example usage
print(greet("Collaborator"))
print("This is real-time code collaboration!")
''',
    'java': '''// Welcome to Java Collaboration!
// You can see real-time changes from other users
// Try editing this code and see others see your changes instantly!

public class Main {
    public static void main(String[] args) {
        System.out.println("Hello from Java Collaboration!");
        System.out.println("Edit this code and watch others see your changes!");
        
        // Example method
        String message = createWelcomeMessage("Java Developer");
        System.out.println(message);
    }
    
    public static String createWelcomeMessage(String name) {
        return "Welcome, " + name + "! This is real-time collaboration!";
    }
}
''',
    'csharp': '''// Welcome to C# Collaboration!
// You can see real-time changes from other users
// Try editing this code and see others see your changes instantly!

using System;

class Program {
    static void Main() {
        Console.WriteLine("Hello from C# Collaboration!");
        Console.WriteLine("Edit this code and watch others see your changes!");
        
        // Example method
        string message = CreateWelcomeMessage("C# Developer");
        Console.WriteLine(message);
    }
    
    static string CreateWelcomeMessage(string name) {
        return "Welcome, " + name + "! This is real-time collaboration!";
    }
}
''',
  };

  // Language mapping for execution
  final Map<String, String> _languageMapping = {
    'python': 'python3',
    'java': 'java',
    'csharp': 'dotnet',
  };

  bool get _isSmallScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width < 600;
  }

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _setupPermissionMonitoring(); // ✅ ADDED: Permission monitoring
  }

  void _initializeApp() {
    Future.delayed(Duration.zero, () {
      if (mounted) {
        _initSession();
      }
    });
    _setupConnectivityListener();
  }

  // ✅ NEW: Permission monitoring
  void _setupPermissionMonitoring() {
    _permissionMonitorTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!mounted) return;
      
      debugPrint('📊 PERMISSION MONITOR:');
      debugPrint('  - Current User: $_currentUserId');
      debugPrint('  - Mentor ID: $_mentorId');
      debugPrint('  - Can Edit: $_canEdit');
      debugPrint('  - Allowed Users: ${_allowedUsers.length}');
      debugPrint('  - Room Members: ${_roomMembers.length}');
      debugPrint('  - Is Mentor: ${_isMentorCurrentUser()}');
    });
  }

  Future<void> _initSession() async {
    if (!mounted) return;
    
    try {
      if (mounted) {
        setState(() => _isLoading = true);
      }
      
      await _loadSession();
      
      // ✅ FIXED: LOAD PERMISSIONS FIRST before setting up anything else
      await _loadPermissionsAndMembers();
      
      _setupListeners();
      _setupAutoSave();
      await _subscribeRealtime();
      
    } catch (e) {
      debugPrint('❌ Error initializing session: $e');
      _safeShowErrorSnackBar('Failed to initialize session');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ✅ FIXED: More reliable permission loading
  Future<void> _loadPermissionsAndMembers() async {
    try {
      debugPrint('🔄 Loading permissions and members...');
      
      // Load allowed users for code review
      final permissionsResponse = await _supabase
          .from('code_review_permissions')
          .select('user_id')
          .eq('room_id', widget.roomId)
          .timeout(const Duration(seconds: 10));

      final allowedUsers = (permissionsResponse as List<dynamic>)
          .map((p) => p['user_id'] as String)
          .where((id) => id.isNotEmpty)
          .toList();

      debugPrint('✅ Loaded ${allowedUsers.length} allowed users: $allowedUsers');
      
      if (mounted) {
        setState(() {
          _allowedUsers = allowedUsers;
        });
      }

      // ✅ ALWAYS update edit permission after loading permissions
      _updateEditPermission();

      // Load room members
      final membersResponse = await _supabase
          .from('room_members')
          .select('user_id')
          .eq('room_id', widget.roomId)
          .timeout(const Duration(seconds: 10));

      final memberUserIds = (membersResponse as List<dynamic>)
          .map((m) => m['user_id'] as String)
          .where((id) => id.isNotEmpty)
          .toList();

      debugPrint('✅ Loaded ${memberUserIds.length} room members');

      if (memberUserIds.isEmpty) {
        if (mounted) {
          setState(() => _roomMembers = []);
        }
        return;
      }

      // Load user profiles
      try {
        final profilesResponse = await _supabase
            .from('profiles_new')
            .select('id, username, role, avatar_url')
            .inFilter('id', memberUserIds)
            .timeout(const Duration(seconds: 10));

        final profilesMap = <String, Map<String, dynamic>>{};
        for (final profile in (profilesResponse as List<dynamic>)) {
          final profileMap = profile as Map<String, dynamic>;
          final userId = profileMap['id'] as String;
          profilesMap[userId] = profileMap;
        }

        if (mounted) {
          setState(() {
            _roomMembers = memberUserIds.map((userId) {
              final profile = profilesMap[userId];
              return {
                'user_id': userId,
                'profiles_new': profile ?? {
                  'username': _generateUsernameFromId(userId),
                  'role': 'viewer',
                  'avatar_url': null,
                },
              };
            }).toList();
          });
        }
        
        debugPrint('✅ Successfully loaded ${_roomMembers.length} member profiles');

      } catch (profileError) {
        debugPrint('⚠️ Could not load profiles, using fallback: $profileError');
        
        // Fallback: create basic member info without profiles
        if (mounted) {
          setState(() {
            _roomMembers = memberUserIds.map((userId) {
              return {
                'user_id': userId,
                'profiles_new': {
                  'username': _generateUsernameFromId(userId),
                  'role': 'viewer',
                  'avatar_url': null,
                },
              };
            }).toList();
          });
        }
      }

    } catch (e) {
      debugPrint('❌ Error loading permissions: $e');
      if (mounted) {
        setState(() {
          _allowedUsers = [];
          _roomMembers = [];
        });
      }
      // ✅ STILL update edit permission even if loading fails
      _updateEditPermission();
    }
  }

  // ✅ FIXED: Force permission update with better state management
  void _updateEditPermission() {
    if (!mounted) return;
    
    if (_currentSession.isEmpty) {
      debugPrint('⚠️ Cannot update edit permission: No session data');
      return;
    }
    
    final newCanEdit = _checkEditPermission(_currentSession);
    
    debugPrint('🔄 UPDATING EDIT PERMISSION:');
    debugPrint('  - Current: $_canEdit');
    debugPrint('  - New: $newCanEdit');
    debugPrint('  - Changed: ${newCanEdit != _canEdit}');
    
    if (newCanEdit != _canEdit) {
      setState(() {
        _canEdit = newCanEdit;
      });
      
      if (_canEdit) {
        _safeShowSuccessSnackBar('🎉 You can now edit code!');
        debugPrint('✅ Edit permission GRANTED');
      } else {
        _safeShowSuccessSnackBar('👀 You are in view-only mode');
        debugPrint('✅ Edit permission REVOKED - View only');
      }
    } else {
      debugPrint('⏭️  Edit permission unchanged');
    }
  }

  String _generateUsernameFromId(String userId) {
    if (userId.isEmpty) return 'Unknown User';
    if (userId.length < 8) return 'User $userId';
    return 'User ${userId.substring(0, 8)}...';
  }

  void _setupConnectivityListener() {
    _reconnectTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (!_isConnected && mounted) {
        _subscribeRealtime();
      }
    });
  }

  void _setupAutoSave() {
    _codeController.addListener(() {
      if (!_canEdit || _isLocalEdit) return;

      _autoSaveTimer?.cancel();
      _autoSaveTimer = Timer(const Duration(seconds: 10), () {
        if (_codeController.text != _lastLocalCode) {
          _saveCode();
        }
      });
    });
  }

  // ✅ FIXED: Better session loading
  Future<void> _loadSession() async {
    try {
      _currentUserId = _supabase.auth.currentUser?.id;
      debugPrint('👤 Loading session for user: $_currentUserId');

      final session = await _supabase
          .from('live_sessions')
          .select()
          .eq('room_id', widget.roomId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (session != null) {
        _mentorId = session['mentor_id'] as String?;
        _selectedLanguage = session['language'] ?? 'python';
        _currentSession = session;
        
        debugPrint('📋 Session Loaded:');
        debugPrint('  - Mentor: $_mentorId');
        debugPrint('  - Mentee: ${session['mentee_id']}');
        debugPrint('  - Language: $_selectedLanguage');
        
        _codeController.text = session['code'] ?? _defaultSnippets[_selectedLanguage]!;
        _lastLocalCode = _codeController.text;
        
        _output = session['output'] ?? '';
        _feedbackController.text = session['mentor_feedback'] ?? '';
        _lastLocalFeedback = _feedbackController.text;

        // ✅ PERMISSION will be updated in _loadPermissionsAndMembers()
        
      } else {
        debugPrint('🆕 Creating new session...');
        final newSession = await _supabase.from('live_sessions').insert({
          'room_id': widget.roomId,
          'language': _selectedLanguage,
          'code': _defaultSnippets[_selectedLanguage] ?? '',
          'is_live': true,
          'waiting': false,
          'mentor_id': widget.isMentor ? _currentUserId : null,
          'mentee_id': !widget.isMentor ? _currentUserId : null,
        }).select().single().timeout(const Duration(seconds: 10));

        _currentSession = newSession;
        _codeController.text = newSession['code'] ?? '';
        _lastLocalCode = _codeController.text;
        _output = newSession['output'] ?? '';
        _feedbackController.text = newSession['mentor_feedback'] ?? '';
        _lastLocalFeedback = _feedbackController.text;
        
        // ✅ PERMISSION will be updated in _loadPermissionsAndMembers()
      }
    } catch (e) {
      debugPrint('❌ Error loading session: $e');
      rethrow;
    }
  }

  // ✅ FIXED: Consistent and reliable permission logic
  bool _checkEditPermission(Map<String, dynamic> session) {
    if (_currentUserId == null) {
      debugPrint('❌ Permission check failed: No current user ID');
      return false;
    }
    
    if (session.isEmpty) {
      debugPrint('❌ Permission check failed: No session data');
      return false;
    }
    
    final sessionMentorId = session['mentor_id'] as String?;
    final sessionMenteeId = session['mentee_id'] as String?;
    
    debugPrint('🔐 PERMISSION CHECK:');
    debugPrint('  - Current User: $_currentUserId');
    debugPrint('  - Session Mentor: $sessionMentorId');
    debugPrint('  - Session Mentee: $sessionMenteeId');
    debugPrint('  - Allowed Users: $_allowedUsers');
    
    // ✅ MENTORS always can edit
    if (sessionMentorId != null && _currentUserId == sessionMentorId) {
      debugPrint('  ✅ User is MENTOR - Can edit');
      return true;
    }
    
    // ✅ MENTEES always can edit
    if (sessionMenteeId != null && _currentUserId == sessionMenteeId) {
      debugPrint('  ✅ User is MENTEE - Can edit');
      return true;
    }
    
    // ✅ VIEWERS: Check if they are in allowed users list
    final isAllowedViewer = _allowedUsers.contains(_currentUserId);
    debugPrint('  ${isAllowedViewer ? '✅' : '❌'} User is ${isAllowedViewer ? 'ALLOWED VIEWER' : 'RESTRICTED VIEWER'}');
    
    return isAllowedViewer;
  }

  void _setupListeners() {
    // ✅ OPTIMIZED: Code editor typing with better logging
    _codeController.addListener(() {
      debugPrint('⌨️  Code Controller Changed:');
      debugPrint('  - _canEdit: $_canEdit');
      debugPrint('  - _isLocalEdit: $_isLocalEdit');
      debugPrint('  - Text length: ${_codeController.text.length}');
      
      if (!_canEdit || _isLocalEdit) {
        debugPrint('⏭️  Skipping typing (cannot edit or is local edit)');
        return;
      }

      _isLocalEdit = true;

      _restartTypingTimer(() async {
        if (_codeController.text != _lastLocalCode) {
          debugPrint('📤 Sending code update to server');
          _lastLocalCode = _codeController.text;
          await _updateLiveField('code', _codeController.text);
        } else {
          debugPrint('⏭️  Skipping update (same content)');
        }
        _isLocalEdit = false;
      });

      // ✅ OPTIMIZED: Faster cursor updates
      _restartCursorTimer(() async {
        await _updateLiveField(
          _isMentorCurrentUser() ? 'mentor_cursor' : 'mentee_cursor',
          _codeController.selection.baseOffset,
        );
      });
    });

    // ✅ NEW: Optimized feedback typing with separate timer
    _feedbackController.addListener(() {
      if (!_isMentorCurrentUser()) {
        debugPrint('⏭️  Only mentors can send feedback updates');
        return;
      }
      
      _restartFeedbackTimer(() async {
        if (_feedbackController.text != _lastLocalFeedback) {
          debugPrint('📤 Sending feedback update to server');
          _lastLocalFeedback = _feedbackController.text;
          await _updateLiveField('mentor_feedback', _feedbackController.text);
        }
      });
    });
  }

  // ✅ NEW: Separate timer for feedback with faster debounce
  void _restartFeedbackTimer(VoidCallback callback) {
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 300), callback);
  }

  // ✅ FIXED: More reliable user permission granting
  Future<void> _allowUserInCodeReview(String userId) async {
    debugPrint('➕ ALLOWING USER: $userId');
    debugPrint('➕ Current user: $_currentUserId');
    debugPrint('➕ Is mentor: ${_isMentorCurrentUser()}');
    debugPrint('➕ Room ID: ${widget.roomId}');
    
    if (!_isMentorCurrentUser()) {
      debugPrint('❌ PERMISSION DENIED: Not mentor');
      _safeShowErrorSnackBar('Only mentors can manage code review permissions.');
      return;
    }

    try {
      debugPrint('🟡 Inserting into code_review_permissions...');
      
      final response = await _supabase.from('code_review_permissions').insert({
        'room_id': widget.roomId,
        'user_id': userId,
        'allowed_by': _currentUserId,
        'granted_at': DateTime.now().toUtc().toIso8601String(),
      }).select().single().timeout(const Duration(seconds: 15));

      debugPrint('✅ Insert successful: $response');
      _safeShowSuccessSnackBar('✅ User allowed in code review');
      
      // ✅ FORCE refresh everything
      await _loadPermissionsAndMembers();
      
      // ✅ DOUBLE CHECK: Force permission update again
      _updateEditPermission();
      
    } catch (e) {
      debugPrint('❌ Error allowing user: $e');
      if (e.toString().contains('duplicate key')) {
        _safeShowErrorSnackBar('User already has edit access');
        // ✅ Still refresh permissions even if duplicate
        await _loadPermissionsAndMembers();
      } else {
        _safeShowErrorSnackBar('Failed to allow user in code review');
      }
    }
  }

  // ✅ FIXED: More reliable user permission removal
  Future<void> _removeUserFromCodeReview(String userId) async {
    debugPrint('➖ REMOVING USER: $userId');
    debugPrint('➖ Current user: $_currentUserId');
    debugPrint('➖ Is mentor: ${_isMentorCurrentUser()}');
    
    if (!_isMentorCurrentUser()) {
      debugPrint('❌ PERMISSION DENIED: Not mentor');
      _safeShowErrorSnackBar('Only mentors can manage code review permissions.');
      return;
    }

    try {
      debugPrint('🟡 Deleting from code_review_permissions...');
      
      final response = await _supabase
          .from('code_review_permissions')
          .delete()
          .eq('room_id', widget.roomId)
          .eq('user_id', userId)
          .timeout(const Duration(seconds: 15));

      debugPrint('✅ Delete successful: $response');
      _safeShowSuccessSnackBar('👋 User removed from code review');
      
      // ✅ FORCE refresh everything
      await _loadPermissionsAndMembers();
      
      // ✅ DOUBLE CHECK: Force permission update again
      _updateEditPermission();
      
    } catch (e) {
      debugPrint('❌ Error removing user: $e');
      _safeShowErrorSnackBar('Failed to remove user from code review');
    }
  }

  // ✅ FIXED: Better permission manager that shows ALL users correctly
  void _showPermissionManager() {
    debugPrint('👥 Showing permission manager');
    debugPrint('👥 Room members: ${_roomMembers.length}');
    debugPrint('👥 Current user: $_currentUserId');
    debugPrint('👥 Is mentor: ${_isMentorCurrentUser()}');
    debugPrint('👥 Allowed users: $_allowedUsers');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Manage Code Editing Access'),
              content: SizedBox(
                width: double.maxFinite,
                child: _roomMembers.isEmpty
                    ? const Center(child: Text('No members in this room'))
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Control who can edit code (besides mentor & mentee):'),
                          const SizedBox(height: 16),
                          // ✅ LEGEND
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                _buildAccessLegendItem('👨‍🏫 Mentor', 'Always can edit', Colors.green),
                                _buildAccessLegendItem('👨‍🎓 Mentee', 'Always can edit', Colors.blue),
                                _buildAccessLegendItem('✅ Allowed', 'Can edit', Colors.orange),
                                _buildAccessLegendItem('👀 Viewer', 'View only', Colors.grey),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: _roomMembers.length,
                              itemBuilder: (context, index) {
                                final member = _roomMembers[index];
                                final memberUserId = member['user_id'] as String;
                                final profile = member['profiles_new'] as Map<String, dynamic>;
                                final username = profile['username'] as String? ?? 'Unknown User';
                                final role = profile['role'] as String? ?? 'viewer';
                                final isAllowed = _allowedUsers.contains(memberUserId);
                                final isCurrentUser = memberUserId == _currentUserId;
                                final isMentorUser = role == 'mentor';
                                final isMenteeUser = memberUserId == _currentSession['mentee_id'];
                                
                                debugPrint("👤 Member $username: role=$role, isMentor=$isMentorUser, isMentee=$isMenteeUser, isAllowed=$isAllowed");

                                // ✅ DON'T SHOW: Current user (you can't manage yourself)
                                if (isCurrentUser) {
                                  return const SizedBox.shrink();
                                }

                                // ✅ DON'T SHOW: Mentors (they always have access)
                                if (isMentorUser) {
                                  return const SizedBox.shrink();
                                }

                                // ✅ SHOW EVERYONE ELSE: mentees and viewers
                                String displayRole = role;
                                Color roleColor = Colors.grey;
                                
                                if (isMenteeUser) {
                                  displayRole = 'Mentee';
                                  roleColor = Colors.blue;
                                } else if (isAllowed) {
                                  displayRole = 'Allowed Viewer';
                                  roleColor = Colors.orange;
                                } else {
                                  displayRole = 'Viewer';
                                  roleColor = Colors.grey;
                                }

                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 4),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: roleColor,
                                      child: Text(
                                        username[0].toUpperCase(),
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                    ),
                                    title: Text(username),
                                    subtitle: Text(
                                      displayRole,
                                      style: TextStyle(
                                        color: roleColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // ✅ MENTEES: Always can edit, no toggle
                                        if (isMenteeUser)
                                          const Icon(
                                            Icons.verified,
                                            color: Colors.blue,
                                          )
                                        // ✅ VIEWERS: Show toggle
                                        else if (!isMenteeUser)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (isAllowed)
                                                const Icon(
                                                  Icons.check_circle,
                                                  color: Colors.green,
                                                )
                                              else
                                                const Icon(
                                                  Icons.remove_circle,
                                                  color: Colors.red,
                                                ),
                                              const SizedBox(width: 8),
                                              isAllowed
                                                  ? IconButton(
                                                      icon: const Icon(Icons.person_remove, color: Colors.red),
                                                      onPressed: () async {
                                                        debugPrint('➖ Removing user: $memberUserId');
                                                        await _removeUserFromCodeReview(memberUserId);
                                                        setDialogState(() {}); // Refresh UI
                                                      },
                                                    )
                                                  : IconButton(
                                                      icon: const Icon(Icons.person_add, color: Colors.green),
                                                      onPressed: () async {
                                                        debugPrint('➕ Adding user: $memberUserId');
                                                        await _allowUserInCodeReview(memberUserId);
                                                        setDialogState(() {}); // Refresh UI
                                                      },
                                                    ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ✅ NEW: Helper for legend with colors
  Widget _buildAccessLegendItem(String text, String subtitle, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runCode() async {
    if (!_canEdit || _isExecuting) return;
    
    if (mounted) {
      setState(() {
        _isExecuting = true;
        _output = '🔄 Executing code...';
      });
    }

    try {
      String result;
      
      try {
        result = await _executeCodeWithJDoodle(_codeController.text, _selectedLanguage);
      } catch (e) {
        debugPrint('JDoodle API failed: $e');
        result = await _executeCodeWithReplit(_codeController.text, _selectedLanguage);
      }
      
      if (mounted) {
        setState(() => _output = result);
      }
      await _updateLiveField('output', result);
    } catch (e) {
      if (mounted) {
        setState(() => _output = '❌ All execution services are temporarily unavailable.\nPlease try again later.');
      }
      debugPrint('❌ All execution failed: $e');
    } finally {
      if (mounted) {
        setState(() => _isExecuting = false);
      }
    }
  }

  Future<String> _executeCodeWithReplit(String code, String language) async {
    const String replitApiUrl = 'https://emkc.org/api/v2/piston/execute';
    
    final String pistonLanguage = _languageMapping[language] ?? language;
    
    String stdin = '';
    if (language == 'python' && code.contains('input(')) {
      stdin = 'test_user\n';
    } else if (language == 'csharp' && code.contains('Console.ReadLine()')) {
      stdin = 'test_user\n';
    }
    
    final Map<String, dynamic> requestData = {
      'language': pistonLanguage,
      'version': _getLanguageVersion(language),
      'files': [{'name': _getFileName(language), 'content': code}],
      'stdin': stdin,
    };

    final args = _getExecutionArgs(language);
    if (args.isNotEmpty) {
      requestData['args'] = args;
    }

    try {
      final response = await http.post(
        Uri.parse(replitApiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestData),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final run = data['run'];
        
        if (run['stderr'] != null && (run['stderr'] as String).isNotEmpty) {
          return '❌ COMPILATION ERROR:\n${run['stderr']}';
        } else if (run['stdout'] != null) {
          return (run['stdout'] as String).trim();
        } else {
          return '✅ Program executed successfully (no output)';
        }
      } else {
        return '❌ API Error (HTTP ${response.statusCode})';
      }
    } on TimeoutException {
      return '❌ Execution timeout';
    } catch (e) {
      throw Exception('Replit API failed: $e');
    }
  }

  Future<String> _executeCodeWithJDoodle(String code, String language) async {
    const String clientId = '9d262318b31550002aa19e7bd46bfd9a';
    const String clientSecret = '6038b60f28cc7b354a6448c940539ea43d64bc3dce1d635ecebdf17b2a86ac10';
    
    try {
      final response = await http.post(
        Uri.parse('https://api.jdoodle.com/v1/execute'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'clientId': clientId,
          'clientSecret': clientSecret,
          'script': code,
          'language': _getJDoodleLanguage(language),
          'versionIndex': _getJDoodleVersionIndex(language),
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['error'] != null && (data['error'] as String).isNotEmpty) {
          return '❌ JDoodle Error:\n${data['error']}';
        } else if (data['output'] != null) {
          String output = (data['output'] as String).trim();
          return output.isEmpty ? '✅ Program executed successfully (no output)' : output;
        } else {
          return '✅ Program executed successfully (no output)';
        }
      } else {
        return '❌ JDoodle API Error (HTTP ${response.statusCode})';
      }
    } on TimeoutException {
      return '❌ Execution timeout';
    } catch (e) {
      throw Exception('JDoodle API failed: $e');
    }
  }

  String _getLanguageVersion(String language) {
    switch (language) {
      case 'python': return '3.10.0';
      case 'java': return '15.0.2';
      case 'csharp': return '6.12.0';
      default: return 'latest';
    }
  }

  String _getFileName(String language) {
    switch (language) {
      case 'java': return 'Main.java';
      case 'csharp': return 'Program.cs';
      case 'python': return 'main.py';
      default: return 'main.py';
    }
  }

  List<String> _getExecutionArgs(String language) {
    if (language == 'java') return ['Main'];
    return [];
  }

  String _getJDoodleLanguage(String language) {
    switch (language) {
      case 'python': return 'python3';
      case 'java': return 'java';
      case 'csharp': return 'csharp';
      default: return 'python3';
    }
  }

  String _getJDoodleVersionIndex(String language) {
    switch (language) {
      case 'python': return '3';
      case 'java': return '3';
      case 'csharp': return '3';
      default: return '0';
    }
  }

  // ✅ FIXED: Simplified real-time subscription
  Future<void> _subscribeRealtime() async {
    try {
      await _channel?.unsubscribe();
      final channelName = 'live_sessions:${widget.roomId}';

      _channel = _supabase.channel(channelName)
        ..onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'live_sessions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.roomId,
          ),
          callback: (payload) {
            Future.microtask(() {
              if (!mounted) return;
              final newData = payload.newRecord;
              if (newData.isEmpty) return;
              
              debugPrint('📡 REAL-TIME UPDATE RECEIVED:');
              debugPrint('  - From user: ${newData['last_editor']}');
              debugPrint('  - Is local edit: $_isLocalEdit');
              
              // ✅ FIXED: Only ignore if it's OUR OWN local edit
              if (_isLocalEdit && newData['last_editor'] == _currentUserId) {
                debugPrint('🔄 Ignoring own update');
                return;
              }
              
              // ✅ EVERYONE sees updates (viewers, mentees, mentors)
              _handleRemoteUpdate(newData);
            });
          },
        )
        // ✅ Subscribe to permission changes
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'code_review_permissions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: widget.roomId,
          ),
          callback: (payload) {
            Future.microtask(() {
              if (!mounted) return;
              debugPrint('🔄 Permission stream update: ${payload.eventType}');
              _loadPermissionsAndMembers(); // Reload permissions when they change
            });
          },
        )
        ..subscribe((RealtimeSubscribeStatus status, [Object? error]) {
          Future.microtask(() {
            if (!mounted) return;
            
            switch (status) {
              case RealtimeSubscribeStatus.subscribed:
                setState(() => _isConnected = true);
                debugPrint('✅ Real-time connected - ALL users can see updates');
                break;
              case RealtimeSubscribeStatus.timedOut:
              case RealtimeSubscribeStatus.closed:
                setState(() => _isConnected = false);
                debugPrint('❌ Real-time disconnected');
                Future.delayed(const Duration(seconds: 2), _subscribeRealtime);
                break;
              default:
                setState(() => _isConnected = false);
            }
          });
        });

  } catch (e) {
    debugPrint('❌ Error subscribing to realtime: $e');
    if (mounted) setState(() => _isConnected = false);
  }
  }

  void _handleRemoteUpdate(Map<String, dynamic> newData) {
    if (!mounted) return;
    
    debugPrint('🔄 HANDLING REMOTE UPDATE:');
    debugPrint('  - _isLocalEdit: $_isLocalEdit');
    debugPrint('  - _canEdit: $_canEdit');
    debugPrint('  - Remote data keys: ${newData.keys}');
    
    setState(() {
      final remoteCode = newData['code'];
      // ✅ FIXED: EVERYONE receives real-time updates, NO PERMISSION CHECKS
      if (remoteCode != null && remoteCode != _codeController.text && remoteCode != _lastLocalCode) {
        debugPrint('👀 Applying code update from others');
        _updateCodeControllerSafely(remoteCode as String);
      } else {
        debugPrint('⏭️  Skipping code update (same content or local edit)');
      }
      
      // ✅ FIXED: EVERYONE receives feedback updates
      final remoteFeedback = newData['mentor_feedback'];
      if (remoteFeedback != null && remoteFeedback != _feedbackController.text && remoteFeedback != _lastLocalFeedback) {
        debugPrint('👀 Applying feedback update from mentor');
        _feedbackController.text = remoteFeedback as String;
        _lastLocalFeedback = remoteFeedback;
      }
      
      if (newData['output'] != null && newData['output'] != _output) {
        _output = newData['output'] as String;
        debugPrint('👀 Applying output update');
      }
      
      if (newData['language'] != null && newData['language'] != _selectedLanguage) {
        _selectedLanguage = newData['language'] as String;
        debugPrint('👀 Applying language update');
      }
    });
  }

  void _updateCodeControllerSafely(String remoteCode) {
    debugPrint('🔄 Updating code controller safely:');
    debugPrint('  - Remote code length: ${remoteCode.length}');
    debugPrint('  - Current code length: ${_codeController.text.length}');
    
    final cursorOffset = _codeController.selection.baseOffset;
    final scrollOffset = _codeScrollController.offset;
    
    _codeController.value = TextEditingValue(
      text: remoteCode,
      selection: TextSelection.collapsed(offset: cursorOffset.clamp(0, remoteCode.length).toInt()),
    );
    _lastLocalCode = remoteCode;
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_codeScrollController.hasClients) {
        _codeScrollController.jumpTo(scrollOffset);
        debugPrint('✅ Code updated and scrolled to position');
      }
    });
  }

  Future<void> _updateLiveField(String field, dynamic value) async {
    try {
      debugPrint('📤 Updating $field: ${value.toString().length} chars');
      
      await _supabase.from('live_sessions').update({
        field: value,
        'last_editor': _currentUserId,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('room_id', widget.roomId).timeout(const Duration(seconds: 5));
      
      debugPrint('✅ Successfully updated $field');
    } catch (e) {
      debugPrint('⚠️ Error updating $field: $e');
    }
  }

  // ✅ FIXED: Better mentor check with debugging
  bool _isMentorCurrentUser() {
    if (_currentUserId == null || _mentorId == null) {
      debugPrint('❌ Mentor Check Failed: currentUserId=$_currentUserId, mentorId=$_mentorId');
      return false;
    }
    
    final isMentor = _currentUserId == _mentorId;
    debugPrint('👨‍🏫 MENTOR CHECK: $isMentor (Current: $_currentUserId, Mentor: $_mentorId)');
    return isMentor;
  }

  // ✅ OPTIMIZED: Faster typing timer (300ms instead of 600ms)
  void _restartTypingTimer(VoidCallback callback) {
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 300), callback);
  }

  // ✅ OPTIMIZED: Faster cursor timer (200ms instead of 300ms)
  void _restartCursorTimer(VoidCallback callback) {
    _cursorTimer?.cancel();
    _cursorTimer = Timer(const Duration(milliseconds: 200), callback);
  }

  void _onLanguageChanged(String? newLanguage) {
    if (newLanguage == null || newLanguage == _selectedLanguage || !_canEdit) return;
    
    _languageChangeTimer?.cancel();
    _languageChangeTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _selectedLanguage = newLanguage;
          _codeController.text = _defaultSnippets[newLanguage] ?? '';
          _lastLocalCode = _codeController.text;
        });
        _updateLiveField('language', newLanguage);
      }
    });
  }

  Future<void> _saveCode() async {
    if (_isSaving || !_canEdit) return;
    
    if (mounted) setState(() => _isSaving = true);
    
    try {
      await _supabase.from('live_sessions').update({
        'code': _codeController.text,
        'language': _selectedLanguage,
        'output': _output,
        'mentor_feedback': _feedbackController.text,
        'last_editor': _currentUserId,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('room_id', widget.roomId);
      _safeShowSuccessSnackBar('💾 Code saved!');
    } catch (e) {
      debugPrint('❌ Error saving code: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _safeShowSuccessSnackBar(String message) {
    Future.microtask(() {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  void _safeShowErrorSnackBar(String message) {
    Future.microtask(() {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });
  }

  Widget _buildConnectionStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _isConnected ? Colors.green : Colors.orange,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isConnected ? Icons.circle : Icons.offline_bolt,
            color: Colors.white,
            size: 12,
          ),
          const SizedBox(width: 6),
          Text(
            _isConnected ? 'Live Connected' : 'Reconnecting...',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_isConnected) ...[
            const SizedBox(width: 4),
            Icon(Icons.visibility, color: Colors.white, size: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildLanguageSelector() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedLanguage,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(
          horizontal: _isSmallScreen ? 12 : 16,
          vertical: _isSmallScreen ? 14 : 16,
        ),
        labelText: 'Programming Language',
      ),
      items: const [
        DropdownMenuItem(value: 'python', child: Text('Python')),
        DropdownMenuItem(value: 'java', child: Text('Java')),
        DropdownMenuItem(value: 'csharp', child: Text('C#')),
      ],
      onChanged: _canEdit ? _onLanguageChanged : null,
    );
  }

  Widget _buildCodeEditor() {
    return Container(
      height: _isSmallScreen ? 250 : 350,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.shade50,
      ),
      child: Stack(
        children: [
          TextField(
            controller: _codeController,
            maxLines: null,
            expands: true,
            readOnly: !_canEdit, // ✅ Only prevent editing, not viewing
            scrollController: _codeScrollController,
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(_isSmallScreen ? 8 : 12),
              hintText: _canEdit ? 'Start coding...' : 'View-only mode - You can see real-time changes',
            ),
            style: TextStyle(
              fontFamily: 'RobotoMono',
              fontSize: _isSmallScreen ? 13 : 14,
              color: _canEdit ? Colors.black : Colors.grey.shade700,
            ),
          ),
          if (!_canEdit)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  border: Border.all(color: Colors.blue),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility, color: Colors.blue, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'View Only - Real-time',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOutputPanel() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(_isSmallScreen ? 12 : 16),
      decoration: BoxDecoration(
        border: Border.all(color: _isExecuting ? Colors.orange : Colors.blue.shade300),
        borderRadius: BorderRadius.circular(8),
        color: _isExecuting ? Colors.orange.shade50 : Colors.blue.shade50,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Output:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _isExecuting ? Colors.orange.shade800 : Colors.blue.shade800,
                  fontSize: _isSmallScreen ? 14 : 16,
                ),
              ),
              if (_isExecuting) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _output.isEmpty ? 'No output yet' : _output,
            style: TextStyle(
              fontSize: _isSmallScreen ? 14 : 16,
              fontFamily: 'RobotoMono',
              color: _output.isEmpty ? Colors.grey : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackPanel() {
    if (_isMentorCurrentUser()) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mentor Feedback:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: _isSmallScreen ? 14 : 16,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _feedbackController,
            maxLines: 4,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'Type your feedback here... (Others see in real-time)',
              contentPadding: EdgeInsets.all(_isSmallScreen ? 12 : 16),
            ),
            style: TextStyle(fontSize: _isSmallScreen ? 14 : 16),
          ),
        ],
      );
    } else {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(_isSmallScreen ? 12 : 16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.green.shade400),
          borderRadius: BorderRadius.circular(8),
          color: Colors.green.shade50,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mentor Feedback:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green.shade800,
                fontSize: _isSmallScreen ? 14 : 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _feedbackController.text.isEmpty 
                  ? "No feedback yet from mentor" 
                  : _feedbackController.text,
              style: TextStyle(
                color: Colors.green.shade800,
                fontSize: _isSmallScreen ? 14 : 16,
              ),
            ),
          ],
        ),
      );
    }
  }

  // ✅ FIXED: Better permission badge
  Widget _buildEditPermissionBadge() {
    if (_currentUserId == null) return const SizedBox.shrink();
    
    final isMentor = _currentUserId == _mentorId;
    final isMentee = _currentUserId == _currentSession['mentee_id'];
    final isAllowedViewer = _allowedUsers.contains(_currentUserId);
    
    String badgeText;
    Color badgeColor;
    Color textColor;
    IconData icon;
    
    if (isMentor) {
      badgeText = 'Mentor';
      badgeColor = Colors.green.shade100;
      textColor = Colors.green.shade800;
      icon = Icons.verified;
    } else if (isMentee) {
      badgeText = 'Mentee';
      badgeColor = Colors.blue.shade100;
      textColor = Colors.blue.shade800;
      icon = Icons.verified_user;
    } else if (isAllowedViewer) {
      badgeText = 'Can Edit';
      badgeColor = Colors.orange.shade100;
      textColor = Colors.orange.shade800;
      icon = Icons.edit;
    } else {
      badgeText = 'View Only';
      badgeColor = Colors.grey.shade100;
      textColor = Colors.grey.shade800;
      icon = Icons.visibility;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor,
        border: Border.all(color: textColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 14),
          const SizedBox(width: 6),
          Text(
            badgeText,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _cursorTimer?.cancel();
    _reconnectTimer?.cancel();
    _autoSaveTimer?.cancel();
    _languageChangeTimer?.cancel();
    _feedbackTimer?.cancel();
    _permissionMonitorTimer?.cancel(); 
    _channel?.unsubscribe();
    _codeController.dispose();
    _feedbackController.dispose();
    _codeScrollController.dispose();
    _contentScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Loading session...',
                style: TextStyle(
                  fontSize: _isSmallScreen ? 16 : 18,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'CodeLiveReview - ${widget.roomId}',
          style: TextStyle(fontSize: _isSmallScreen ? 16 : 18),
        ),
        actions: [
          _buildEditPermissionBadge(),
          const SizedBox(width: 8),
          _buildConnectionStatus(),
          const SizedBox(width: 8),
          if (_isMentorCurrentUser()) 
            IconButton(
              icon: const Icon(Icons.manage_accounts),
              onPressed: _showPermissionManager,
              tooltip: 'Manage Edit Permissions',
            ),
          if (_canEdit) ...[
            IconButton(
              icon: _isSaving
                  ? SizedBox(
                      width: _isSmallScreen ? 20 : 24,
                      height: _isSmallScreen ? 20 : 24,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.save, size: _isSmallScreen ? 20 : 24),
              onPressed: _saveCode,
              tooltip: 'Save Code',
            ),
            IconButton(
              icon: _isExecuting
                  ? SizedBox(
                      width: _isSmallScreen ? 20 : 24,
                      height: _isSmallScreen ? 20 : 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(Icons.play_arrow, size: _isSmallScreen ? 20 : 24),
              onPressed: _runCode,
              tooltip: 'Run Code',
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(_isSmallScreen ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLanguageSelector(),
              SizedBox(height: _isSmallScreen ? 12 : 16),
              Expanded(
                child: SingleChildScrollView(
                  controller: _contentScrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCodeEditor(),
                      SizedBox(height: _isSmallScreen ? 12 : 16),
                      _buildOutputPanel(),
                      SizedBox(height: _isSmallScreen ? 12 : 16),
                      _buildFeedbackPanel(),
                      SizedBox(height: _isSmallScreen ? 12 : 16),
                    ],
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