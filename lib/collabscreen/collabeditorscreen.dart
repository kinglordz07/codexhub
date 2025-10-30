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

  int? _otherUserCursor;
  Timer? _typingTimer;
  Timer? _cursorTimer;
  Timer? _reconnectTimer;
  RealtimeChannel? _channel;

  String? _lastLocalCode;

  // Language mapping for execution
  static const Map<String, String> _languageMapping = {
    'python': 'python3',
    'java': 'java',
    'csharp': 'dotnet',
  };

  static const Map<String, String> _defaultSnippets = {
    'python': 'print("Hello, World!")',
    'java': '''
public class Main {
    public static void main(String[] args) {
        System.out.println("Hello, World!");
    }
}
''',
    'csharp': '''
using System;

class Program {
    static void Main() {
        Console.WriteLine("Hello, World!");
    }
}
''',
  };

  bool get _isSmallScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width < 600;
  }

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  void _initializeApp() {
    Future.delayed(Duration.zero, () {
      if (mounted) {
        _initSession();
      }
    });
    _setupConnectivityListener();
  }

  Future<void> _initSession() async {
    if (!mounted) return;
    
    try {
      if (mounted) {
        setState(() => _isLoading = true);
      }
      
      await _loadSession();
      _setupListeners();
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

  void _setupConnectivityListener() {
    _reconnectTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      if (!_isConnected && mounted) {
        _subscribeRealtime();
      }
    });
  }

  Future<void> _loadSession() async {
    try {
      _currentUserId = _supabase.auth.currentUser?.id;

      final session = await _supabase
          .from('live_sessions')
          .select()
          .eq('room_id', widget.roomId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (session != null) {
        _mentorId = session['mentor_id'];
        _selectedLanguage = session['language'] ?? 'python';
        
        _codeController.text = session['code'] ?? _defaultSnippets[_selectedLanguage]!;
        _lastLocalCode = _codeController.text;
        
        _output = session['output'] ?? '';
        _feedbackController.text = session['mentor_feedback'] ?? '';

        _canEdit = widget.isMentor || (!widget.isReadOnly && _currentUserId == session['mentee_id']);
      } else {
        final newSession = await _supabase.from('live_sessions').insert({
          'room_id': widget.roomId,
          'language': _selectedLanguage,
          'code': _defaultSnippets[_selectedLanguage] ?? '',
          'is_live': true,
          'waiting': false,
          'mentor_id': widget.isMentor ? _currentUserId : null,
          'mentee_id': !widget.isMentor ? _currentUserId : null,
        }).select().single();

        _codeController.text = newSession['code'] ?? '';
        _lastLocalCode = _codeController.text;
        _output = newSession['output'] ?? '';
        _canEdit = true && !widget.isReadOnly;
      }
    } catch (e) {
      debugPrint('❌ Error loading session: $e');
      rethrow;
    }
  }

  void _setupListeners() {
    _codeController.addListener(() {
      if (!_canEdit || _isLocalEdit) return;

      _isLocalEdit = true;

      _restartTypingTimer(() async {
        if (_codeController.text != _lastLocalCode) {
          _lastLocalCode = _codeController.text;
          await _updateLiveField('code', _codeController.text);
        }
        _isLocalEdit = false;
      });

      _restartCursorTimer(() async {
        await _updateLiveField(
          widget.isMentor ? 'mentor_cursor' : 'mentee_cursor',
          _codeController.selection.baseOffset,
        );
      });
    });

    _feedbackController.addListener(() {
      if (!_canEdit || !_isMentorCurrentUser()) return;
      _restartTypingTimer(() async {
        await _updateLiveField('mentor_feedback', _feedbackController.text);
      });
    });
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
      
      // Try JDoodle API first (more reliable)
      try {
        result = await _executeCodeWithJDoodle(_codeController.text, _selectedLanguage);
      } catch (e) {
        debugPrint('JDoodle API failed: $e');
        // Fallback to Replit API
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
    
    // Enhanced input handling
    String stdin = '';
    String processedCode = code;
    
    if (language == 'python' && code.contains('input(')) {
      stdin = 'test_user\n'; // Provide default input for Python
    } else if (language == 'csharp' && code.contains('Console.ReadLine()')) {
      stdin = 'test_user\n'; // Provide default input for .NET
    }
    
    // Prepare request data
    final Map<String, dynamic> requestData = {
      'language': pistonLanguage,
      'version': _getLanguageVersion(language),
      'files': [{'name': _getFileName(language), 'content': processedCode}],
      'stdin': stdin,
    };

    // Add args only for languages that need them
    final args = _getExecutionArgs(language);
    if (args.isNotEmpty) {
      requestData['args'] = args;
    }

    try {
      final response = await http.post(
        Uri.parse(replitApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'CodexHub/1.0',
        },
        body: jsonEncode(requestData),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['run'] != null) {
          final run = data['run'];
          
          if (run['stderr'] != null && (run['stderr'] as String).isNotEmpty) {
            return '❌ COMPILATION ERROR:\n${run['stderr']}';
          } else if (run['stdout'] != null) {
            return (run['stdout'] as String).trim();
          } else if (run['output'] != null) {
            return (run['output'] as String).trim();
          } else {
            return '✅ Program executed successfully (no output)';
          }
        } else {
          return '❌ Execution failed: Invalid response format';
        }
      } else if (response.statusCode == 400) {
        return '❌ Bad Request: The code may contain unsupported features';
      } else if (response.statusCode == 429) {
        return '❌ Rate limit exceeded: Please try again in a few moments';
      } else {
        return '❌ API Error (HTTP ${response.statusCode}): ${response.body.length > 100 ? '${response.body.substring(0, 100)}...' : response.body}';
      }
    } catch (e) {
      throw Exception('Replit API connection failed: $e');
    }
  }

  Future<String> _executeCodeWithJDoodle(String code, String language) async {
    const String clientId = '9d262318b31550002aa19e7bd46bfd9a';
    const String clientSecret = '6038b60f28cc7b354a6448c940539ea43d64bc3dce1d635ecebdf17b2a86ac10';
    
    try {
      final response = await http.post(
        Uri.parse('https://api.jdoodle.com/v1/execute'),
        headers: {
          'Content-Type': 'application/json',
          'User-Agent': 'CodexHub/1.0',
        },
        body: jsonEncode({
          'clientId': clientId,
          'clientSecret': clientSecret,
          'script': code,
          'language': _getJDoodleLanguage(language),
          'versionIndex': _getJDoodleVersionIndex(language),
        }),
      ).timeout(const Duration(seconds: 20));

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
      } else if (response.statusCode == 400) {
        return '❌ JDoodle: Invalid request - code may be too long or contain errors';
      } else if (response.statusCode == 429) {
        return '❌ JDoodle: Daily limit reached - please try again tomorrow';
      } else {
        return '❌ JDoodle API Error (HTTP ${response.statusCode})';
      }
    } catch (e) {
      throw Exception('JDoodle API connection failed: $e');
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
    if (language == 'java') {
      return ['Main'];
    }
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
              if (_isLocalEdit && _canEdit) return;
              _handleRemoteUpdate(newData);
            });
          },
        )
        ..onBroadcast(
          event: 'cursor_update',
          callback: (payload) {
            Future.microtask(() {
              if (!mounted) return;
              _handleCursorUpdate(payload);
            });
          },
        )
        ..subscribe((RealtimeSubscribeStatus status, [Object? error]) {
          Future.microtask(() {
            if (!mounted) return;
            if (error != null) {
              setState(() => _isConnected = false);
            } else {
              setState(() => _isConnected = true);
            }
            
            if (status == RealtimeSubscribeStatus.closed) {
              setState(() => _isConnected = false);
              Future.delayed(const Duration(seconds: 5), _subscribeRealtime);
            }
          });
        });

    } catch (e) {
      debugPrint('❌ Error subscribing to realtime: $e');
      if (mounted) {
        setState(() => _isConnected = false);
      }
    }
  }

  void _handleRemoteUpdate(Map<String, dynamic> newData) {
    if (!mounted) return;
    
    setState(() {
      final remoteCode = newData['code'];
      if (remoteCode != null && remoteCode != _codeController.text && remoteCode != _lastLocalCode) {
        _updateCodeControllerSafely(remoteCode as String);
      }
      
      if (newData['mentor_feedback'] != null && newData['mentor_feedback'] != _feedbackController.text) {
        _feedbackController.text = newData['mentor_feedback'] as String;
      }
      
      if (newData['output'] != null && newData['output'] != _output) {
        _output = newData['output'] as String;
      }
      
      if (newData['language'] != null && newData['language'] != _selectedLanguage) {
        _selectedLanguage = newData['language'] as String;
      }
    });
  }

  void _updateCodeControllerSafely(String remoteCode) {
    final cursorOffset = _codeController.selection.baseOffset;
    final scrollOffset = _codeScrollController.offset;
    _codeController.value = TextEditingValue(
      text: remoteCode,
      selection: TextSelection.collapsed(
        offset: cursorOffset.clamp(0, remoteCode.length).toInt(),
      ),
    );
    _lastLocalCode = remoteCode;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_codeScrollController.hasClients) {
        _codeScrollController.jumpTo(scrollOffset);
      }
    });
  }

  void _handleCursorUpdate(Map<String, dynamic> payload) {
    final otherCursorField = (_currentUserId == _mentorId) ? 'mentee_cursor' : 'mentor_cursor';
    if (payload[otherCursorField] != null) {
      if (mounted) {
        setState(() {
          _otherUserCursor = payload[otherCursorField];
        });
      }
    }
  }

  Future<void> _updateLiveField(String field, dynamic value) async {
    try {
      await _supabase.from('live_sessions').update({
        field: value,
        'last_editor': _currentUserId,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('room_id', widget.roomId);
    } catch (e) {
      debugPrint('⚠️ Error updating $field: $e');
    }
  }

  bool _isMentorCurrentUser() => _currentUserId == _mentorId;

  void _restartTypingTimer(VoidCallback callback) {
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 600), callback);
  }

  void _restartCursorTimer(VoidCallback callback) {
    _cursorTimer?.cancel();
    _cursorTimer = Timer(const Duration(milliseconds: 300), callback);
  }

  Future<void> _saveCode() async {
    if (_isSaving || !_canEdit) return;
    
    if (mounted) {
      setState(() => _isSaving = true);
    }
    
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
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _safeShowSuccessSnackBar(String message) {
    Future.microtask(() {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(_isSmallScreen ? 8 : 16),
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
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(_isSmallScreen ? 8 : 16),
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
            _isConnected ? 'Connected' : 'Reconnecting...',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
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
      onChanged: _canEdit ? (v) {
        if (v != null && v != _selectedLanguage) {
          setState(() {
            _selectedLanguage = v;
            _codeController.text = _defaultSnippets[v] ?? '';
            _lastLocalCode = _codeController.text;
          });
          _updateLiveField('language', v);
        }
      } : null,
    );
  }

  Widget _buildCodeEditor() {
    const double charWidth = 8;
    const double lineHeight = 20;
    const int charsPerLine = 80;

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
            readOnly: !_canEdit,
            scrollController: _codeScrollController,
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(_isSmallScreen ? 8 : 12),
              hintText: _canEdit ? 'Start coding...' : 'Read-only mode',
            ),
            style: TextStyle(
              fontFamily: 'RobotoMono',
              fontSize: _isSmallScreen ? 13 : 14,
              color: _canEdit ? Colors.black : Colors.grey.shade600,
            ),
          ),
          if (_otherUserCursor != null && _otherUserCursor! <= _codeController.text.length)
            Positioned(
              left: (_otherUserCursor! % charsPerLine) * charWidth,
              top: (_otherUserCursor! ~/ charsPerLine) * lineHeight,
              child: Container(
                width: 2,
                height: lineHeight,
                color: const Color.fromRGBO(255, 0, 0, 0.7),
              ),
            ),
          if (!_canEdit)
            Positioned.fill(
              child: Container(
                color: const Color(0xFF000000).withValues(alpha: 0.1), 
                child: Center(
                  child: Text(
                    'Read Only',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
              hintText: 'Type your feedback here...',
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

  @override
  void dispose() {
    _typingTimer?.cancel();
    _cursorTimer?.cancel();
    _reconnectTimer?.cancel();
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
          _buildConnectionStatus(),
          const SizedBox(width: 8),
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
                  : Icon(
                      Icons.save,
                      size: _isSmallScreen ? 20 : 24,
                    ),
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
                  : Icon(
                      Icons.play_arrow,
                      size: _isSmallScreen ? 20 : 24,
                    ),
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