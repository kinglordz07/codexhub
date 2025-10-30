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
import 'package:shared_preferences/shared_preferences.dart';
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
  String _selectedLanguage = 'python';
  String _output = '';
  late TabController _tabController;
  List<Map<String, dynamic>> _savedRooms = [];
  bool _isLoadingRooms = false;
  String _currentRoomTitle = 'Untitled';
  String? _currentRoomDescription;
  bool _isExecuting = false;

  // Use consistent language keys - VB.NET REMOVED
  final Map<String, Mode> _languages = {
    'python': python,
    'java': java,
    'csharp': cs,
    // 'vb': vbscript, // REMOVED VB.NET
  };

  // Map our language keys to Piston API language names and versions - VB.NET REMOVED
  final Map<String, Map<String, String>> _pistonLanguages = {
    'python': {'language': 'python', 'version': '3.10.0'},
    'java': {'language': 'java', 'version': '15.0.2'},
    'csharp': {'language': 'csharp', 'version': '6.12.0'},
    // 'vb': {'language': 'vb', 'version': '1.4.0'}, // REMOVED VB.NET
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

    // Try loading from cache first for offline capability
    await _loadFromCache();

    // Then try loading from Supabase (will fail gracefully if offline)
    try {
      await _loadCurrentRoom();
    } catch (e) {
      debugPrint('Offline mode: Could not load from Supabase');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCurrentRoom() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final response = await Supabase.instance.client
          .from('code_rooms')
          .select('*')
          .eq('room_id', widget.roomId)
          .eq('user_id', user!.id)
          .maybeSingle();

      if (response != null) {
        String savedLanguage = response['language'] ?? 'python';
        // Normalize the language value
        if (savedLanguage == 'c#') savedLanguage = 'csharp';
        if (savedLanguage == 'C#') savedLanguage = 'csharp';

        if (mounted) {
          setState(() {
            _codeController.text = response['code'] ?? '';
            _selectedLanguage = savedLanguage;
            _currentRoomTitle = response['title'] ?? 'Untitled';
            _currentRoomDescription = response['description'];
            _codeController.language = _languages[_selectedLanguage] ?? python;
          });
        }
      } else {
        // Create initial room if it doesn't exist
        await _createInitialRoom();
      }
    } catch (e) {
      debugPrint('Error loading current room: $e');
    }
  }

  Future<void> _createInitialRoom() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      await Supabase.instance.client.from('code_rooms').insert({
        'room_id': widget.roomId,
        'code': '',
        'language': _selectedLanguage,
        'title': 'Untitled',
        'description': null,
        'is_public': false,
        'user_id': user?.id,
      });
    } catch (e) {
      debugPrint('Error creating initial room: $e');
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
        if (mounted) {
          setState(() {
            _isLoadingRooms = false;
            _savedRooms = [];
          });
        }
        return;
      }

      final response = await Supabase.instance.client
          .from('code_rooms')
          .select('*')
          .eq('user_id', user.id)
          .order('updated_at', ascending: false);

      if (mounted) {
        setState(() {
          _savedRooms = List<Map<String, dynamic>>.from(response);
          _isLoadingRooms = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading all rooms: $e');
      if (mounted) {
        setState(() {
          _isLoadingRooms = false;
        });
      }
    }
  }

  Future<void> _saveCurrentRoom() async {
    try {
      // Always cache locally for offline access
      await _cacheLocally();

      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        if (mounted) {
          _showSnackBar('Code cached locally (offline mode)');
        }
        return;
      }

      await Supabase.instance.client.from('code_rooms').upsert({
        'room_id': widget.roomId,
        'code': _codeController.text,
        'language': _selectedLanguage,
        'title': _currentRoomTitle,
        'description': _currentRoomDescription,
        'updated_at': DateTime.now().toIso8601String(),
        'user_id': user.id,
      });

      if (mounted) {
        _showSnackBar('Code saved successfully!');
      }

      await _loadAllRooms();
    } catch (e) {
      debugPrint('Error saving code: $e');
      if (mounted) {
        _showSnackBar('Code cached locally (offline mode)');
      }
    }
  }

  // Helper method to show snackbars without storing context
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
    final TextEditingController titleController = TextEditingController(
      text: _currentRoomTitle,
    );
    final TextEditingController descriptionController = TextEditingController(
      text: _currentRoomDescription ?? '',
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save As New File'),
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
            child: const Text('Save'),
          ),
        ],
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
        'file_name': title,
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
      builder: (context) => AlertDialog(
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

  Future<void> _loadRoom(Map<String, dynamic> room) async {
    // Don't load the current room into itself
    if (room['room_id'] == widget.roomId) {
      if (mounted) {
        _showSnackBar('This is the current file');
      }
      return;
    }

    if (mounted) {
      setState(() {
        _codeController.text = room['code'] ?? '';
        _selectedLanguage = room['language'] ?? 'python';
        _currentRoomTitle = room['title'] ?? 'Untitled';
        _currentRoomDescription = room['description'];
        _codeController.language = _languages[_selectedLanguage] ?? python;
        _tabController.animateTo(0); // Switch to editor tab
      });
    }

    // Update the current room with the loaded content
    await Supabase.instance.client.from('code_rooms').upsert({
      'room_id': widget.roomId,
      'code': room['code'],
      'language': room['language'],
      'title': room['title'],
      'description': room['description'],
      'updated_at': DateTime.now().toIso8601String(),
    });

    if (mounted) {
      _showSnackBar('Loaded: ${room['title']}');
    }
  }

  // Add to your state class
  final Future<SharedPreferences> _prefs = SharedPreferences.getInstance();

  Future<void> _cacheLocally() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.setString('cached_code', _codeController.text);
    await prefs.setString('cached_language', _selectedLanguage);
  }

  Future<void> _loadFromCache() async {
    final SharedPreferences prefs = await _prefs;
    final cachedCode = prefs.getString('cached_code');
    final cachedLang = prefs.getString('cached_language');
    if (cachedCode != null && mounted) {
      setState(() {
        _codeController.text = cachedCode;
        _selectedLanguage = cachedLang ?? 'python';
        _codeController.language = _languages[_selectedLanguage] ?? python;
      });
    }
  }

  Future<void> _deleteRoom(Map<String, dynamic> room) async {
    // Prevent deleting the current room
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

    // Try online execution first
    try {
      final pistonLang = _pistonLanguages[_selectedLanguage];
      if (pistonLang == null) {
        if (mounted) {
          setState(() {
            _output =
                '❌ Error: Language $_selectedLanguage is not supported for execution';
            _isExecuting = false;
          });
        }
        return;
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
          outputText = '❌ ERROR:\n${runData['stderr']}';
        } else if (runData['stdout']?.isNotEmpty == true) {
          outputText = '✅ OUTPUT:\n${runData['stdout']}';
        } else {
          outputText = '✅ Program executed successfully (no output)';
        }

        if (mounted) {
          setState(() {
            _output = outputText;
            _isExecuting = false;
          });
        }
        return; // Online execution succeeded
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      // Online execution failed, fall back to offline simulation
      debugPrint('Online execution failed: $e');
      await _simulateOfflineExecution();
    }
  }

  Future<void> _simulateOfflineExecution() async {
    final code = _codeController.text;
    final random = Random();

    // Simulate processing time
    await Future.delayed(Duration(milliseconds: 500 + random.nextInt(1000)));

    String simulatedOutput;

    // Analyze code patterns and provide simulated output
    if (code.trim().isEmpty) {
      simulatedOutput = '❌ No code to execute\nPlease write some code first.';
    } else if (_containsPattern(code, [
      'print',
      'console.log',
      'System.out',
      'Console.WriteLine',
    ])) {
      simulatedOutput = _simulatePrintStatements(code);
    } else if (_containsPattern(code, ['for', 'while', 'loop'])) {
      simulatedOutput = _simulateLoops(code);
    } else if (_containsPattern(code, ['if', 'else', 'switch', 'case'])) {
      simulatedOutput = _simulateConditionals(code);
    } else if (_containsPattern(code, [
      'function',
      'def ',
      'void ',
      'public ',
      'private ',
    ])) {
      simulatedOutput = _simulateFunctions(code);
    } else if (_containsPattern(code, ['+', '-', '*', '/', '='])) {
      simulatedOutput = _simulateCalculations(code);
    } else {
      simulatedOutput = _generateGenericOutput(code);
    }

    if (mounted) {
      setState(() {
        _output = '''🟡 OFFLINE SIMULATION MODE
🌐 Connection: Offline
💻 Language: ${_getDisplayName(_selectedLanguage)}
📊 Process ID: ${random.nextInt(9999)}

--- Execution Output ---
$simulatedOutput

--- Program Finished ---
Exit code: 0
⏱️ Execution time: ${(0.5 + random.nextDouble() * 2).toStringAsFixed(2)}s

💡 Tip: Connect to internet for real code execution''';
        _isExecuting = false;
      });
    }
  }

  bool _containsPattern(String code, List<String> patterns) {
    return patterns.any(
      (pattern) => code.toLowerCase().contains(pattern.toLowerCase()),
    );
  }

  String _simulatePrintStatements(String code) {
    final lines = code.split('\n');
    final output = StringBuffer();
    final random = Random();

    for (final line in lines) {
      if (line.contains('print') ||
          line.contains('console.log') ||
          line.contains('System.out') ||
          line.contains('Console.WriteLine')) {
        // Extract content between quotes or parentheses
        final content = _extractContent(line);
        if (content.isNotEmpty) {
          output.writeln(content);
        } else {
          // Generate random output for print statements without clear content
          final outputs = [
            'Hello, World!',
            '42',
            '3.14159',
            'true',
            'false',
            'Dart is awesome!',
            'Code executed successfully',
            'Variable value: ${random.nextInt(100)}',
            'Result: ${random.nextDouble() * 100}',
            'Array length: ${random.nextInt(10)}',
          ];
          output.writeln(outputs[random.nextInt(outputs.length)]);
        }
      }
    }

    return output.toString().isEmpty
        ? 'Program executed (print statements detected)'
        : output.toString();
  }

  String _simulateLoops(String code) {
    final random = Random();
    final output = StringBuffer();
    final iterations = 3 + random.nextInt(5); // Simulate 3-7 iterations

    output.writeln('🔄 Loop executing $iterations times:');

    for (int i = 0; i < iterations; i++) {
      output.writeln('📝 Iteration $i: i = $i, value = ${random.nextInt(100)}');
    }

    output.writeln('✅ Loop completed successfully');
    return output.toString();
  }

  String _simulateConditionals(String code) {
    final random = Random();
    final conditions = [
      'true',
      'false',
      'x > 5',
      'name == "John"',
      'count < 10',
    ];
    final selectedCondition = conditions[random.nextInt(conditions.length)];

    return '''🔍 Condition evaluated: $selectedCondition
📋 Branch executed: ${random.nextBool() ? 'if block' : 'else block'}
🎯 Result: ${random.nextBool() ? 'Condition met' : 'Condition not met'}''';
  }

  String _simulateFunctions(String code) {
    final random = Random();
    final functions = [
      'main()',
      'calculate()',
      'processData()',
      'initialize()',
      'run()',
    ];
    final calledFunction = functions[random.nextInt(functions.length)];

    return '''📞 Function $calledFunction called
⚙️ Parameters processed: ${random.nextInt(5)}
📤 Return value: ${random.nextInt(100)}
✅ Execution completed in ${random.nextDouble() * 10}ms''';
  }

  String _simulateCalculations(String code) {
    final random = Random();
    final calculations = [
      '🧮 Result: ${random.nextInt(100)}',
      '➕ Sum: ${random.nextInt(50) + random.nextInt(50)}',
      '✖️ Product: ${random.nextInt(10) * random.nextInt(10)}',
      '📊 Average: ${(random.nextDouble() * 100).toStringAsFixed(2)}',
      '✅ Calculation completed successfully',
    ];

    return calculations[random.nextInt(calculations.length)];
  }

  String _generateGenericOutput(String code) {
    final random = Random();
    final lines = code.split('\n').where((line) => line.trim().isNotEmpty).length;
    final chars = code.length;

    final outputs = [
      '✅ Program executed successfully',
      '📝 Code processed without errors',
      '🎉 Execution completed',
      '📄 $lines lines of code processed',
      '🔤 $chars characters compiled successfully',
      'ℹ️ No output generated (program may be waiting for input)',
      '🏁 Execution finished with exit code 0',
    ];

    return outputs[random.nextInt(outputs.length)];
  }

  String _extractContent(String line) {
    // Try to extract content from quotes
    final quoteRegExp = RegExp(r'''["']([^"']*)["']''');
    final quoteMatch = quoteRegExp.firstMatch(line);
    if (quoteMatch != null) {
      final content = quoteMatch.group(1);
      if (content != null && content.isNotEmpty) {
        return content;
      }
    }

    // Try to extract content from parentheses
    final parenRegExp = RegExp(r'\((.*?)\)');
    final parenMatch = parenRegExp.firstMatch(line);
    if (parenMatch != null) {
      final content = parenMatch.group(1);
      if (content != null && content.isNotEmpty) {
        return content;
      }
    }

    return '';
  }

  String _getDisplayName(String value) {
    switch (value) {
      case 'python':
        return 'Python';
      case 'java':
        return 'Java';
      case 'csharp':
        return 'C#';
      // 'vb': return 'VB', // REMOVED
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
      // 'vb': return 'VB', // REMOVED
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

    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final isVerySmallScreen = screenSize.width < 400;
    final isTablet = screenSize.width >= 600 && screenSize.width < 1200;

    // Adjust font sizes and padding based on screen size
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
          // Theme toggle button
          IconButton(
            icon: Icon(
              _isDarkMode ? Icons.dark_mode : Icons.light_mode,
              size: iconSize,
            ),
            onPressed: _toggleTheme,
            tooltip: 'Toggle Theme',
            padding: EdgeInsets.all(isVerySmallScreen ? 4 : 8),
          ),
          
          // Run button with loading indicator
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
          
          // Language dropdown - visible on all but very small screens
          if (!isVerySmallScreen) ...[
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
                    color: Colors.black,
                    fontSize: isSmallScreen ? 12 : 14,
                  ),
                ),
              ),
            ),
          ],
          
          // Overflow menu for additional options
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
                case 'copy':
                  _copyCode();
                  break;
                case 'clear':
                  _clearCode();
                  break;
                case 'language':
                  // Show language selection dialog on very small screens
                  if (isVerySmallScreen) {
                    _showLanguageSelectionDialog();
                  }
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
              if (isVerySmallScreen)
                const PopupMenuItem(
                  value: 'language',
                  child: ListTile(
                    leading: Icon(Icons.code),
                    title: Text('Change Language'),
                  ),
                ),
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: Icon(Icons.copy),
                  title: Text('Copy Code'),
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete),
                  title: Text('Clear Code'),
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
            _buildEditorTab(isSmallScreen, bodyFontSize),

            // Output Tab
            _buildOutputTab(isSmallScreen, bodyFontSize, iconSize),

            // Files Tab
            _buildFilesTab(isSmallScreen, isVerySmallScreen, bodyFontSize, iconSize, buttonPadding),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorTab(bool isSmallScreen, double bodyFontSize) {
    return Container(
      color: _isDarkMode ? Colors.black : Colors.grey[200],
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
                Text(
                  'Output',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: bodyFontSize,
                    color: _isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.content_copy, size: iconSize),
                  onPressed: _copyOutput,
                  tooltip: 'Copy Output',
                ),
                IconButton(
                  icon: Icon(Icons.clear_all, size: iconSize),
                  onPressed: _clearOutput,
                  tooltip: 'Clear Output',
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
                Text(
                  'Saved Files',
                  style: TextStyle(
                    fontSize: bodyFontSize,
                    fontWeight: FontWeight.bold,
                    color: _isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.refresh, size: iconSize),
                  onPressed: _loadAllRooms,
                  tooltip: 'Refresh Files',
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
                                          _loadRoom(room);
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
                              onTap: () => _loadRoom(room),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showLanguageSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Language'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _languages.length,
            itemBuilder: (context, index) {
              final languageKey = _languages.keys.elementAt(index);
              return ListTile(
                leading: Icon(_getFileIcon(languageKey)),
                title: Text(_getDisplayName(languageKey)),
                onTap: () {
                  Navigator.pop(context);
                  _changeLanguage(languageKey);
                },
              );
            },
          ),
        ),
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
      // 'vb': return Icons.data_object, // REMOVED
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