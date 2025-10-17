// ignore_for_file: prefer_final_fields

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
  Color _feedbackBg = Colors.transparent;

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

    // Kunin ang existing session para sa room
    final session = await supabase
        .from('live_sessions')
        .select()
        .eq('room_id', widget.roomId)
        .maybeSingle();

    if (session != null) {
      _mentorId = session['mentor_id'];
      _menteeId = session['mentee_id'];
      selectedLanguage = session['language'] ?? 'python';

      // Para sa viewers at editors pareho, set the code + output
      _codeController.text = session['code'] ?? defaultSnippets[selectedLanguage]!;
      output = session['output'] ?? '';
      _feedbackController.text = session['mentor_feedback'] ?? '';

      // Edit permission lang sa mentor/mentee
      canEdit = (_currentUserId == _mentorId || _currentUserId == _menteeId);
    } else {
      // Kung walang session, gumawa ng bagong session (auto editor)
      final newSession = await supabase.from('live_sessions').insert({
        'room_id': widget.roomId,
        'language': selectedLanguage,
        'code': defaultSnippets[selectedLanguage] ?? '',
        'is_live': true,
        'waiting': false,
      }).select().maybeSingle();

      _codeController.text = newSession?['code'] ?? '';
      output = newSession?['output'] ?? '';
      canEdit = true; // gumawa ng bagong session, creator can edit
    }
  } catch (e) {
    debugPrint('❌ Error loading session: $e');
  } finally {
    if (mounted) setState(() => isLoading = false);
  }
}

  void _setupListeners() {
    _codeController.addListener(() {
      if (!canEdit) return;
      _isLocalEdit = true;

      _restartTypingTimer(() async {
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

        // Viewer lang, di kailangan i-block
        if (_isLocalEdit && canEdit) return;

        setState(() {
          final remoteCode = newData['code'];
          if (remoteCode != null && remoteCode != _codeController.text) {
            final oldSel = _codeController.selection;
            _codeController.text = remoteCode;
            final offset = oldSel.baseOffset.clamp(0, _codeController.text.length);
            _codeController.selection = TextSelection.collapsed(offset: offset);
          }

          if (newData['mentor_feedback'] != null) {
            _feedbackController.text = newData['mentor_feedback'];
          }

          final otherCursorField = (_currentUserId == _mentorId) ? 'mentee_cursor' : 'mentor_cursor';
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
      await supabase
          .from('live_sessions')
          .update({
            field: value,
            'last_editor': _currentUserId,
          })
          .eq('room_id', widget.roomId);
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
          const SnackBar(content: Text('💾 Code saved!')),
        );
      }
    } catch (e) {
      debugPrint('❌ Error saving code: $e');
    } finally {
      setState(() => isSaving = false);
    }
  }

  Future<void> _runCode() async {
    if (!canEdit) return;
    setState(() => output = 'Running code...');
    await Future.delayed(const Duration(milliseconds: 500));
    final result = _getFakeExecutionResult(_codeController.text, selectedLanguage);
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

  @override
  Widget build(BuildContext context) {
    const double charWidth = 8;
    const double lineHeight = 20;
    const int charsPerLine = 80;

    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('CodeLiveReview'),
        actions: [
          if (canEdit)
            IconButton(
              icon: isSaving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Icon(Icons.save),
              onPressed: _saveCode,
            ),
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: _runCode,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          controller: _codeScrollController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedLanguage,
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
                          });
                        }
                      }
                    : null,
              ),
              const SizedBox(height: 10),
              Container(
                height: 300,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Stack(
                  children: [
                    TextField(
                      controller: _codeController,
                      maxLines: null,
                      expands: true,
                      readOnly: !canEdit,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(8),
                      ),
                      style:
                          const TextStyle(fontFamily: 'monospace', fontSize: 14),
                    ),
                    if (_otherUserCursor != null &&
                        _otherUserCursor! <= _codeController.text.length)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 150),
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
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text('Output:\n$output'),
              ),
              const SizedBox(height: 10),
              if (_isMentorCurrentUser())
                TextField(
                  controller: _feedbackController,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Type mentor feedback here...',
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.green),
                    borderRadius: BorderRadius.circular(5),
                    color: _feedbackBg,
                  ),
                  child: Text(
                    'Mentor Feedback:\n${_feedbackController.text}',
                    style: const TextStyle(color: Colors.green),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
