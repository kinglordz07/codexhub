import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:highlight/languages/java.dart';
import 'package:highlight/languages/cs.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/vbscript.dart'; // for VB.NET
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:highlight/highlight.dart';

class CollabCodeEditorScreen extends StatefulWidget {
  final String roomId;
  const CollabCodeEditorScreen({super.key, required this.roomId});

  @override
  State<CollabCodeEditorScreen> createState() => _CollabCodeEditorScreenState();
}

class _CollabCodeEditorScreenState extends State<CollabCodeEditorScreen> {
  final SupabaseClient supabase = Supabase.instance.client;

  String selectedLanguage = 'C#';
  late CodeController _codeController;
  Timer? _debounce;
  late RealtimeChannel _channel;
  String? executionResult;
  bool isExecuting = false;
  bool isOnline = true;

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

    _codeController = CodeController(
      text: languageSnippets[selectedLanguage]!,
      language: cs, // default C#
    );

    _codeController.addListener(() {
      _onCodeChanged(_codeController.text);
    });

    _initRealtime();
    _loadInitialCode();
  }

  void _initRealtime() {
    _channel = supabase.channel('code_room_${widget.roomId}');

    _channel.onPostgresChanges(
      event: PostgresChangeEvent.all, // listen for insert + update
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
          setState(() {
            _codeController.text = newCode.toString();
          });
        }
      },
    );

    _channel.subscribe();
  }

  Future<void> _loadInitialCode() async {
    try {
      final response =
          await supabase
              .from('code_rooms')
              .select()
              .eq('room_id', widget.roomId)
              .maybeSingle();

      if (response != null && response['code'] != null) {
        _codeController.text = response['code'].toString();
      } else {
        final user = supabase.auth.currentUser;
        if (user != null) {
          await supabase.from('code_rooms').upsert({
            'room_id': widget.roomId,
            'code': _codeController.text,
            'user_id': user.id,
            'language': selectedLanguage,
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading code: $e');
    }
  }

  void _onCodeChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      try {
        await supabase.from('code_rooms').upsert({
          'room_id': widget.roomId,
          'code': value,
          'user_id': supabase.auth.currentUser!.id,
          'language': selectedLanguage,
          'updated_at': DateTime.now().toIso8601String(),
        });
        setState(() => isOnline = true);
      } catch (e) {
        setState(() => isOnline = false);
      }
    });
  }

  Future<void> _runCode() async {
    setState(() {
      isExecuting = true;
      executionResult = null;
    });

    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      executionResult =
          "✅ Code executed (simulation)\n\nFor real execution, connect to Piston or JDoodle API.";
      isExecuting = false;
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    _debounce?.cancel();
    supabase.removeChannel(_channel);
    super.dispose();
  }

  void _insertSnippet(String language) {
    setState(() {
      selectedLanguage = language;
      _codeController.text = languageSnippets[language]!;
      _codeController.language = _getLanguageDef(language);
    });
  }

  /// ✅ Now returns Mode instead of Map<String, TextStyle>
  Mode? _getLanguageDef(String lang) {
    switch (lang) {
      case 'Python':
        return python;
      case 'VB.NET':
        return vbscript;
      case 'Java':
        return java;
      default:
        return cs; // C# default
    }
  }

  @override
  Widget build(BuildContext context) {
    // ✅ Auto theme detection
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final themeStyles = isDarkMode ? atomOneDarkTheme : githubTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Collaborative Editor ($selectedLanguage)'),
        backgroundColor: Colors.indigo,
        actions: [
          if (executionResult != null)
            IconButton(
              icon: const Icon(Icons.info),
              onPressed: () {
                showDialog(
                  context: context,
                  builder:
                      (_) => AlertDialog(
                        title: const Text('Execution Result'),
                        content: Text(executionResult!),
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
          Row(
            children: [
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: selectedLanguage,
                items:
                    languageSnippets.keys
                        .map(
                          (lang) =>
                              DropdownMenuItem(value: lang, child: Text(lang)),
                        )
                        .toList(),
                onChanged: (val) => _insertSnippet(val!),
              ),
              Icon(
                isOnline ? Icons.cloud_done : Icons.cloud_off,
                color: isOnline ? Colors.green : Colors.orange,
              ),
            ],
          ),
          Expanded(
            child: CodeTheme(
              data: CodeThemeData(styles: themeStyles), // ✅ Proper theme
              child: SingleChildScrollView(
                child: CodeField(
                  controller: _codeController,
                  textStyle: const TextStyle(fontFamily: "monospace"),
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ElevatedButton.icon(
                onPressed: isExecuting ? null : _runCode,
                icon: const Icon(Icons.play_arrow),
                label: Text(isExecuting ? "Running..." : "Run"),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: _codeController.text),
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Code copied to clipboard")),
                  );
                },
                icon: const Icon(Icons.save),
                label: const Text("Save"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
