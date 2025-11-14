import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/cs.dart';
import 'package:highlight/languages/python.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:highlight/highlight.dart';
import 'package:http/http.dart' as http;
import 'dart:math';
import 'dart:convert';

class CollabCodeEditorScreen extends StatefulWidget {
  final String roomId;
  final bool isMentor;

  const CollabCodeEditorScreen({
    super.key,
    required this.roomId,
    required this.isMentor,
  });

  @override
  State<CollabCodeEditorScreen> createState() => _CollabCodeEditorScreenState();
}

class _CollabCodeEditorScreenState extends State<CollabCodeEditorScreen>
    with SingleTickerProviderStateMixin {
  late CodeController _codeController;
  bool _isDarkMode = false;
  bool _isLoading = true;
  bool _showFileSelection = true; 
  String _selectedLanguage = 'python';
  String _output = '';
  late TabController _tabController;
  List<Map<String, dynamic>> _savedRooms = [];
  bool _isLoadingRooms = false;
  String _currentRoomTitle = 'Untitled';
  String? _currentRoomDescription;
  bool _isExecuting = false;

  final Map<String, Mode> _languages = {
    'python': python,
    'java': java,
    'csharp': cs,
  };

  final Map<String, Map<String, String>> _pistonLanguages = {
    'python': {'language': 'python', 'version': '3.10.0'},
    'java': {'language': 'java', 'version': '15.0.2'},
    'csharp': {'language': 'csharp', 'version': '6.12.0'},
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeEditor();
    _loadAllRooms();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _initializeEditor() async {
    _codeController = CodeController(
      text: '',
      language: _languages[_selectedLanguage] ?? python,
    );

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

 void _startNewFile() async {
  final TextEditingController titleController = TextEditingController(text: 'Untitled');

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: SingleChildScrollView(
          child: AlertDialog(
            title: const Text('Create New File'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'File Name',
                    hintText: 'Enter file name',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (titleController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a file name')),
                    );
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (result == true && mounted) {
    setState(() {
      _showFileSelection = false;
      _currentRoomTitle = titleController.text.trim();
      _currentRoomDescription = null;
      _codeController.text = '';
    });
    
    await _createInitialRoom();
  }
}

  void _openExistingFile(Map<String, dynamic> room) {
    if (mounted) {
      setState(() {
        _showFileSelection = false;
        _codeController.text = room['code'] ?? '';
        _selectedLanguage = room['language'] ?? 'python';
        _currentRoomTitle = room['title'] ?? 'Untitled';
        _currentRoomDescription = room['description'];
        _codeController.language = _languages[_selectedLanguage] ?? python;
      });
    }
    _updateCurrentRoomContent(room);
  }

  Future<void> _updateCurrentRoomContent(Map<String, dynamic> room) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        var query = Supabase.instance.client.from('code_rooms').update({
          'room_id': widget.roomId,
          'code': room['code'],
          'language': room['language'],
          'title': room['title'],
          'description': room['description'],
          'updated_at': DateTime.now().toIso8601String(),
          'user_id': user.id,
        });
        query = query.eq('room_id', widget.roomId);
      query = query.eq('user_id', user.id);
      
      await query;
      }
    } catch (e) {
      debugPrint('Error updating current room: $e');
      await _createInitialRoom();
    }
  }

  void _showFileSelectionScreen() {
    if (mounted) {
      setState(() {
        _showFileSelection = true;
      });
    }
  }

  Future<void> _createInitialRoom() async {
  try {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('❌ No user for creating initial room');
      return;
    }

    debugPrint('🏗️ Creating initial room: ${widget.roomId}');

    await Supabase.instance.client.from('code_rooms').insert({
      'room_id': widget.roomId,
      'code': _codeController.text,
      'language': _selectedLanguage,
      'title': _currentRoomTitle,
      'description': _currentRoomDescription,
      'is_public': false,
      'user_id': user.id,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    debugPrint('✅ Initial room created successfully');
  } catch (e, stackTrace) {
    debugPrint('❌ Error creating initial room: $e');
    debugPrint('Stack trace: $stackTrace');
    
    // If room already exists, that's fine - we'll update it later
    if (e.toString().contains('unique constraint')) {
      debugPrint('ℹ️ Room already exists, will update on save');
    }
  }
}

  Future<void> _loadAllRooms() async {
  if (!mounted) return;

  setState(() {
    _isLoadingRooms = true;
  });

  try {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      debugPrint('❌ No user logged in');
      if (mounted) {
        setState(() {
          _isLoadingRooms = false;
          _savedRooms = [];
        });
      }
      return;
    }

    debugPrint('🔄 Loading rooms for user: ${user.id}');
    
    final response = await Supabase.instance.client
        .from('code_rooms')
        .select('*')
        .eq('user_id', user.id)  // This filter requires RLS policy
        .order('updated_at', ascending: false);

    debugPrint('✅ Loaded ${response.length} rooms');

    if (mounted) {
      setState(() {
        _savedRooms = List<Map<String, dynamic>>.from(response);
        _isLoadingRooms = false;
      });
    }
  } catch (e, stackTrace) {
    debugPrint('❌ Error loading rooms: $e');
    debugPrint('Stack trace: $stackTrace');
    
    // Check for RLS policy errors
    if (e.toString().toLowerCase().contains('policy') || 
        e.toString().toLowerCase().contains('permission')) {
      debugPrint('🔒 RLS Policy Error - Check your database policies');
      if (mounted) {
        _showSnackBar('Database permission error. Contact administrator.');
      }
    }
    
    if (mounted) {
      setState(() {
        _isLoadingRooms = false;
        _savedRooms = [];
      });
    }
  }
}

  Future<void> _saveCurrentRoom() async {
  if (_codeController.text.trim().isEmpty) {
    if (mounted) {
      _showSnackBar('No code to save');
    }
    return;
  }

  try {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        _showSnackBar('Please sign in to save files');
      }
      return;
    }

    debugPrint('🔄 Saving code for user: ${user.id}');
    debugPrint('📝 Room ID: ${widget.roomId}');

    // Use upsert with onConflict to handle unique constraints
    final response = await Supabase.instance.client
        .from('code_rooms')
        .upsert({
          'room_id': widget.roomId,
          'code': _codeController.text,
          'language': _selectedLanguage,
          'title': _currentRoomTitle,
          'description': _currentRoomDescription,
          'user_id': user.id,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'room_id,user_id') // Add this if you use composite unique key
        .select();

    debugPrint('✅ Save response: $response');

    if (mounted) {
      _showSnackBar('Code saved successfully!');
    }

    await _loadAllRooms();
  } catch (e, stackTrace) {
    debugPrint('❌ Error saving code: $e');
    debugPrint('Stack trace: $stackTrace');
    
    // More specific error handling
    if (e.toString().contains('unique constraint')) {
      if (mounted) {
        _showSnackBar('Room ID conflict. Try saving with a different name.');
      }
    } else if (e.toString().contains('row-level security')) {
      if (mounted) {
        _showSnackBar('Permission denied. Please check RLS policies.');
      }
    } else {
      if (mounted) {
        _showSnackBar('Failed to save code: ${e.toString()}');
      }
    }
  }
}

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(8),
      ),
    );
  }

  Future<void> _saveAsNewRoom() async {
  if (_codeController.text.trim().isEmpty) {
    if (mounted) {
      _showSnackBar('No code to save');
    }
    return;
  }
  
  final TextEditingController titleController = TextEditingController(
    text: _currentRoomTitle,
  );
  final TextEditingController descriptionController = TextEditingController(
    text: _currentRoomDescription ?? '',
  );

  final result = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: SingleChildScrollView(
          child: AlertDialog(
            title: const Text('Save As New File'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'File Name',
                    hintText: 'Enter file name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    hintText: 'Enter file description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (titleController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a file name')),
                    );
                    return;
                  }
                  Navigator.pop(context, true);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  if (result == true && mounted) {
    await _performSaveAsNewRoom(
      titleController.text.trim(),
      descriptionController.text.trim(),
    );
  }
}

  Future<void> _performSaveAsNewRoom(String title, String description) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final newRoomId = 'room_${DateTime.now().millisecondsSinceEpoch}';

      await Supabase.instance.client.from('code_rooms').insert({
        'room_id': newRoomId,
        'description': description,
        'code': _codeController.text,
        'language': _selectedLanguage,
        'title': title,
        'is_public': false,
        'user_id': user?.id,
      });

      await _loadAllRooms();
      if (mounted) {
        _showSnackBar('New file saved successfully!');
      }
    } catch (e) {
      debugPrint('Error saving new room: $e');
      if (mounted) {
        _showSnackBar('Failed to save new file.');
      }
    }
  }

  Future<void> _updateRoomInfo() async {
    final TextEditingController titleController = TextEditingController(
      text: _currentRoomTitle,
    );
    final TextEditingController descriptionController = TextEditingController(
      text: _currentRoomDescription ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 400,
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: SingleChildScrollView(
            child: AlertDialog(
              title: const Text('Update File Info'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'File Name',
                      hintText: 'Enter file name',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description (Optional)',
                      hintText: 'Enter file description',
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (titleController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a file name')),
                      );
                      return;
                    }
                    Navigator.pop(context, true);
                  },
                  child: const Text('Update'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (result == true && mounted) {
      await _performUpdateRoomInfo(
        titleController.text.trim(),
        descriptionController.text.trim(),
      );
    }
  }

  Future<void> _performUpdateRoomInfo(String title, String description) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      await Supabase.instance.client.from('code_rooms').upsert({
        'room_id': widget.roomId,
        'title': title,
        'description': description,
        'updated_at': DateTime.now().toIso8601String(),
        'user_id': user?.id,
      });

      if (mounted) {
        setState(() {
          _currentRoomTitle = title;
          _currentRoomDescription = description;
        });
      }

      await _loadAllRooms();
      if (mounted) {
        _showSnackBar('File info updated successfully!');
      }
    } catch (e) {
      debugPrint('Error updating room info: $e');
      if (mounted) {
        _showSnackBar('Failed to update file info.');
      }
    }
  }

 



  Future<void> _deleteRoom(Map<String, dynamic> room) async {
    if (room['room_id'] == widget.roomId) {
      if (mounted) {
        _showSnackBar('Cannot delete the current file');
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text(
          'Are you sure you want to delete "${room['title']}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await Supabase.instance.client
            .from('code_rooms')
            .delete()
            .eq('room_id', room['room_id']);

        await _loadAllRooms();
        if (mounted) {
          _showSnackBar('Deleted: ${room['title']}');
        }
      } catch (e) {
        debugPrint('Error deleting room: $e');
        if (mounted) {
          _showSnackBar('Failed to delete file.');
        }
      }
    }
  }

  Future<void> _runCode() async {
    if (_isExecuting) return;
    
    _tabController.animateTo(1);

    if (mounted) {
      setState(() {
        _isExecuting = true;
        _output = "🔄 Running ${_getDisplayName(_selectedLanguage)} code...";
      });
    }

    try {
      final pistonLang = _pistonLanguages[_selectedLanguage];
      if (pistonLang == null) {
        throw Exception('Language $_selectedLanguage not supported');
      }

      final uri = Uri.parse('https://emkc.org/api/v2/piston/execute');
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'language': pistonLang['language'],
              'version': pistonLang['version'],
              'files': [
                {'content': _codeController.text},
              ],
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final runData = data['run'];
        String outputText;
        
        if (runData['stderr']?.isNotEmpty == true) {
          outputText = '🌐 ONLINE EXECUTION\n❌ ERROR:\n${runData['stderr']}';
        } else if (runData['stdout']?.isNotEmpty == true) {
          outputText = '🌐 ONLINE EXECUTION\n✅ OUTPUT:\n${runData['stdout']}';
        } else {
          outputText = '🌐 ONLINE EXECUTION\n✅ Program executed successfully (no output)';
        }

        if (mounted) {
          setState(() {
            _output = outputText;
            _isExecuting = false;
          });
        }
        return; 
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Online execution failed: $e');
      await _executeEnhancedOffline();
    }
  }

  Future<void> _executeEnhancedOffline() async {
    final code = _codeController.text;
    final random = Random();

    await Future.delayed(Duration(milliseconds: 500 + random.nextInt(1000)));

    String analyzedOutput;

    if (code.trim().isEmpty) {
      analyzedOutput = '❌ No code to execute\nPlease write some code first.';
    } else {
      analyzedOutput = _analyzeCodeStructure(code);
    }

    if (mounted) {
      setState(() {
        _output = '''🔍 ENHANCED OFFLINE ANALYSIS
🌐 Connection: Offline
💻 Language: ${_getDisplayName(_selectedLanguage)}
📊 Analysis Result:

$analyzedOutput

💡 Tip: Connect to internet for real code execution''';
        _isExecuting = false;
      });
    }
  }

  String _analyzeCodeStructure(String code) {
    final output = StringBuffer();
    final lines = code.split('\n');
    int lineCount = lines.length;
    int nonEmptyLines = lines.where((line) => line.trim().isNotEmpty).length;

    output.writeln('📊 Code Analysis:');
    output.writeln('📄 Total lines: $lineCount');
    output.writeln('📝 Non-empty lines: $nonEmptyLines');
    output.writeln('');

    switch (_selectedLanguage) {
      case 'python':
        _analyzePythonCode(code, output);
        break;
      case 'java':
        _analyzeJavaCode(code, output);
        break;
      case 'csharp':
        _analyzeCSharpCode(code, output);
        break;
    }

    return output.toString();
  }

  void _analyzePythonCode(String code, StringBuffer output) {
    final functions = RegExp(r'def\s+(\w+)\s*\(').allMatches(code);
    final imports = RegExp(r'^import\s+(\w+)', multiLine: true).allMatches(code);
    final prints = RegExp(r'print\s*\(([^)]+)\)').allMatches(code);
    final variables = RegExp(r'^(\w+)\s*=').allMatches(code);
    final classes = RegExp(r'class\s+(\w+)').allMatches(code);

    if (functions.isNotEmpty) {
      output.writeln('🔧 Functions found:');
      for (final match in functions) {
        output.writeln('   - ${match.group(1)}()');
      }
      output.writeln('');
    }

    if (imports.isNotEmpty) {
      output.writeln('📦 Imports found:');
      for (final match in imports) {
        output.writeln('   - ${match.group(1)}');
      }
      output.writeln('');
    }

    if (classes.isNotEmpty) {
      output.writeln('🏗️ Classes found:');
      for (final match in classes) {
        output.writeln('   - ${match.group(1)}');
      }
      output.writeln('');
    }

    if (variables.isNotEmpty) {
      output.writeln('💾 Variables found: ${variables.length}');
      output.writeln('');
    }

    if (prints.isNotEmpty) {
      output.writeln('🖨️ Print statements: ${prints.length}');
      output.writeln('   Expected output:');
      for (final match in prints) {
        final content = match.group(1);
        if (content != null) {
          final evaluated = _evaluatePythonExpression(content);
          output.writeln('   - $evaluated');
        }
      }
    } else {
      output.writeln('💡 No print statements found');
    }

    if (code.contains('for ') && code.contains(' in ')) {
      output.writeln('\n🔄 For loop detected');
    }
    if (code.contains('if ') && code.contains(':')) {
      output.writeln('🔍 If statements detected');
    }
    if (code.contains('while ')) {
      output.writeln('⚡ While loop detected');
    }
  }

  void _analyzeJavaCode(String code, StringBuffer output) {
    final methods = RegExp(r'(public|private|protected)?\s*\w+\s+(\w+)\s*\(').allMatches(code);
    final classes = RegExp(r'class\s+(\w+)').allMatches(code);
    final prints = RegExp(r'System\.out\.(print|println)\s*\(([^)]+)\)').allMatches(code);
    final variables = RegExp(r'\w+\s+(\w+)\s*=').allMatches(code);

    if (classes.isNotEmpty) {
      output.writeln('🏗️ Classes found:');
      for (final match in classes) {
        output.writeln('   - ${match.group(1)}');
      }
      output.writeln('');
    }

    if (methods.isNotEmpty) {
      output.writeln('🔧 Methods found:');
      for (final match in methods) {
        if (match.group(2) != 'main' && match.group(2) != 'class') {
          output.writeln('   - ${match.group(2)}()');
        }
      }
      output.writeln('');
    }

    if (variables.isNotEmpty) {
      output.writeln('💾 Variables found: ${variables.length}');
      output.writeln('');
    }

    if (prints.isNotEmpty) {
      output.writeln('🖨️ Print statements: ${prints.length}');
      output.writeln('   Expected output:');
      for (final match in prints) {
        final content = match.group(2);
        if (content != null) {
          final evaluated = _evaluateJavaExpression(content);
          output.writeln('   - $evaluated');
        }
      }
    } else {
      output.writeln('💡 No print statements found');
    }

    if (code.contains('for (')) {
      output.writeln('\n🔄 For loop detected');
    }
    if (code.contains('if (')) {
      output.writeln('🔍 If statements detected');
    }
    if (code.contains('while (')) {
      output.writeln('⚡ While loop detected');
    }
  }

  void _analyzeCSharpCode(String code, StringBuffer output) {
    final methods = RegExp(r'(public|private|protected)?\s*\w+\s+(\w+)\s*\(').allMatches(code);
    final classes = RegExp(r'class\s+(\w+)').allMatches(code);
    final prints = RegExp(r'Console\.(Write|WriteLine)\s*\(([^)]+)\)').allMatches(code);
    final variables = RegExp(r'\w+\s+(\w+)\s*=').allMatches(code);

    if (classes.isNotEmpty) {
      output.writeln('🏗️ Classes found:');
      for (final match in classes) {
        output.writeln('   - ${match.group(1)}');
      }
      output.writeln('');
    }

    if (methods.isNotEmpty) {
      output.writeln('🔧 Methods found:');
      for (final match in methods) {
        if (match.group(2) != 'Main' && match.group(2) != 'class') {
          output.writeln('   - ${match.group(2)}()');
        }
      }
      output.writeln('');
    }

    if (variables.isNotEmpty) {
      output.writeln('💾 Variables found: ${variables.length}');
      output.writeln('');
    }

    if (prints.isNotEmpty) {
      output.writeln('🖨️ Console writes: ${prints.length}');
      output.writeln('   Expected output:');
      for (final match in prints) {
        final content = match.group(2);
        if (content != null) {
          final evaluated = _evaluateCSharpExpression(content);
          output.writeln('   - $evaluated');
        }
      }
    } else {
      output.writeln('💡 No console output statements found');
    }

    if (code.contains('for (')) {
      output.writeln('\n🔄 For loop detected');
    }
    if (code.contains('if (')) {
      output.writeln('🔍 If statements detected');
    }
    if (code.contains('while (')) {
      output.writeln('⚡ While loop detected');
    }
  }

  String _evaluatePythonExpression(String expr) {
    expr = expr.trim();
    
    if ((expr.startsWith("'") && expr.endsWith("'")) ||
        (expr.startsWith('"') && expr.endsWith('"'))) {
      return expr.substring(1, expr.length - 1);
    }

    if (RegExp(r'^\d+\s*[\+\-\*\/]\s*\d+$').hasMatch(expr)) {
      try {
        if (expr.contains('+')) {
          final parts = expr.split('+');
          if (parts.length >= 2) {
            final a = int.tryParse(parts[0].trim()) ?? double.tryParse(parts[0].trim());
            final b = int.tryParse(parts[1].trim()) ?? double.tryParse(parts[1].trim());
            if (a != null && b != null) return (a + b).toString();
          }
        }
        if (expr.contains('-')) {
          final parts = expr.split('-');
          if (parts.length >= 2) {
            final a = int.tryParse(parts[0].trim()) ?? double.tryParse(parts[0].trim());
            final b = int.tryParse(parts[1].trim()) ?? double.tryParse(parts[1].trim());
            if (a != null && b != null) return (a - b).toString();
          }
        }
      } catch (e) {
        return expr;
      }
    }

    if (expr.contains('+') && (expr.contains("'") || expr.contains('"'))) {
      try {
        final parts = expr.split('+');
        final result = parts.map((part) {
          final trimmed = part.trim();
          if ((trimmed.startsWith("'") && trimmed.endsWith("'")) ||
              (trimmed.startsWith('"') && trimmed.endsWith('"'))) {
            return trimmed.substring(1, trimmed.length - 1);
          }
          return trimmed;
        }).join();
        return result;
      } catch (e) {
        return expr.replaceAll("'", "").replaceAll('"', '');
      }
    }

    return expr;
  }

  String _evaluateJavaExpression(String expr) {
    expr = expr.replaceAll(';', '').trim();
    
    if (expr.startsWith('"') && expr.endsWith('"')) {
      return expr.substring(1, expr.length - 1);
    }

    if (RegExp(r'^\d+\s*[\+\-\*\/]\s*\d+$').hasMatch(expr)) {
      try {
        if (expr.contains('+')) {
          final parts = expr.split('+');
          final a = int.tryParse(parts[0].trim());
          final b = int.tryParse(parts[1].trim());
          if (a != null && b != null) return (a + b).toString();
        }
      } catch (e) {
        return expr;
      }
    }

    return expr;
  }

  String _evaluateCSharpExpression(String expr) {
    expr = expr.replaceAll(';', '').trim();
    
    if (expr.startsWith('"') && expr.endsWith('"')) {
      return expr.substring(1, expr.length - 1);
    }

    if (RegExp(r'^\d+\s*[\+\-\*\/]\s*\d+$').hasMatch(expr)) {
      try {
        if (expr.contains('+')) {
          final parts = expr.split('+');
          if (parts.length >= 2) {
            final a = int.tryParse(parts[0].trim());
            final b = int.tryParse(parts[1].trim());
            if (a != null && b != null) return (a + b).toString();
          }
        }
      } catch (e) {
        return expr;
      }
    }

    return expr;
  }

  String _getDisplayName(String value) {
    switch (value) {
      case 'python':
        return 'Python';
      case 'java':
        return 'Java';
      case 'csharp':
        return 'C#';
      default:
        return value;
    }
  }

  String _getLanguageDisplayName(String lang) {
    switch (lang) {
      case 'python':
        return 'Python';
      case 'java':
        return 'Java';
      case 'csharp':
        return 'C#';
      default:
        return lang;
    }
  }

  void _clearCode() {
    if (mounted) {
      setState(() {
        _codeController.text = '';
        _output = '';
      });
    }
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _codeController.text));
    if (mounted) {
      _showSnackBar('Code copied to clipboard!');
    }
  }

  void _copyOutput() {
    if (_output.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: _output));
      if (mounted) {
        _showSnackBar('Output copied to clipboard!');
      }
    }
  }

  void _clearOutput() {
    if (mounted) {
      setState(() {
        _output = '';
      });
    }
  }

  void _toggleTheme() {
    if (mounted) {
      setState(() {
        _isDarkMode = !_isDarkMode;
      });
    }
  }

  void _changeLanguage(String? newValue) {
    if (newValue != null && _languages.containsKey(newValue)) {
      if (mounted) {
        setState(() {
          _selectedLanguage = newValue;
          _codeController.language = _languages[newValue]!;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
          ),
        ),
      );
    }

    if (_showFileSelection) {
      return _buildFileSelectionScreen();
    }

    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final isVerySmallScreen = screenSize.width < 400;
    final isTablet = screenSize.width >= 600 && screenSize.width < 1200;

    final double titleFontSize = isVerySmallScreen ? 14 : (isSmallScreen ? 16 : (isTablet ? 18 : 20));
    final double bodyFontSize = isVerySmallScreen ? 12 : (isSmallScreen ? 14 : 16);
    final double iconSize = isVerySmallScreen ? 18 : (isSmallScreen ? 20 : 24);
    final double buttonPadding = isVerySmallScreen ? 8 : (isSmallScreen ? 12 : 16);

    final dropdownItems = _languages.keys.map<DropdownMenuItem<String>>((String key) {
      return DropdownMenuItem<String>(
        value: key,
        child: Text(
          _getDisplayName(key),
          style: TextStyle(fontSize: isVerySmallScreen ? 12 : 14),
        ),
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _currentRoomTitle,
              style: TextStyle(fontSize: titleFontSize),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_currentRoomDescription != null && _currentRoomDescription!.isNotEmpty)
              Text(
                _currentRoomDescription!,
                style: TextStyle(
                  fontSize: isSmallScreen ? 10 : 12,
                  fontWeight: FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        foregroundColor: Colors.white,
        backgroundColor: Colors.indigo,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.lightBlueAccent,
          tabs: [
            Tab(
              icon: Icon(Icons.code, size: iconSize),
              text: isVerySmallScreen ? null : 'Editor',
            ),
            Tab(
              icon: Icon(Icons.output, size: iconSize),
              text: isVerySmallScreen ? null : 'Output',
            ),
            Tab(
              icon: Icon(Icons.folder, size: iconSize),
              text: isVerySmallScreen ? null : 'Files',
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.folder_open, size: iconSize),
            onPressed: _showFileSelectionScreen,
            tooltip: 'Open File Selection',
            padding: EdgeInsets.all(isVerySmallScreen ? 4 : 8),
          ),
          
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedLanguage,
                items: dropdownItems,
                onChanged: _changeLanguage,
                dropdownColor: _isDarkMode ? Colors.grey[800] : Colors.white,
                iconSize: isSmallScreen ? 18 : 24,
                style: TextStyle(
                  color: _isDarkMode ? Colors.white : Colors.black,
                  fontSize: isSmallScreen ? 12 : 14,
                ),
                icon: Icon(
                  Icons.arrow_drop_down,
                  color: Colors.white,
                  size: isSmallScreen ? 18 : 24,
                ),
                underline: Container(),
              ),
            ),
          ),
          
          _isExecuting
              ? Padding(
                  padding: EdgeInsets.all(isVerySmallScreen ? 4 : 8),
                  child: SizedBox(
                    width: iconSize,
                    height: iconSize,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                )
              : IconButton(
                  icon: Icon(Icons.play_arrow, size: iconSize),
                  onPressed: _runCode,
                  tooltip: 'Run Code',
                  padding: EdgeInsets.all(isVerySmallScreen ? 4 : 8),
                ),
          
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, size: iconSize),
            onSelected: (value) {
              switch (value) {
                case 'save':
                  _saveCurrentRoom();
                  break;
                case 'save_as':
                  _saveAsNewRoom();
                  break;
                case 'update_info':
                  _updateRoomInfo();
                  break;
                case 'theme':
                  _toggleTheme();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'save',
                child: ListTile(
                  leading: Icon(Icons.save),
                  title: Text('Save'),
                ),
              ),
              const PopupMenuItem(
                value: 'save_as',
                child: ListTile(
                  leading: Icon(Icons.save_as),
                  title: Text('Save As...'),
                ),
              ),
              const PopupMenuItem(
                value: 'update_info',
                child: ListTile(
                  leading: Icon(Icons.info),
                  title: Text('Update File Info'),
                ),
              ),
              PopupMenuItem(
                value: 'theme',
                child: ListTile(
                  leading: Icon(
                    _isDarkMode ? Icons.light_mode : Icons.dark_mode,
                  ),
                  title: Text(_isDarkMode ? 'Light Mode' : 'Dark Mode'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: TabBarView(
          controller: _tabController,
          children: [
            // Editor Tab 
            _buildEditorTab(isSmallScreen, bodyFontSize, iconSize),

            // Output Tab
            _buildOutputTab(isSmallScreen, bodyFontSize, iconSize),

            // Files Tab
            _buildFilesTab(isSmallScreen, isVerySmallScreen, bodyFontSize, iconSize, buttonPadding),
          ],
        ),
      ),
    );
  }

  Widget _buildFileSelectionScreen() {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Code Editor'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.indigo,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Icon(
                    Icons.code,
                    size: isSmallScreen ? 60 : 80,
                    color: Colors.indigo,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Welcome to Code Editor',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 20 : 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Choose how you want to start coding:',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 16,
                    color: Colors.grey[600],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // New File Option
                Card(
                  elevation: 4,
                  child: ListTile(
                    leading: Icon(
                      Icons.create_new_folder,
                      size: isSmallScreen ? 32 : 40,
                      color: Colors.green,
                    ),
                    title: Text(
                      'Create New File',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 16 : 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      'Start with a blank file and write new code',
                      style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios, size: isSmallScreen ? 16 : 20),
                    onTap: _startNewFile,
                  ),
                ),
                const SizedBox(height: 16),
                // Open Existing File Option
                Card(
                  elevation: 4,
                  child: ListTile(
                    leading: Icon(
                      Icons.folder_open,
                      size: isSmallScreen ? 32 : 40,
                      color: Colors.blue,
                    ),
                    title: Text(
                      'Open Existing File',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 16 : 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      'Open and continue working on a saved file',
                      style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios, size: isSmallScreen ? 16 : 20),
                    onTap: () {
                      setState(() {
                        _showFileSelection = false;
                        _tabController.animateTo(2);
                      });
                    },
                  ),
                ),
                const SizedBox(height: 24),
                // Info Container
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.info,
                        color: Colors.blue,
                        size: isSmallScreen ? 20 : 24,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You can always switch between files using the folder icon in the app bar',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 11 : 13,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditorTab(bool isSmallScreen, double bodyFontSize, double iconSize) {
    return Container(
      color: _isDarkMode ? Colors.black : Colors.grey[200],
      child: Column(
        children: [
          // Clear and Copy buttons 
          Container(
            padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
            color: _isDarkMode ? Colors.grey[800] : Colors.grey[300],
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Code Editor - ${_getDisplayName(_selectedLanguage)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: bodyFontSize,
                      color: _isDarkMode ? Colors.white : Colors.black,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.copy, size: iconSize),
                  onPressed: _copyCode,
                  tooltip: 'Copy Code',
                  padding: EdgeInsets.all(4),
                  constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                ),
                IconButton(
                  icon: Icon(Icons.clear_all, size: iconSize),
                  onPressed: _clearCode,
                  tooltip: 'Clear Code',
                  padding: EdgeInsets.all(4),
                  constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ],
            ),
          ),
          Expanded(
            child: CodeTheme(
              data: CodeThemeData(
                styles: _isDarkMode ? atomOneDarkTheme : githubTheme,
              ),
              child: SingleChildScrollView(
                child: CodeField(
                  controller: _codeController,
                  textStyle: TextStyle(
                    fontFamily: 'SourceCodePro',
                    fontSize: bodyFontSize,
                    color: _isDarkMode ? Colors.white : Colors.black,
                  ),
                  minLines: 10,
                  maxLines: 1000,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOutputTab(bool isSmallScreen, double bodyFontSize, double iconSize) {
    return Container(
      color: _isDarkMode ? Colors.grey[900] : Colors.grey[100],
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
            color: _isDarkMode ? Colors.grey[800] : Colors.grey[200],
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Output',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: bodyFontSize,
                      color: _isDarkMode ? Colors.white : Colors.black,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.content_copy, size: iconSize),
                  onPressed: _copyOutput,
                  tooltip: 'Copy Output',
                  padding: EdgeInsets.all(4),
                  constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                ),
                IconButton(
                  icon: Icon(Icons.clear_all, size: iconSize),
                  onPressed: _clearOutput,
                  tooltip: 'Clear Output',
                  padding: EdgeInsets.all(4),
                  constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
              child: SingleChildScrollView(
                child: SelectableText(
                  _output.isEmpty
                      ? 'Output will appear here after running code...\n\n💡 Tip: Click the "Run" button to execute your code'
                      : _output,
                  style: TextStyle(
                    fontFamily: 'SourceCodePro',
                    fontSize: bodyFontSize,
                    color: _isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesTab(bool isSmallScreen, bool isVerySmallScreen, double bodyFontSize, double iconSize, double buttonPadding) {
    return Container(
      color: _isDarkMode ? Colors.grey[900] : Colors.grey[100],
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
            color: _isDarkMode ? Colors.grey[800] : Colors.grey[200],
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Saved Files',
                    style: TextStyle(
                      fontSize: bodyFontSize,
                      fontWeight: FontWeight.bold,
                      color: _isDarkMode ? Colors.white : Colors.black,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.refresh, size: iconSize),
                  onPressed: _loadAllRooms,
                  tooltip: 'Refresh Files',
                  padding: EdgeInsets.all(4),
                  constraints: BoxConstraints(minWidth: 40, minHeight: 40),
                ),
                if (!isVerySmallScreen)
                  Padding(
                    padding: EdgeInsets.only(left: buttonPadding),
                    child: ElevatedButton.icon(
                      onPressed: _saveAsNewRoom,
                      icon: Icon(Icons.save, size: iconSize),
                      label: Text(isSmallScreen ? 'Save As' : 'Save Current As New'),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _isLoadingRooms
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _isDarkMode ? Colors.white : Colors.blue,
                      ),
                    ),
                  )
                : _savedRooms.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open,
                              size: isSmallScreen ? 48 : 64,
                              color: _isDarkMode ? Colors.grey[600] : Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No saved files yet',
                              style: TextStyle(
                                fontSize: bodyFontSize,
                                color: _isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'Save your current code to get started',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 12 : 14,
                                  color: _isDarkMode ? Colors.grey[500] : Colors.grey[500],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton.icon(
                              onPressed: _startNewFile,
                              icon: Icon(Icons.add),
                              label: Text('Create New File'),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _savedRooms.length,
                        itemBuilder: (context, index) {
                          final room = _savedRooms[index];
                          final isCurrentRoom = room['room_id'] == widget.roomId;

                          return Card(
                            margin: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 8 : 12,
                              vertical: 4,
                            ),
                            color: _isDarkMode
                                ? (isCurrentRoom ? Colors.blue[900] : Colors.grey[800])
                                : (isCurrentRoom ? Colors.blue[50] : Colors.white),
                            child: ListTile(
                              leading: Icon(
                                _getFileIcon(room['language']),
                                color: _isDarkMode ? Colors.white : Colors.blue,
                                size: iconSize,
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      room['title'] ?? 'Untitled',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: bodyFontSize,
                                        color: _isDarkMode ? Colors.white : Colors.black,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isCurrentRoom)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        'Current',
                                        style: TextStyle(
                                          fontSize: isSmallScreen ? 8 : 10,
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (room['description'] != null && room['description'].isNotEmpty)
                                    Text(
                                      room['description'],
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 10 : 12,
                                        color: _isDarkMode ? Colors.grey[300] : Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  Text(
                                    '${_getLanguageDisplayName(room['language'] ?? 'unknown')} • ${_formatDate(room['updated_at'])}',
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 10 : 12,
                                      color: _isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                              trailing: isCurrentRoom
                                  ? IconButton(
                                      icon: Icon(Icons.info, size: iconSize),
                                      onPressed: () => _updateRoomInfo(),
                                      tooltip: 'Edit File Info',
                                    )
                                  : PopupMenuButton<String>(
                                      icon: Icon(Icons.more_vert, size: iconSize - 4),
                                      onSelected: (value) {
                                        if (value == 'load') {
                                          _openExistingFile(room);
                                        } else if (value == 'delete') {
                                          _deleteRoom(room);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'load',
                                          child: ListTile(
                                            leading: Icon(Icons.open_in_browser),
                                            title: Text('Open'),
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: ListTile(
                                            leading: Icon(Icons.delete, color: Colors.red),
                                            title: Text('Delete'),
                                          ),
                                        ),
                                      ],
                                    ),
                              onTap: () => _openExistingFile(room),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String language) {
    switch (language) {
      case 'python':
        return Icons.terminal;
      case 'java':
        return Icons.coffee;
      case 'csharp':
        return Icons.code;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.month}/${date.day}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'Unknown date';
    }
  }
}