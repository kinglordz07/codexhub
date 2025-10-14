import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CollabCodeEditorScreen extends StatefulWidget {
  final String roomId;
  final bool isMentor;
  

  const CollabCodeEditorScreen({
    super.key,
    required this.roomId,
    this.isMentor = false,
  });

  @override
  State<CollabCodeEditorScreen> createState() =>
      _CollabCodeEditorScreenState();
}

class _CollabCodeEditorScreenState extends State<CollabCodeEditorScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _feedbackController = TextEditingController();

  bool isSaving = false;
  bool isLoading = true;
  bool _isLocalEdit = false;

  

  String selectedLanguage = 'python';
  String output = '';

  bool _ignoreNextUpdate = false;

  Timer? _typingTimer;
  RealtimeChannel? _channel;

  List<int> _highlightedLines = [];
  Map<int, String> _lineComments = {};

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
    _loadSession().then((_) => _subscribeRealtime());

  _codeController.addListener(() {
  if (_isLocalEdit) return;

  _updateSpecificLine();
  _updateCursorPosition();
});
    _feedbackController.addListener(() {
  if (widget.isMentor) {
    _updateLiveField('mentor_feedback', _feedbackController.text);
  }
});
  }

  void _updateSpecificLine() {
  final codeText = _codeController.text;
  _updateLiveField('code', codeText);
}

  Future<void> _loadSession() async {
    try {
      final session = await supabase
          .from('live_sessions')
          .select()
          .eq('id', widget.roomId)
          .maybeSingle();

      if (session != null) {
        selectedLanguage = session['language'] ?? 'python';
        final rawCode = (session['code'] ?? '').toString();
        _codeController.text =
            rawCode.isEmpty ? (defaultSnippets[selectedLanguage] ?? '') : rawCode;

        output = session['output'] ?? '';
        _feedbackController.text = session['mentor_feedback'] ?? '';
        _highlightedLines = List<int>.from(session['highlighted_lines'] ?? []);
        _lineComments = Map<int, String>.from(session['line_comments'] ?? {});
      } else {
        _codeController.text = defaultSnippets[selectedLanguage] ?? '';
      }
    } catch (e) {
      debugPrint('❌ Error loading session: $e');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _subscribeRealtime() {
  _channel = supabase.channel('public:live_sessions')
    ..onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'live_sessions',
      callback: (payload) {
  if (_ignoreNextUpdate) return; // 🛑 Skip if this update came from ourselves

  final newData = payload.newRecord;
  if (!mounted) return;

  setState(() {
  if (newData['code'] != null && newData['code'] != _codeController.text) {
    _isLocalEdit = true; // 🧩 mark as external update

    final oldSelection = _codeController.selection;
    _codeController.text = newData['code'] as String;

    // keep cursor stable
    final offset = oldSelection.baseOffset.clamp(0, _codeController.text.length);
    _codeController.selection = TextSelection.collapsed(offset: offset);

    _isLocalEdit = false;
  }

  // ✅ update other fields
  output = newData['output'] ?? output;

  if (!widget.isMentor) {
    _feedbackController.text = newData['mentor_feedback'] ?? '';
  }

  _highlightedLines = List<int>.from(newData['highlighted_lines'] ?? []);
  _lineComments = Map<int, String>.from(newData['line_comments'] ?? {});
});
},
    )
    ..subscribe();

  debugPrint('✅ Realtime listening for room ${widget.roomId}');
}

  Future<void> _updateLiveField(String field, dynamic value) async {
  try {
    _ignoreNextUpdate = true; // 🟢 prevent self-trigger
    dynamic supabaseValue = value;
    if (field == 'line_comments' && value is Map<int, String>) {
      supabaseValue = value.map<String, String>((k, v) => MapEntry(k.toString(), v));
    }

    await supabase
        .from('live_sessions')
        .update({field: supabaseValue})
        .eq('id', widget.roomId);
  } catch (e) {
    debugPrint('⚠️ Error updating $field: $e');
  } finally {
    // 🔵 Delay unflag para sure na tapos muna ang DB update
    Future.delayed(const Duration(milliseconds: 400), () {
      _ignoreNextUpdate = false;
    });
  }
}

  void _updateCursorPosition() {
  final cursorPos = _codeController.selection.baseOffset;
  if (widget.isMentor) {
    _updateLiveField('mentor_cursor', cursorPos);
  } else {
    _updateLiveField('mentee_cursor', cursorPos);
  }
}


  Future<void> _saveCode() async {
  if (isSaving) return;
  setState(() => isSaving = true);

  try {
    // Prepare data
    final Map<String, dynamic> dataToSave = {
      'code': _codeController.text,
      'language': selectedLanguage,
      'output': output,
      'mentor_feedback': _feedbackController.text,
      'highlighted_lines': _highlightedLines,
      'line_comments': _lineComments.map((k, v) => MapEntry(k.toString(), v)),
    };

    // Save to Supabase
    await supabase
        .from('live_sessions')
        .update(dataToSave)
        .eq('id', widget.roomId);

    // Feedback
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Code saved!')));
  } catch (e, st) {
    debugPrint('❌ Error saving code: $e');
    debugPrint('$st');
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Failed to save code')));
    }
  } finally {
    setState(() => isSaving = false);
  }
}


  Future<void> _runCode() async {
  final codeToRun = _codeController.text;
  if (codeToRun.isEmpty) {
    setState(() => output = '⚠️ No valid code to run.');
    await _updateLiveField('output', output);
    return;
  }

  setState(() => output = 'Running code...');
  await Future.delayed(const Duration(milliseconds: 500));

  final result = _getFakeExecutionResult(codeToRun, selectedLanguage);
  setState(() => output = result);

  // Update output for both mentor and mentee in real-time
  await _updateLiveField('output', result);
}
  String _getFakeExecutionResult(String code, String language) {
  List<String> results = [];

  if (language == 'python') {
    final regex = RegExp(r'print\s*\((.*?)\)', dotAll: true);
    final matches = regex.allMatches(code);
    for (var m in matches) {
      var content = m.group(1) ?? '';
      if ((content.startsWith('"') && content.endsWith('"')) ||
          (content.startsWith("'") && content.endsWith("'"))) {
        content = content.substring(1, content.length - 1);
      }
      results.add(content);
    }
  } else if (language == 'java') {
    final regex = RegExp(r'System\.out\.println\s*\((.*?)\)\s*;', dotAll: true);
    final matches = regex.allMatches(code);
    for (var m in matches) {
      var content = m.group(1) ?? '';
      if ((content.startsWith('"') && content.endsWith('"')) ||
          (content.startsWith("'") && content.endsWith("'"))) {
        content = content.substring(1, content.length - 1);
      }
      results.add(content);
    }
  } else if (language == 'csharp') {
    final regex = RegExp(r'Console\.WriteLine\s*\((.*?)\)\s*;', dotAll: true);
    final matches = regex.allMatches(code);
    for (var m in matches) {
      var content = m.group(1) ?? '';
      if ((content.startsWith('"') && content.endsWith('"')) ||
          (content.startsWith("'") && content.endsWith("'"))) {
        content = content.substring(1, content.length - 1);
      }
      results.add(content);
    }
  } else if (language == 'vbnet') {
    final regex = RegExp(r'Console\.WriteLine\s*\((.*?)\)', dotAll: true);
    final matches = regex.allMatches(code);
    for (var m in matches) {
      var content = m.group(1) ?? '';
      if ((content.startsWith('"') && content.endsWith('"')) ||
          (content.startsWith("'") && content.endsWith("'"))) {
        content = content.substring(1, content.length - 1);
      }
      results.add(content);
    }
  }

  return results.isEmpty
      ? '⚠️ Nothing to execute or unsupported code.'
      : results.join('\n');
}

  @override
  void dispose() {
    _typingTimer?.cancel();
    _channel?.unsubscribe();
    _codeController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  title: const Text('CodeLiveReview'),
  actions: [
    // Mentee buttons
    if (!widget.isMentor)
      IconButton(
        icon: isSaving
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.save),
        onPressed: _saveCode,
      ),
    if (!widget.isMentor)
      IconButton(icon: const Icon(Icons.play_arrow), onPressed: _runCode),

    // Mentor buttons (pwede na rin mag-save/run)
    if (widget.isMentor)
      IconButton(
        icon: isSaving
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.save),
        onPressed: _saveCode,
      ),
    if (widget.isMentor)
      IconButton(icon: const Icon(Icons.play_arrow), onPressed: _runCode),
  ],
),

      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedLanguage,
                    items: const [
                      DropdownMenuItem(value: 'python', child: Text('Python')),
                      DropdownMenuItem(value: 'vbnet', child: Text('VB.NET')),
                      DropdownMenuItem(value: 'java', child: Text('Java')),
                      DropdownMenuItem(value: 'csharp', child: Text('C#')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          selectedLanguage = v;
                          _codeController.text = defaultSnippets[v] ?? '';
                          _highlightedLines.clear();
                          _lineComments.clear();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      child: TextField(
                        controller: _codeController,
                        maxLines: null,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        style:
                            const TextStyle(fontFamily: 'monospace', fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(5)),
                    child: Text(
                      'Output:\n$output',
                      style:
                          const TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 10),
                  widget.isMentor
                      ? TextField(
                          controller: _feedbackController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            hintText: 'Type mentor feedback here...',
                          ),
                        )
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              border: Border.all(color: Colors.green),
                              borderRadius: BorderRadius.circular(5)),
                          child: Text(
                            'Mentor Feedback:\n${_feedbackController.text}',
                            style: const TextStyle(
                                fontSize: 14, color: Colors.green),
                          ),
                        ),
                ],
              ),
            ),
    );
  }
}
