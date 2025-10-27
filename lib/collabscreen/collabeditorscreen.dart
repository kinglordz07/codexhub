import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _feedbackController = TextEditingController();
  final ScrollController _codeScrollController = ScrollController();

  bool isSaving = false;
  bool isLoading = true;
  bool canEdit = false;
  bool _isLocalEdit = false;

  String selectedLanguage = 'python';
  String output = '';
  String? _mentorId;
  String? _menteeId;
  String? _currentUserId;

  int? _otherUserCursor;
  Timer? _typingTimer;
  Timer? _cursorTimer;
  RealtimeChannel? _channel;

  String? _lastLocalCode;

  final Map<String, String> defaultSnippets = {
    'python': 'print("Hello, World!")',
    'vbnet': '''
Module Module1
  Sub Main()
    Console.WriteLine("Hello, World!")
  End Sub
End Module
''',
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
    _initSession();
  }

  Future<void> _initSession() async {
    await _loadSession();
    _setupListeners();
    _subscribeRealtime();
  }

  Future<void> _loadSession() async {
    try {
      _currentUserId = supabase.auth.currentUser?.id;

      final session = await supabase
          .from('live_sessions')
          .select()
          .eq('room_id', widget.roomId)
          .maybeSingle();

      if (session != null) {
        _mentorId = session['mentor_id'];
        _menteeId = session['mentee_id'];
        selectedLanguage = session['language'] ?? 'python';

        _codeController.text =
            session['code'] ?? defaultSnippets[selectedLanguage]!;
        _lastLocalCode = _codeController.text;

        output = session['output'] ?? '';
        _feedbackController.text = session['mentor_feedback'] ?? '';

        canEdit = (_currentUserId == _mentorId || _currentUserId == _menteeId);
      } else {
        final newSession = await supabase.from('live_sessions').insert({
          'room_id': widget.roomId,
          'language': selectedLanguage,
          'code': defaultSnippets[selectedLanguage] ?? '',
          'is_live': true,
          'waiting': false,
        }).select().maybeSingle();

        _codeController.text = newSession?['code'] ?? '';
        _lastLocalCode = _codeController.text;

        output = newSession?['output'] ?? '';
        canEdit = true;
      }
    } catch (e) {
      debugPrint('❌ Error loading session: $e');
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _setupListeners() {
    _codeController.addListener(() {
      if (!canEdit) return;
      _isLocalEdit = true;

      _restartTypingTimer(() async {
        _lastLocalCode = _codeController.text;
        await _updateLiveField('code', _codeController.text);
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
      if (!canEdit || !_isMentorCurrentUser()) return;
      _restartTypingTimer(() async {
        await _updateLiveField('mentor_feedback', _feedbackController.text);
      });
    });
  }

  void _subscribeRealtime() {
    final channelName = 'live_sessions:${widget.roomId}';

    _channel = supabase.channel(channelName)
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
          if (!mounted) return;
          final newData = payload.newRecord;
          if (newData.isEmpty) return;

          // Viewer-only updates
          if (_isLocalEdit && canEdit) return;

          setState(() {
            // Smooth code update
            final remoteCode = newData['code'];
            if (remoteCode != null &&
                remoteCode != _codeController.text &&
                remoteCode != _lastLocalCode) {
              final cursorOffset = _codeController.selection.baseOffset;
              final scrollOffset = _codeScrollController.offset;

              _codeController.value = TextEditingValue(
                text: remoteCode,
                selection: TextSelection.collapsed(
                  offset: cursorOffset.clamp(0, remoteCode.length).toInt(),
                ),
              );

              _lastLocalCode = remoteCode;

              if (_codeScrollController.hasClients) {
                _codeScrollController.jumpTo(scrollOffset);
              }
            }

            if (newData['mentor_feedback'] != null &&
                newData['mentor_feedback'] != _feedbackController.text) {
              _feedbackController.text = newData['mentor_feedback'];
            }

            final otherCursorField = (_currentUserId == _mentorId)
                ? 'mentee_cursor'
                : 'mentor_cursor';
            _otherUserCursor = newData[otherCursorField];

            output = newData['output'] ?? output;
          });
        },
      )
      ..subscribe((RealtimeSubscribeStatus status, [Object? error]) {
        debugPrint('🔔 Channel $channelName → $status');
        if (error != null) debugPrint('⚠️ Channel error: $error');

        if (status == RealtimeSubscribeStatus.closed) {
          Future.delayed(const Duration(seconds: 2), _subscribeRealtime);
        }
      });

    debugPrint('✅ Subscribed to live room: ${widget.roomId}');
  }

  Future<void> _updateLiveField(String field, dynamic value) async {
    try {
      await supabase.from('live_sessions').update({
        field: value,
        'last_editor': _currentUserId,
      }).eq('room_id', widget.roomId);
    } catch (e) {
      debugPrint('⚠️ Error updating $field: $e');
    }
  }

  bool _isMentorCurrentUser() => _currentUserId == _mentorId;

  void _restartTypingTimer(VoidCallback callback) {
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 400), callback);
  }

  void _restartCursorTimer(VoidCallback callback) {
    _cursorTimer?.cancel();
    _cursorTimer = Timer(const Duration(milliseconds: 150), callback);
  }

  Future<void> _saveCode() async {
    if (isSaving || !canEdit) return;
    setState(() => isSaving = true);

    try {
      await supabase.from('live_sessions').update({
        'code': _codeController.text,
        'language': selectedLanguage,
        'output': output,
        'mentor_feedback': _feedbackController.text,
        'last_editor': _currentUserId,
      }).eq('room_id', widget.roomId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('💾 Code saved!'),
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(isSmallScreen ? 8 : 16),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error saving code: $e');
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  Future<void> _runCode() async {
    if (!canEdit) return;
    setState(() => output = 'Running code...');
    await Future.delayed(const Duration(milliseconds: 500));
    final result =
        _getFakeExecutionResult(_codeController.text, selectedLanguage);
    setState(() => output = result);
    await _updateLiveField('output', result);
  }

  String _getFakeExecutionResult(String code, String language) {
    final regexes = {
      'python': RegExp(r'print\s*\((.*?)\)', dotAll: true),
      'java': RegExp(r'System\.out\.println\s*\((.*?)\)\s*;', dotAll: true),
      'csharp': RegExp(r'Console\.WriteLine\s*\((.*?)\)\s*;', dotAll: true),
      'vbnet': RegExp(r'Console\.WriteLine\s*\((.*?)\)', dotAll: true),
    };

    final matches = regexes[language]?.allMatches(code) ?? [];
    final results = matches.map((m) {
      var text = m.group(1) ?? '';
      if (text.startsWith('"') || text.startsWith("'")) {
        text = text.substring(1, text.length - 1);
      }
      return text;
    }).toList();

    return results.isEmpty ? '⚠️ Nothing to execute.' : results.join('\n');
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _cursorTimer?.cancel();
    _channel?.unsubscribe();
    _codeController.dispose();
    _feedbackController.dispose();
    _codeScrollController.dispose();
    super.dispose();
  }

  Widget _buildLanguageSelector() {
    return DropdownButtonFormField<String>(
      initialValue: selectedLanguage,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(
          horizontal: isSmallScreen ? 12 : 16,
          vertical: isSmallScreen ? 14 : 16,
        ),
      ),
      items: const [
        DropdownMenuItem(value: 'python', child: Text('Python')),
        DropdownMenuItem(value: 'vbnet', child: Text('VB.NET')),
        DropdownMenuItem(value: 'java', child: Text('Java')),
        DropdownMenuItem(value: 'csharp', child: Text('C#')),
      ],
      onChanged: canEdit
          ? (v) {
              if (v != null) {
                setState(() {
                  selectedLanguage = v;
                  _codeController.text = defaultSnippets[v] ?? '';
                  _lastLocalCode = _codeController.text;
                });
              }
            }
          : null,
    );
  }

  Widget _buildCodeEditor() {
    const double charWidth = 8;
    const double lineHeight = 20;
    const int charsPerLine = 80;

    return Container(
      height: isSmallScreen ? 250 : 300,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          TextField(
            controller: _codeController,
            maxLines: null,
            expands: true,
            readOnly: !canEdit,
            decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(isSmallScreen ? 8 : 12),
            ),
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: isSmallScreen ? 13 : 14,
            ),
          ),
          if (_otherUserCursor != null &&
              _otherUserCursor! <= _codeController.text.length)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 100),
              left: (_otherUserCursor! % charsPerLine) * charWidth,
              top: (_otherUserCursor! ~/ charsPerLine) * lineHeight,
              child: Container(
                width: 2,
                height: lineHeight,
                color: Colors.red,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOutputPanel() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.shade50,
      ),
      child: Text(
        'Output:\n$output',
        style: TextStyle(
          fontSize: isSmallScreen ? 14 : 16,
          fontFamily: 'monospace',
        ),
      ),
    );
  }

  Widget _buildFeedbackPanel() {
    if (_isMentorCurrentUser()) {
      return TextField(
        controller: _feedbackController,
        maxLines: 4,
        decoration: InputDecoration(
          border: const OutlineInputBorder(),
          hintText: 'Type mentor feedback here...',
          contentPadding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        ),
        style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
      );
    } else {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.green),
          borderRadius: BorderRadius.circular(8),
          color: Colors.green.withAlpha(20),
        ),
        child: Text(
          'Mentor Feedback:\n${_feedbackController.text.isEmpty ? "No feedback yet" : _feedbackController.text}',
          style: TextStyle(
            color: Colors.green.shade800,
            fontSize: isSmallScreen ? 14 : 16,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'CodeLiveReview',
          style: TextStyle(fontSize: isSmallScreen ? 18 : 20),
        ),
        actions: [
          if (canEdit)
            IconButton(
              icon: isSaving
                  ? SizedBox(
                      width: isSmallScreen ? 20 : 24,
                      height: isSmallScreen ? 20 : 24,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      Icons.save,
                      size: isSmallScreen ? 20 : 24,
                    ),
              onPressed: _saveCode,
              tooltip: 'Save Code',
            ),
          if (canEdit)
            IconButton(
              icon: Icon(
                Icons.play_arrow,
                size: isSmallScreen ? 20 : 24,
              ),
              onPressed: _runCode,
              tooltip: 'Run Code',
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLanguageSelector(),
              SizedBox(height: isSmallScreen ? 12 : 16),
              Expanded(
                child: SingleChildScrollView(
                  controller: _codeScrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildCodeEditor(),
                      SizedBox(height: isSmallScreen ? 12 : 16),
                      _buildOutputPanel(),
                      SizedBox(height: isSmallScreen ? 12 : 16),
                      _buildFeedbackPanel(),
                      SizedBox(height: isSmallScreen ? 12 : 16),
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