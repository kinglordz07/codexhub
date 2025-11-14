import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;

class SavedSessionsScreen extends StatelessWidget {
  const SavedSessionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final bool isSmallScreen = MediaQuery.of(context).size.width < 600;
    final bool isVerySmallScreen = MediaQuery.of(context).size.width < 400;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Saved Sessions'),
        backgroundColor: Colors.blue.shade700,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadAllSessions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
                child: Text(
                  'Error loading sessions: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
                ),
              ),
            );
          }
          
          final sessions = snapshot.data ?? [];
          
          if (sessions.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(isSmallScreen ? 20 : 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.code_off, 
                      size: isVerySmallScreen ? 48 : isSmallScreen ? 64 : 80, 
                      color: Colors.grey
                    ),
                    SizedBox(height: isSmallScreen ? 16 : 24),
                    Text(
                      'No saved sessions yet',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 16 : 20,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 8 : 12),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 20 : 40),
                      child: Text(
                        'Save your code sessions to see them here!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: isSmallScreen ? 12 : 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          
          return ListView.builder(
            padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
            itemCount: sessions.length,
            itemBuilder: (context, index) {
              final session = sessions[index];
              final roomId = session['room_id'] ?? 'Unknown Room';
              final language = session['language'] ?? 'python';
              final code = session['code'] ?? '';
              final savedAt = session['saved_at'] ?? '';
              final codeLength = code.length;
              
              return Card(
                margin: EdgeInsets.only(bottom: isSmallScreen ? 8 : 12),
                child: ListTile(
                  leading: Container(
                    width: isVerySmallScreen ? 40 : isSmallScreen ? 45 : 50,
                    height: isVerySmallScreen ? 40 : isSmallScreen ? 45 : 50,
                    decoration: BoxDecoration(
                      color: _getLanguageColor(language),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        _getLanguageIcon(language),
                        style: TextStyle(
                          fontSize: isVerySmallScreen ? 14 : isSmallScreen ? 16 : 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    'Room: $roomId',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isSmallScreen ? 14 : 16,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Language: ${_getLanguageName(language)}',
                        style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                      ),
                      Text(
                        'Code: $codeLength characters',
                        style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                      ),
                      if (savedAt.isNotEmpty) 
                        Text(
                          'Saved: ${_formatDate(savedAt)}', 
                          style: TextStyle(
                            fontSize: isSmallScreen ? 10 : 12, 
                            color: Colors.grey
                          ),
                        ),
                    ],
                  ),
                  trailing: Icon(
                    Icons.arrow_forward_ios, 
                    size: isSmallScreen ? 14 : 16
                  ),
                  onTap: () {
                    Navigator.pushReplacement(context, MaterialPageRoute(
                      builder: (context) => CollabCodeEditorScreen(
                        roomId: roomId,
                        isMentor: true,
                        isReadOnly: false,
                      ),
                    ));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadAllSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final allKeys = prefs.getKeys().where((key) => key.startsWith('session_')).toList();
      
      List<Map<String, dynamic>> sessions = [];
      for (final key in allKeys) {
        final sessionData = prefs.getString(key);
        if (sessionData != null) {
          try {
            sessions.add(json.decode(sessionData) as Map<String, dynamic>);
          } catch (e) {
            debugPrint('Error decoding session $key: $e');
          }
        }
      }
      
      sessions.sort((a, b) {
        final aTime = a['last_saved'] ?? 0;
        final bTime = b['last_saved'] ?? 0;
        return bTime.compareTo(aTime);
      });
      
      return sessions;
    } catch (e) {
      debugPrint('Error loading sessions: $e');
      return [];
    }
  }

  String _getLanguageIcon(String language) {
    switch (language) {
      case 'python': return 'Py';
      case 'java': return 'Jv';
      case 'csharp': return 'C#';
      default: return 'Code';
    }
  }

  String _getLanguageName(String language) {
    switch (language) {
      case 'python': return 'Python';
      case 'java': return 'Java';
      case 'csharp': return 'C#';
      default: return language;
    }
  }

  Color _getLanguageColor(String language) {
    switch (language) {
      case 'python': return Colors.blue.shade600;
      case 'java': return Colors.orange.shade600;
      case 'csharp': return Colors.purple.shade600;
      default: return Colors.grey.shade600;
    }
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return '${date.month}/${date.day}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown date';
    }
  }
}

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

  String get _sessionStorageKey => 'session_${widget.roomId}';

  List<String> _allowedUsers = [];
  List<Map<String, dynamic>> _roomMembers = [];
  Map<String, dynamic> _currentSession = {};

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

  final Map<String, String> _languageMapping = {
    'python': 'python3',
    'java': 'java',
    'csharp': 'dotnet',
  };

  bool get _isSmallScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width < 600;
  }

  bool get _isVerySmallScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width < 400;
  }

  double get _codeEditorHeight {
    final mediaQuery = MediaQuery.of(context);
    if (mediaQuery.size.width < 400) {
      return 200; 
    } else if (mediaQuery.size.width < 600) {
      return 250; 
    } else {
      return 350;
    }
  }

  double get _paddingSize {
    return _isVerySmallScreen ? 8 : _isSmallScreen ? 12 : 16;
  }

  double get _fontSize {
    return _isVerySmallScreen ? 12 : _isSmallScreen ? 13 : 14;
  }

  double get _iconSize {
    return _isVerySmallScreen ? 18 : _isSmallScreen ? 20 : 24;
  }

  @override
  void initState() {
    super.initState();
    _initializeApp();
    _setupPermissionMonitoring();
  }

  void _initializeApp() {
    Future.delayed(Duration.zero, () {
      if (mounted) {
        _initSession();
      }
    });
    _setupConnectivityListener();
  }

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

  Future<void> _loadSession() async {
    try {
      _currentUserId = _supabase.auth.currentUser?.id;
      debugPrint('👤 Loading session for user: $_currentUserId');

      final localSession = await _loadSessionFromLocalStorage();
      
      if (localSession != null) {
        debugPrint('📋 Session Loaded FROM LOCAL STORAGE:');
        _selectedLanguage = localSession['language'] ?? 'python';
        _codeController.text = localSession['code'] ?? _defaultSnippets[_selectedLanguage]!;
        _lastLocalCode = _codeController.text;
        _output = localSession['output'] ?? '';
        _feedbackController.text = localSession['mentor_feedback'] ?? '';
        _lastLocalFeedback = _feedbackController.text;
        
        _safeShowSuccessSnackBar('📁 Loaded from local storage');
      } else {
        debugPrint('🔄 No local session found, loading from Supabase...');
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
          
          debugPrint('📋 Session Loaded FROM SUPABASE:');
          debugPrint('  - Mentor: $_mentorId');
          debugPrint('  - Language: $_selectedLanguage');
          
          _codeController.text = session['code'] ?? _defaultSnippets[_selectedLanguage]!;
          _lastLocalCode = _codeController.text;
          _output = session['output'] ?? '';
          _feedbackController.text = session['mentor_feedback'] ?? '';
          _lastLocalFeedback = _feedbackController.text;
        } else {
          debugPrint('🆕 Creating new session...');
          _codeController.text = _defaultSnippets[_selectedLanguage]!;
          _lastLocalCode = _codeController.text;
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading session: $e');
      _codeController.text = _defaultSnippets[_selectedLanguage]!;
      _lastLocalCode = _codeController.text;
    }
  }

  Future<Map<String, dynamic>?> _loadSessionFromLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionData = prefs.getString(_sessionStorageKey);
      
      if (sessionData != null) {
        debugPrint('💾 Found local session data');
        return json.decode(sessionData) as Map<String, dynamic>;
      }
      
      debugPrint('📭 No local session data found');
      return null;
    } catch (e) {
      debugPrint('❌ Error loading local session: $e');
      return null;
    }
  }

  Future<void> _loadPermissionsAndMembers() async {
    try {
      debugPrint('🔄 Loading permissions and members...');
      
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

      _updateEditPermission();

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
      _updateEditPermission();
    }
  }

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
    
    if (sessionMentorId != null && _currentUserId == sessionMentorId) {
      debugPrint('  ✅ User is MENTOR - Can edit');
      return true;
    }
    
    if (sessionMenteeId != null && _currentUserId == sessionMenteeId) {
      debugPrint('  ✅ User is MENTEE - Can edit');
      return true;
    }
    
    final isAllowedViewer = _allowedUsers.contains(_currentUserId);
    debugPrint('  ${isAllowedViewer ? '✅' : '❌'} User is ${isAllowedViewer ? 'ALLOWED VIEWER' : 'RESTRICTED VIEWER'}');
    
    return isAllowedViewer;
  }

  void _setupListeners() {
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

      _restartCursorTimer(() async {
        await _updateLiveField(
          _isMentorCurrentUser() ? 'mentor_cursor' : 'mentee_cursor',
          _codeController.selection.baseOffset,
        );
      });
    });

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

  void _restartFeedbackTimer(VoidCallback callback) {
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 500), callback);
  }

  void _showPermissionManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: EdgeInsets.all(_paddingSize),
              child: Column(
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Manage Edit Access',
                        style: TextStyle(
                          fontSize: _isSmallScreen ? 18 : 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Content
                  Expanded(
                    child: _roomMembers.isEmpty
                        ? Center(
                            child: Text(
                              'No members in this room',
                              style: TextStyle(
                                fontSize: _isSmallScreen ? 14 : 16,
                                color: Colors.grey,
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              // Legend
                              Container(
                                padding: EdgeInsets.all(_paddingSize),
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
                              
                              // Members List
                              Expanded(
                                child: ListView.builder(
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
                                    
                                    // Don't show current user or mentors
                                    if (isCurrentUser || isMentorUser) {
                                      return const SizedBox.shrink();
                                    }

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
                                          radius: _isVerySmallScreen ? 16 : 20,
                                          child: Text(
                                            username.isNotEmpty ? username[0].toUpperCase() : '?',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: _isVerySmallScreen ? 12 : 14,
                                            ),
                                          ),
                                        ),
                                        title: Text(
                                          username,
                                          style: TextStyle(
                                            fontSize: _isSmallScreen ? 14 : 16,
                                          ),
                                        ),
                                        subtitle: Text(
                                          displayRole,
                                          style: TextStyle(
                                            color: roleColor,
                                            fontWeight: FontWeight.w500,
                                            fontSize: _isSmallScreen ? 12 : 14,
                                          ),
                                        ),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Mentees: Always can edit, no toggle
                                            if (isMenteeUser)
                                              Icon(
                                                Icons.verified,
                                                color: Colors.blue,
                                                size: _iconSize,
                                              )
                                            // Viewers: Show toggle
                                            else if (!isMenteeUser)
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (isAllowed)
                                                    Icon(
                                                      Icons.check_circle,
                                                      color: Colors.green,
                                                      size: _iconSize,
                                                    )
                                                  else
                                                    Icon(
                                                      Icons.remove_circle,
                                                      color: Colors.red,
                                                      size: _iconSize,
                                                    ),
                                                  SizedBox(width: _isVerySmallScreen ? 4 : 8),
                                                  isAllowed
                                                      ? IconButton(
                                                          icon: Icon(Icons.person_remove, 
                                                              color: Colors.red,
                                                              size: _iconSize),
                                                          onPressed: () async {
                                                            await _removeUserFromCodeReview(memberUserId);
                                                            setDialogState(() {});
                                                          },
                                                        )
                                                      : IconButton(
                                                          icon: Icon(Icons.person_add, 
                                                              color: Colors.green,
                                                              size: _iconSize),
                                                          onPressed: () async {
                                                            await _allowUserInCodeReview(memberUserId);
                                                            setDialogState(() {});
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
                ],
              ),
            );
          },
        );
      },
    );
  }

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
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: _isSmallScreen ? 12 : 14,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: _isSmallScreen ? 10 : 12,
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

  Future<void> _allowUserInCodeReview(String userId) async {
    if (!_isMentorCurrentUser()) {
      _safeShowErrorSnackBar('Only mentors can manage code review permissions.');
      return;
    }

    try {
      final response = await _supabase.from('code_review_permissions').insert({
        'room_id': widget.roomId,
        'user_id': userId,
        'allowed_by': _currentUserId,
        'granted_at': DateTime.now().toUtc().toIso8601String(),
      }).select().single().timeout(const Duration(seconds: 15));

      debugPrint('✅ Insert successful: $response');
      _safeShowSuccessSnackBar('✅ User allowed in code review');
      
      await _loadPermissionsAndMembers();
      _updateEditPermission();
      
    } catch (e) {
      debugPrint('❌ Error allowing user: $e');
      if (e.toString().contains('duplicate key')) {
        _safeShowErrorSnackBar('User already has edit access');
        await _loadPermissionsAndMembers();
      } else {
        _safeShowErrorSnackBar('Failed to allow user in code review');
      }
    }
  }

  Future<void> _removeUserFromCodeReview(String userId) async {
    if (!_isMentorCurrentUser()) {
      _safeShowErrorSnackBar('Only mentors can manage code review permissions.');
      return;
    }

    try {
      final response = await _supabase
          .from('code_review_permissions')
          .delete()
          .eq('room_id', widget.roomId)
          .eq('user_id', userId)
          .timeout(const Duration(seconds: 15));

      debugPrint('✅ Delete successful: $response');
      _safeShowSuccessSnackBar('👋 User removed from code review');
      
      await _loadPermissionsAndMembers();
      _updateEditPermission();
      
    } catch (e) {
      debugPrint('❌ Error removing user: $e');
      _safeShowErrorSnackBar('Failed to remove user from code review');
    }
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
              
              if (_isLocalEdit && newData['last_editor'] == _currentUserId) {
                debugPrint('🔄 Ignoring own update');
                return;
              }
              
              _handleRemoteUpdate(newData);
            });
          },
        )
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
              _loadPermissionsAndMembers();
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
     if (!mounted || _isChangingLanguage) return;
    
    debugPrint('🔄 HANDLING REMOTE UPDATE:');
    debugPrint('  - _isLocalEdit: $_isLocalEdit');
    debugPrint('  - _canEdit: $_canEdit');
    debugPrint('  - Remote data keys: ${newData.keys}');
    
    setState(() {
      final remoteCode = newData['code'];
      if (remoteCode != null && remoteCode != _codeController.text && remoteCode != _lastLocalCode) {
        debugPrint('👀 Applying code update from others');
        _updateCodeControllerSafely(remoteCode as String);
      } else {
        debugPrint('⏭️  Skipping code update (same content or local edit)');
      }
      
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

  bool _isMentorCurrentUser() {
    if (_currentUserId == null || _mentorId == null) {
      debugPrint('❌ Mentor Check Failed: currentUserId=$_currentUserId, mentorId=$_mentorId');
      return false;
    }
    
    final isMentor = _currentUserId == _mentorId;
    debugPrint('👨‍🏫 MENTOR CHECK: $isMentor (Current: $_currentUserId, Mentor: $_mentorId)');
    return isMentor;
  }

  void _restartTypingTimer(VoidCallback callback) {
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 800), callback);
  }

  void _restartCursorTimer(VoidCallback callback) {
    _cursorTimer?.cancel();
    _cursorTimer = Timer(const Duration(milliseconds: 500), callback);
  }

  bool _isChangingLanguage = false; 

void _onLanguageChanged(String? newLanguage) {
  if (newLanguage == null || newLanguage == _selectedLanguage || !_canEdit) return;
  
  _languageChangeTimer?.cancel();
  _languageChangeTimer = Timer(const Duration(milliseconds: 500), () async {
    if (!mounted) return;
    
    _isChangingLanguage = true;
    
    final currentCode = _codeController.text;
    
    if (mounted) {
      setState(() {
        _selectedLanguage = newLanguage;
        
        if (currentCode.trim().isEmpty) {
          _codeController.text = _defaultSnippets[newLanguage] ?? '';
          _lastLocalCode = _codeController.text;
        }
      });
      
      await _updateLiveField('language', newLanguage);
      
      Future.delayed(const Duration(seconds: 3), () {
        _isChangingLanguage = false;
      });
    }
  });
}

  Future<void> _saveCode() async {
    if (_isSaving || !_canEdit) return;
    
    if (mounted) setState(() => _isSaving = true);
    
    try {

      await _saveSessionToLocalStorage();
      
      _safeShowSuccessSnackBar('💾 Code saved LOCALLY!');
      debugPrint('💾 LOCAL SAVE: Session ${widget.roomId} saved to device storage');
      
    } catch (e) {
      debugPrint('❌ Error saving code locally: $e');
      _safeShowErrorSnackBar('Failed to save locally');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveSessionToLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final sessionData = {
        'room_id': widget.roomId,
        'code': _codeController.text,
        'language': _selectedLanguage,
        'output': _output,
        'mentor_feedback': _feedbackController.text,
        'last_editor': _currentUserId,
        'saved_at': DateTime.now().toIso8601String(),
        'last_saved': DateTime.now().millisecondsSinceEpoch,
      };
      
      await prefs.setString(_sessionStorageKey, json.encode(sessionData));
      _lastLocalCode = _codeController.text;
      _lastLocalFeedback = _feedbackController.text;
      
      debugPrint('💾 LOCAL SAVE COMPLETE:');
      debugPrint('  - Key: $_sessionStorageKey');
      debugPrint('  - Code length: ${_codeController.text.length}');
      debugPrint('  - Language: $_selectedLanguage');
      debugPrint('  - Physical location: SharedPreferences');
      
    } catch (e) {
      debugPrint('❌ Error in _saveSessionToLocalStorage: $e');
      rethrow;
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
      padding: EdgeInsets.symmetric(
        horizontal: _isVerySmallScreen ? 8 : 12, 
        vertical: _isVerySmallScreen ? 4 : 6
      ),
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
            size: _isVerySmallScreen ? 10 : 12,
          ),
          SizedBox(width: _isVerySmallScreen ? 4 : 6),
          Text(
            _isConnected ? 'Live' : 'Offline',
            style: TextStyle(
              color: Colors.white,
              fontSize: _isVerySmallScreen ? 10 : 12,
              fontWeight: FontWeight.w500,
            ),
          ),
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
        horizontal: _isVerySmallScreen ? 8 : 12,
        vertical: _isVerySmallScreen ? 12 : 14,
      ),
      labelText: 'Language',
      labelStyle: TextStyle(
        fontSize: _isSmallScreen ? 14 : 16,
        color: Colors.black87, 
      ),
      filled: true,
      fillColor: Colors.grey.shade50, 
    ),
    items: const [
      DropdownMenuItem(
        value: 'python',
        child: Text(
          'Python',
          style: TextStyle(color: Colors.black), 
        ),
      ),
      DropdownMenuItem(
        value: 'java',
        child: Text(
          'Java', 
          style: TextStyle(color: Colors.black), 
        ),
      ),
      DropdownMenuItem(
        value: 'csharp',
        child: Text(
          'C#',
          style: TextStyle(color: Colors.black), 
        ),
      ),
    ],
    onChanged: _canEdit ? _onLanguageChanged : null,
    style: TextStyle(
      fontSize: _isSmallScreen ? 14 : 16,
      color: Colors.black, 
    ),
    dropdownColor: Colors.white, 
    icon: Icon(
      Icons.arrow_drop_down,
      color: Colors.black, 
    ),
  );
}

  Widget _buildCodeEditor() {
    return Container(
      height: _codeEditorHeight,
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
            readOnly: !_canEdit,
            scrollController: _codeScrollController,
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(_isVerySmallScreen ? 6 : 8),
              hintText: _canEdit ? 'Start coding...' : 'View-only mode - You can see real-time changes',
              hintStyle: TextStyle(fontSize: _fontSize),
            ),
            style: TextStyle(
              fontFamily: 'RobotoMono',
              fontSize: _fontSize,
              color: _canEdit ? Colors.black : Colors.grey.shade700,
            ),
          ),
          if (!_canEdit)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: _isVerySmallScreen ? 8 : 12, 
                  vertical: _isVerySmallScreen ? 4 : 6
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  border: Border.all(color: Colors.blue),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.visibility, 
                        color: Colors.blue, 
                        size: _isVerySmallScreen ? 12 : 14),
                    SizedBox(width: _isVerySmallScreen ? 2 : 4),
                    Text(
                      'View Only',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: _isVerySmallScreen ? 10 : 12,
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
      padding: EdgeInsets.all(_isVerySmallScreen ? 8 : 12),
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
                SizedBox(width: _isVerySmallScreen ? 4 : 8),
                SizedBox(
                  width: _isVerySmallScreen ? 14 : 16,
                  height: _isVerySmallScreen ? 14 : 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: _isVerySmallScreen ? 4 : 8),
          Expanded(
            child: SingleChildScrollView(
              child: Text(
                _output.isEmpty ? 'No output yet' : _output,
                style: TextStyle(
                  fontSize: _fontSize,
                  fontFamily: 'RobotoMono',
                  color: _output.isEmpty ? Colors.grey : Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ✅ NEW: Mobile-optimized feedback panel
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
          SizedBox(height: _isVerySmallScreen ? 4 : 8),
          TextField(
            controller: _feedbackController,
            maxLines: 3,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'Type your feedback here...',
              contentPadding: EdgeInsets.all(_isVerySmallScreen ? 8 : 12),
            ),
            style: TextStyle(fontSize: _isSmallScreen ? 14 : 16),
          ),
        ],
      );
    } else {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(_isVerySmallScreen ? 8 : 12),
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
            SizedBox(height: _isVerySmallScreen ? 4 : 8),
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

  // ✅ NEW: Mobile-optimized permission badge
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
      padding: EdgeInsets.symmetric(
        horizontal: _isVerySmallScreen ? 8 : 12, 
        vertical: _isVerySmallScreen ? 4 : 6
      ),
      decoration: BoxDecoration(
        color: badgeColor,
        border: Border.all(color: textColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: _isVerySmallScreen ? 12 : 14),
          SizedBox(width: _isVerySmallScreen ? 4 : 6),
          Text(
            badgeText,
            style: TextStyle(
              color: textColor,
              fontSize: _isVerySmallScreen ? 10 : 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ✅ NEW: Mobile-optimized app bar actions
  List<Widget> _buildAppBarActions() {
    final actions = <Widget>[];

    // Saved Sessions Button
    actions.add(
      IconButton(
        icon: Icon(Icons.history, size: _iconSize),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (context) => const SavedSessionsScreen(),
          ));
        },
        tooltip: 'Saved Sessions',
      ),
    );

    // Permission Badge
    actions.add(_buildEditPermissionBadge());
    actions.add(SizedBox(width: _isVerySmallScreen ? 4 : 8));

    // Connection Status
    actions.add(_buildConnectionStatus());
    actions.add(SizedBox(width: _isVerySmallScreen ? 4 : 8));

    // Permission Manager (Mentors only)
    if (_isMentorCurrentUser()) {
      actions.add(
        IconButton(
          icon: Icon(Icons.manage_accounts, size: _iconSize),
          onPressed: _showPermissionManager,
          tooltip: 'Manage Edit Permissions',
        ),
      );
    }

    // Save Button (Editors only)
    if (_canEdit) {
      actions.add(
        IconButton(
          icon: _isSaving
              ? SizedBox(
                  width: _iconSize,
                  height: _iconSize,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(Icons.save, size: _iconSize),
          onPressed: _saveCode,
          tooltip: 'Save Code',
        ),
      );

      // Run Button
      actions.add(
        IconButton(
          icon: _isExecuting
              ? SizedBox(
                  width: _iconSize,
                  height: _iconSize,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Icon(Icons.play_arrow, size: _iconSize),
          onPressed: _runCode,
          tooltip: 'Run Code',
        ),
      );
    }

    return actions;
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
              SizedBox(height: _isVerySmallScreen ? 12 : 16),
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
          'CodeLive - ${widget.roomId}',
          style: TextStyle(
            fontSize: _isVerySmallScreen ? 14 : _isSmallScreen ? 16 : 18,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: _buildAppBarActions(),
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(_paddingSize),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLanguageSelector(),
              SizedBox(height: _paddingSize),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      controller: _contentScrollController,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildCodeEditor(),
                            SizedBox(height: _paddingSize),
                            SizedBox(
                              height: _isVerySmallScreen ? 120 : 150,
                              child: _buildOutputPanel(),
                            ),
                            SizedBox(height: _paddingSize),
                            _buildFeedbackPanel(),
                            SizedBox(height: _paddingSize),
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
      ),
    );
  }
}