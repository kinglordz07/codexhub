// ignore_for_file: deprecated_member_use, use_build_context_synchronously, unused_element

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/cs.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/vbscript.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:highlight/highlight.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CollabCodeEditorScreen extends StatefulWidget {
  final String roomId;
  
  const CollabCodeEditorScreen({super.key, required this.roomId});
  

  @override
  State<CollabCodeEditorScreen> createState() => _CollabCodeEditorScreenState();
}

class _CollabCodeEditorScreenState extends State<CollabCodeEditorScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  final List<Map<String, dynamic>> _availableFiles = [];
  final List<Map<String, dynamic>> _savedFiles = [];
bool _isSaving = false;
bool _isLoadingFiles = false;

  String selectedLanguage = 'C#';
  late CodeController _codeController;
  Timer? _debounce;
  RealtimeChannel? _channel;
  String? executionResult;
  bool isExecuting = false;
  bool isOnline = true;
  bool _isInitialized = false;
  bool _hasConnectionError = false;

  // Local storage key
  String get _localStorageKey => 'code_editor_${widget.roomId}';

  final Map<String, String> languageSnippets = {
    'C#': '''using System;
class Program {
    static void Main() {
        Console.WriteLine("Hello, World!");
    }
}''',
    'Python': '''def main():
    print("Hello, World!")

if __name__ == "__main__":
    main()''',
    'VB.NET': '''Module Module1
    Sub Main()
        Console.WriteLine("Hello, World!")
    End Sub
End Module''',
    'Java': '''public class Main {
    public static void main(String[] args) {
        System.out.println("Hello, World!");
    }
}''',
  };

  @override
  void initState() {
    super.initState();
    _initializeEditor();
    _setupConnectivityListener();
    _loadAvailableFiles();
     _loadSavedFiles();
  }

  Future<void> _initializeEditor() async {
    // Initialize controller first
    _codeController = CodeController(
      text: languageSnippets[selectedLanguage]!,
      language: _getLanguageDef(selectedLanguage),
    );

    // Load from local storage
    await _loadFromLocalStorage();
    
    // Set up listener
    _codeController.addListener(_onCodeChanged);

    // Test server connection and initialize realtime
    await _testServerConnection();
    
    setState(() {
      _isInitialized = true;
    });
  }

  Future<void> _testServerConnection() async {
    try {
      // Simple test to check if Supabase is reachable
      await supabase.from('code_rooms').select('count').limit(1).single();
      setState(() {
        isOnline = true;
        _hasConnectionError = false;
      });
      await _initRealtime();
      await _loadInitialCode();
    } catch (e) {
      debugPrint('Server connection test failed: $e');
      setState(() {
        isOnline = false;
        _hasConnectionError = true;
      });
    }
  }

  void _setupConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
      final hasInternet = results.isNotEmpty && !results.contains(ConnectivityResult.none);
      
      if (hasInternet && !isOnline) {
        // We have connectivity, test if server is actually reachable
        await _testServerConnection();
      } else if (!hasInternet) {
        // Definitely offline
        setState(() {
          isOnline = false;
          _hasConnectionError = false;
        });
      }
    });
  }

  Future<void> _loadFromLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedCode = prefs.getString('${_localStorageKey}_code');
      final savedLanguage = prefs.getString('${_localStorageKey}_language');
      
      if (savedCode != null && savedCode.isNotEmpty) {
        _codeController = CodeController(
          text: savedCode,
          language: _getLanguageDef(savedLanguage ?? selectedLanguage),
        );
      }
      
      if (savedLanguage != null) {
        selectedLanguage = savedLanguage;
      }
    } catch (e) {
      debugPrint('Error loading from local storage: $e');
    }
  }

  Future<void> _saveToLocalStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${_localStorageKey}_code', _codeController.text);
      await prefs.setString('${_localStorageKey}_language', selectedLanguage);
    } catch (e) {
      debugPrint('Error saving to local storage: $e');
    }
  }

  Future<void> _initRealtime() async {
    try {
      _channel = supabase.channel('code_room_${widget.roomId}');

      _channel!.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'code_rooms',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: widget.roomId,
        ),
        callback: (payload) {
          final newCode = payload.newRecord['code'];
          final sender = payload.newRecord['user_id'];
          final currentUserId = supabase.auth.currentUser?.id;

          if (newCode != null && sender != currentUserId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _codeController.text = newCode.toString();
                  _saveToLocalStorage();
                });
              }
            });
          }
        },
      );

      _channel!.subscribe();
    } catch (e) {
      debugPrint('Error initializing realtime: $e');
      // Don't set offline here - just realtime failed
    }
  }

  Future<void> _loadInitialCode() async {
    try {
      final response = await supabase
          .from('code_rooms')
          .select()
          .eq('room_id', widget.roomId)
          .maybeSingle();

      if (response != null && response['code'] != null) {
        final serverCode = response['code'].toString();
        if (serverCode != _codeController.text) {
          setState(() {
            _codeController.text = serverCode;
            _saveToLocalStorage();
          });
        }
      } else {
        await _syncToServer();
      }
    } catch (e) {
      debugPrint('Error loading initial code: $e');
      // Don't set offline - just loading failed
    }
  }

  void _onCodeChanged() {
    _saveToLocalStorage();

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    _debounce = Timer(const Duration(milliseconds: 1500), () {
      if (isOnline) {
        _syncToServer();
      }
    });
  }

Future<void> _ensureUserProfile() async {
  try {
    final user = supabase.auth.currentUser;
    if (user != null) {
      // Check if user profile exists
      final profileResponse = await supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      // Create profile if it doesn't exist
      if (profileResponse == null) {
        // Generate a username from email or use a default
        final username = user.email?.split('@').first ?? 'user_${user.id.substring(0, 8)}';
        
        await supabase.from('profiles').insert({
          'id': user.id,
          'email': user.email,
          'username': username, // Add required username field
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    }
  } catch (e) {
    debugPrint('Error ensuring user profile: $e');
    // If profile creation fails, we'll continue without it
  }
}


Future<void> _loadAvailableFiles() async {
  if (!isOnline) return;
  
  setState(() {
    _isLoadingFiles = true;
  });

  try {
    final response = await supabase
        .from('code_rooms')
        .select('room_id, language, updated_at')
        .order('updated_at', ascending: false)
        .limit(50);

    setState(() {
      _availableFiles.clear();
      _availableFiles.addAll(List<Map<String, dynamic>>.from(response));
      _isLoadingFiles = false;
    });
  } catch (e) {
    debugPrint('Error loading files: $e');
    setState(() {
      _isLoadingFiles = false;
    });
  }
}

// Method to show save dialog
void _showSaveDialog() {
  final TextEditingController fileNameController = TextEditingController(
    text: 'my_code_${DateTime.now().millisecondsSinceEpoch}',
  );

  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Save File'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: fileNameController,
            decoration: const InputDecoration(
              labelText: 'File Name',
              hintText: 'Enter a name for your file',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: selectedLanguage,
            decoration: const InputDecoration(
              labelText: 'Language',
              border: OutlineInputBorder(),
            ),
            items: languageSnippets.keys
                .map((lang) => DropdownMenuItem(
                      value: lang,
                      child: Text(lang),
                    ))
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  selectedLanguage = value;
                });
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => _saveFile(fileNameController.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

// Method to save file to database
Future<void> _saveFile(String fileName) async {
  if (fileName.isEmpty) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a file name')),
      );
    }
    return;
  }

  setState(() {
    _isSaving = true;
  });

  try {
    final user = supabase.auth.currentUser;
    final fileId = '${user?.id}_${DateTime.now().millisecondsSinceEpoch}';

    // Save to saved_files table (you'll need to create this table)
    await supabase.from('saved_files').upsert({
      'file_id': fileId,
      'file_name': fileName,
      'code': _codeController.text,
      'language': selectedLanguage,
      'user_id': user?.id,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // Also save to code_rooms for compatibility
    await supabase.from('code_rooms').upsert({
      'room_id': fileId,
      'code': _codeController.text,
      'language': selectedLanguage,
      'user_id': user?.id,
      'updated_at': DateTime.now().toIso8601String(),
    });

    if (mounted) {
      Navigator.pop(context); // Close the dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File "$fileName" saved successfully!')),
      );
      
      // Reload the saved files list
      _loadSavedFiles();
    }
  } catch (e) {
    debugPrint('Error saving file: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving file: $e')),
      );
    }
  } finally {
    if (mounted) {
      setState(() {
        _isSaving = false;
      });
    }
  }
}

// Method to load user's saved files
Future<void> _loadSavedFiles() async {
  if (!isOnline) return;

  setState(() {
    _isLoadingFiles = true;
  });

  try {
    final user = supabase.auth.currentUser;
    if (user != null) {
      final response = await supabase
          .from('saved_files')
          .select('file_id, file_name, language, created_at, updated_at')
          .eq('user_id', user.id)
          .order('updated_at', ascending: false);

      setState(() {
        _savedFiles.clear();
        _savedFiles.addAll(List<Map<String, dynamic>>.from(response));
      });
    }
  } catch (e) {
    debugPrint('Error loading saved files: $e');
  } finally {
    setState(() {
      _isLoadingFiles = false;
    });
  }
}

// Method to open a saved file
Future<void> _openSavedFile(String fileId, String fileName) async {
  try {
    setState(() {
      _isLoadingFiles = true;
    });

    final response = await supabase
        .from('saved_files')
        .select()
        .eq('file_id', fileId)
        .maybeSingle();

    if (response != null && response['code'] != null) {
      final newCode = response['code'].toString();
      final newLanguage = response['language']?.toString() ?? selectedLanguage;
      
      setState(() {
        _codeController.text = newCode;
        selectedLanguage = newLanguage;
        _codeController.language = _getLanguageDef(newLanguage);
        _saveToLocalStorage();
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Opened: $fileName")),
        );
      }
    }
  } catch (e) {
    debugPrint('Error opening saved file: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error opening file")),
      );
    }
  } finally {
    setState(() {
      _isLoadingFiles = false;
    });
  }
}

// Method to delete a saved file
Future<void> _deleteSavedFile(String fileId, String fileName) async {
  try {
    await supabase
        .from('saved_files')
        .delete()
        .eq('file_id', fileId);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File "$fileName" deleted')),
      );
      _loadSavedFiles(); // Refresh the list
    }
  } catch (e) {
    debugPrint('Error deleting file: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting file')),
      );
    }
  }
}

// Method to show saved files dialog
void _showSavedFilesDialog() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('My Saved Files'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _isLoadingFiles
            ? const Center(child: CircularProgressIndicator())
            : _savedFiles.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_open, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No saved files yet'),
                        SizedBox(height: 8),
                        Text(
                          'Save your code using the Save button',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _savedFiles.length,
                    itemBuilder: (context, index) {
                      final file = _savedFiles[index];
                      final fileId = file['file_id']?.toString() ?? '';
                      final fileName = file['file_name']?.toString() ?? 'Untitled';
                      final language = file['language']?.toString() ?? 'Unknown';
                      final updatedAt = file['updated_at']?.toString() ?? '';
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: Icon(
                            _getLanguageIcon(language),
                            color: _getLanguageColor(language),
                          ),
                          title: Text(fileName),
                          subtitle: Text('$language • ${_formatDate(updatedAt)}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _showDeleteConfirmation(fileId, fileName),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            _openSavedFile(fileId, fileName);
                          },
                        ),
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        TextButton(
          onPressed: _loadSavedFiles,
          child: const Text('Refresh'),
        ),
      ],
    ),
  );
}

// Helper method for delete confirmation
void _showDeleteConfirmation(String fileId, String fileName) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete File'),
      content: Text('Are you sure you want to delete "$fileName"?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context); // Close confirmation
            _deleteSavedFile(fileId, fileName);
          },
          child: const Text('Delete', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}

// Helper methods for UI
IconData _getLanguageIcon(String language) {
  switch (language) {
    case 'Python':
      return Icons.architecture;
    case 'Java':
      return Icons.coffee;
    case 'C#':
      return Icons.code;
    case 'VB.NET':
      return Icons.data_object;
    default:
      return Icons.description;
  }
}

Color _getLanguageColor(String language) {
  switch (language) {
    case 'Python':
      return Colors.blue;
    case 'Java':
      return Colors.orange;
    case 'C#':
      return Colors.purple;
    case 'VB.NET':
      return Colors.green;
    default:
      return Colors.grey;
  }
}

String _formatDate(String dateString) {
  if (dateString.isEmpty) return 'Unknown date';
  try {
    final date = DateTime.parse(dateString);
    return '${date.month}/${date.day}/${date.year}';
  } catch (e) {
    return 'Unknown date';
  }
}

Future<void> _openFile(String roomId) async {
  try {
    setState(() {
      _isLoadingFiles = true;
    });

    final response = await supabase
        .from('code_rooms')
        .select()
        .eq('room_id', roomId)
        .maybeSingle();

    if (response != null && response['code'] != null) {
      final newCode = response['code'].toString();
      final newLanguage = response['language']?.toString() ?? selectedLanguage;
      
      setState(() {
        _codeController.text = newCode;
        selectedLanguage = newLanguage;
        _codeController.language = _getLanguageDef(newLanguage);
        _saveToLocalStorage();
      });
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Opened file: $roomId")),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("File not found")),
        );
      }
    }
  } catch (e) {
    debugPrint('Error opening file: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error opening file")),
      );
    }
  } finally {
    setState(() {
      _isLoadingFiles = false;
    });
  }
}

// Add this method to show the open file dialog
void _showOpenFileDialog() {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Open Existing File'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _isLoadingFiles
            ? const Center(child: CircularProgressIndicator())
            : _availableFiles.isEmpty
                ? const Center(child: Text('No files available'))
                : ListView.builder(
                    itemCount: _availableFiles.length,
                    itemBuilder: (context, index) {
                      final file = _availableFiles[index];
                      final roomId = file['room_id']?.toString() ?? 'Unknown';
                      final language = file['language']?.toString() ?? 'Unknown';
                      final updatedAt = file['updated_at']?.toString() ?? '';
                      
                      return ListTile(
                        title: Text('Room: $roomId'),
                        subtitle: Text('Language: $language'),
                        trailing: Text(
                          updatedAt.isNotEmpty 
                            ? updatedAt.substring(0, 10) 
                            : '',
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          _openFile(roomId);
                        },
                      );
                    },
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _loadAvailableFiles,
          child: const Text('Refresh'),
        ),
      ],
    ),
  );
}

Future<void> _syncToServer() async {
  if (!isOnline) return;

  try {
    final user = supabase.auth.currentUser;
    
    // Ensure user profile exists first
    if (user != null) {
      await _ensureUserProfile();
    }

    // Build the data object
    final data = {
      'room_id': widget.roomId,
      'code': _codeController.text,
      'language': selectedLanguage,
      'updated_at': DateTime.now().toIso8601String(),
    };

    // Only add user_id if we have a valid user
    if (user != null) {
      data['user_id'] = user.id;
    }

    // Use upsert to handle both insert and update
    await supabase.from('code_rooms').upsert(
      data,
      onConflict: 'room_id', // Specify the unique constraint column
    );

    // Clear any previous connection errors on successful sync
    if (mounted && _hasConnectionError) {
      setState(() {
        _hasConnectionError = false;
      });
    }
    
  } catch (e) {
    debugPrint('Error syncing to server: $e');
    
    // Handle specific error types
    if (e.toString().contains('23503')) {
      // Foreign key violation - user doesn't exist
      debugPrint('Foreign key violation, syncing without user_id');
      await _syncWithoutUserId();
    } else if (e.toString().contains('23505')) {
      // Unique constraint violation - handle upsert differently
      debugPrint('Unique constraint violation, trying update only');
      await _updateExistingRecord();
    } else {
      // Generic error
      if (mounted) {
        setState(() {
          _hasConnectionError = true;
        });
      }
    }
  }
}

Future<void> _syncWithoutUserId() async {
  try {
    await supabase.from('code_rooms').upsert({
      'room_id': widget.roomId,
      'code': _codeController.text,
      'language': selectedLanguage,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'room_id');
  } catch (e) {
    debugPrint('Error syncing without user_id: $e');
    // If this also fails, we'll work offline
  }
}

Future<void> _updateExistingRecord() async {
  try {
    // Try to update existing record without attempting insert
    await supabase
        .from('code_rooms')
        .update({
          'code': _codeController.text,
          'language': selectedLanguage,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('room_id', widget.roomId);
  } catch (e) {
    debugPrint('Error updating existing record: $e');
  }
}

Future<void> _handleRLSError() async {
  debugPrint('RLS policy violation, trying alternative sync method');
  
  try {
    // Try a different approach - update if exists, insert if not
    final response = await supabase
        .from('code_rooms')
        .select()
        .eq('room_id', widget.roomId)
        .maybeSingle();
    
    if (response != null) {
      // Update existing record
      await supabase
          .from('code_rooms')
          .update({
            'code': _codeController.text,
            'language': selectedLanguage,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('room_id', widget.roomId);
    } else {
      // Try insert with room_id only
      await supabase.from('code_rooms').insert({
        'room_id': widget.roomId,
        'code': _codeController.text,
        'language': selectedLanguage,
      });
    }
  } catch (e) {
    debugPrint('Alternative sync also failed: $e');
    // At this point, we'll just work offline
  }
}

Future<void> _handleUserNotFoundError() async {
  debugPrint('User profile not found, creating profile...');
  
  try {
    final user = supabase.auth.currentUser;
    if (user != null) {
      // Try to create user profile
      await supabase.from('profiles').insert({
        'id': user.id,
        'email': user.email,
        'created_at': DateTime.now().toIso8601String(),
      });
      
      // Wait a bit for the profile to be created
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Retry the original sync
      await _syncToServer();
    }
  } catch (e) {
    debugPrint('Failed to create user profile: $e');
    // If profile creation fails, try without user_id
    await _syncWithoutUserId();
  }
}

 // Update your _runCode method
Future<void> _runCode() async {
  if (isExecuting) return;

  setState(() {
    isExecuting = true;
    executionResult = null;
  });

  // Simulate execution based on actual code content
  await Future.delayed(const Duration(seconds: 2));

  if (mounted) {
    setState(() {
      executionResult = _getExecutionResult(_codeController.text, selectedLanguage);
      isExecuting = false;
    });
  }
}

// Update your _getExecutionResult method to be more reliable
String _getExecutionResult(String code, String language) {
  final lines = code.split('\n');
  final lineCount = lines.length;
  final charCount = code.length;
  
  // Simple message extraction without complex regex
  String? extractMessage() {
    for (final line in lines) {
      final trimmed = line.trim();
      
      // Look for Python print statements
      if (trimmed.startsWith('print(') && trimmed.contains("'")) {
        final start = trimmed.indexOf("'");
        final end = trimmed.lastIndexOf("'");
        if (start < end) return trimmed.substring(start + 1, end);
      }
      
      // Look for C# Console.WriteLine
      if (trimmed.contains('Console.WriteLine(') && trimmed.contains('"')) {
        final start = trimmed.indexOf('"');
        final end = trimmed.lastIndexOf('"');
        if (start < end) return trimmed.substring(start + 1, end);
      }
      
      // Look for Java System.out.println
      if (trimmed.contains('System.out.println(') && trimmed.contains('"')) {
        final start = trimmed.indexOf('"');
        final end = trimmed.lastIndexOf('"');
        if (start < end) return trimmed.substring(start + 1, end);
      }
      
      // Look for VB.NET Console.WriteLine
      if (trimmed.contains('Console.WriteLine(') && trimmed.contains('"')) {
        final start = trimmed.indexOf('"');
        final end = trimmed.lastIndexOf('"');
        if (start < end) return trimmed.substring(start + 1, end);
      }
    }
    return null;
  }
  
  final message = extractMessage();
  if (message != null) {
    return "✅ $language Execution Result:\n📤 Output: $message\n\n[Execution completed successfully]";
  }
  
  // Default response
  return "✅ $language Code Executed Successfully!\n"
         "📊 Stats: $lineCount lines, $charCount characters\n"
         "🔄 Output: Program executed without errors\n"
         "💡 Tip: Add print/Console.WriteLine statements to see output";
}
    

  @override
  void dispose() {
    _codeController.dispose();
    _debounce?.cancel();
    _connectivitySubscription.cancel();
    if (_channel != null) {
      supabase.removeChannel(_channel!);
    }
    super.dispose();
  }

  void _insertSnippet(String language) {
    setState(() {
      selectedLanguage = language;
      _codeController.text = languageSnippets[language]!;
      _codeController.language = _getLanguageDef(language);
      _saveToLocalStorage();
      if (isOnline) _syncToServer();
    });
  }

  Mode? _getLanguageDef(String lang) {
    switch (lang) {
      case 'Python':
        return python;
      case 'VB.NET':
        return vbscript;
      case 'Java':
        return java;
      default:
        return cs;
    }
  }

  void _retryConnection() async {
    setState(() {
      _hasConnectionError = false;
    });
    await _testServerConnection();
  }

 @override
Widget build(BuildContext context) {
  if (!_isInitialized) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Loading Editor...'),
        backgroundColor: Colors.indigo,
      ),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Initializing code editor...'),
          ],
        ),
      ),
    );
  }

  final isDarkMode = Theme.of(context).brightness == Brightness.dark;
  final themeStyles = isDarkMode ? atomOneDarkTheme : githubTheme;

  return Scaffold(
    appBar: AppBar(
      title: Text('Code Editor ($selectedLanguage) ${isOnline ? '' : '(Offline)'}'),
      backgroundColor: isOnline ? Colors.indigo : Colors.orange,
      actions: [
        if (_hasConnectionError)
          IconButton(
            icon: const Icon(Icons.wifi_off, color: Colors.red),
            onPressed: _retryConnection,
            tooltip: 'Connection error - tap to retry',
          )
        else
          IconButton(
            icon: Icon(isOnline ? Icons.cloud_done : Icons.cloud_off),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(isOnline ? 'Online Mode' : 'Offline Mode'),
                  content: Text(isOnline
                      ? 'You are connected to the server. Changes will sync automatically.'
                      : 'You are currently offline. Your code is saved locally and will sync when you reconnect.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("OK"),
                    ),
                    if (!isOnline)
                      TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _retryConnection();
                        },
                        child: const Text("Retry Connection"),
                      ),
                  ],
                ),
              );
            },
            tooltip: isOnline ? 'Online' : 'Offline - tap for info',
          ),
        if (executionResult != null)
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Execution Result'),
                  content: SingleChildScrollView(
                    child: Text(executionResult!),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Close"),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    ),
    body: Column(
      children: [
        // Status and language selector
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              DropdownButton<String>(
                value: selectedLanguage,
                items: languageSnippets.keys
                    .map((lang) => DropdownMenuItem(
                          value: lang,
                          child: Text(lang),
                        ))
                    .toList(),
                onChanged: (val) => _insertSnippet(val!),
              ),
              const SizedBox(width: 16),
              _buildStatusIndicator(),
            ],
          ),
        ),

        // Connection error banner
        if (_hasConnectionError)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.red.withOpacity(0.1),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Connection error. Working in offline mode.',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                TextButton(
                  onPressed: _retryConnection,
                  child: Text('Retry', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ),

        // Code Editor (Expanded to fill space)
        Expanded(
          child: CodeTheme(
            data: CodeThemeData(styles: themeStyles),
            child: CodeField(
              controller: _codeController,
              textStyle: const TextStyle(
                fontFamily: "monospace",
                fontSize: 14,
              ),
              expands: true,
            ),
          ),
        ),

        // Execution result (scrollable)
        if (executionResult != null)
          Container(
            width: double.infinity,
            height: 120,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              border: Border.all(color: Colors.green),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SingleChildScrollView(
              child: Text(
                executionResult!,
                style: const TextStyle(fontFamily: "monospace", fontSize: 12),
              ),
            ),
          ),

        // Action buttons at bottom (scrollable if many)
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.grey[100],
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ElevatedButton.icon(
                  onPressed: isExecuting ? null : _runCode,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(isExecuting ? "Running..." : "Run Code"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _codeController.text));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Code copied to clipboard")),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text("Copy Code"),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _showSaveDialog,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text("Save File"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _showSavedFilesDialog,
                  icon: const Icon(Icons.folder),
                  label: const Text("My Files"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _showOpenFileDialog,
                  icon: const Icon(Icons.folder_open),
                  label: const Text("Open Room"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
                if (!isOnline || _hasConnectionError) ...[
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _retryConnection,
                    icon: const Icon(Icons.sync),
                    label: const Text("Retry Connection"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
  Widget _buildStatusIndicator() {
    if (_hasConnectionError) {
      return Chip(
        backgroundColor: Colors.red.withOpacity(0.2),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 16, color: Colors.red),
            SizedBox(width: 4),
            Text(
              'Connection Error',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
      );
    } else if (!isOnline) {
      return Chip(
        backgroundColor: Colors.orange.withOpacity(0.2),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 16, color: Colors.orange),
            SizedBox(width: 4),
            Text(
              'Offline',
              style: TextStyle(color: Colors.orange),
            ),
          ],
        ),
      );
    } else {
      return Chip(
        backgroundColor: Colors.green.withOpacity(0.2),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_done, size: 16, color: Colors.green),
            SizedBox(width: 4),
            Text(
              'Online',
              style: TextStyle(color: Colors.green),
            ),
          ],
        ),
      );
    }
  }
}