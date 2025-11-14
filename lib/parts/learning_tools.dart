import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class LearningTools extends StatefulWidget {
  const LearningTools({super.key});

  @override
  State<LearningTools> createState() => _LearningToolsState();
}

class _LearningToolsState extends State<LearningTools> {
  bool _isLoading = true;
  StreamSubscription? _articlesSubscription;
  final Map<int, TextEditingController> _essayControllers = {};
  List<Map<String, dynamic>> _articles = [];
  List<Map<String, dynamic>> _quizQuestions = [];
  Map<String, List<String>> _videoIds = {};
  List<Map<String, dynamic>> _videoData = []; 

  int _quizIndex = 0;
  int _score = 0;
  bool _quizFinished = false;
  String? _selectedAnswer;
  bool _showAnswerFeedback = false;
  int _quizTimeSeconds = 0;
  late Timer _quizTimer;
  final List<Map<String, dynamic>> _answeredQuestions = [];
  String? _selectedMentor;
  List<String> _availableMentors = [];
  Map<String, List<Map<String, dynamic>>> _mentorQuizzes = {};
  bool _quizStarted = false; 
  bool _showCategorySelection = true;

  @override
  void initState() {
    super.initState();
    _loadContent();
    _subscribeToArticles();
    _startQuizTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _testStorageConnection();
      _debugBucketContents();
    });
  }

  void _startQuizTimer() {
    _quizTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!_quizFinished && mounted) {
        setState(() {
          _quizTimeSeconds++;
        });
      }
    });
  }

  void _subscribeToArticles() {
    final client = Supabase.instance.client;
    _articlesSubscription = client
        .from('articles')
        .stream(primaryKey: ['id'])
        .asyncMap((List<Map<String, dynamic>> data) async {
          // Enrich each article with profile information
          final enrichedArticles = <Map<String, dynamic>>[];
          for (final article in data) {
            final enrichedArticle = await _enrichArticleWithProfile(article, client);
            enrichedArticles.add(enrichedArticle);
          }
          return enrichedArticles;
        })
        .listen(
          (List<Map<String, dynamic>> data) {
            setState(() {
              _articles = _processArticles(data);
            });
          },
          onError: (error) {
            debugPrint('Real-time subscription error: $error');
          },
        );
  }

  Future<Map<String, dynamic>> _enrichArticleWithProfile(
      Map<String, dynamic> article, SupabaseClient client) async {
    try {
      debugPrint('Article keys: ${article.keys.toList()}');
      debugPrint('Article data: $article');
      
      // Try to get user_id from article
      final userId = article['user_id'] ?? article['uploaded_by'];
      
      if (userId != null && userId.toString().isNotEmpty) {
        try {
          // Fetch the user profile from profiles_new
          final profileData = await client
              .from('profiles_new')
              .select('username, full_name')
              .eq('id', userId)
              .single();
          
          debugPrint('Profile found: $profileData');
          
          // Add profile to article with the correct key name
          return {
            ...article,
            'profiles_new': profileData,
          };
        } catch (e) {
          debugPrint('Error fetching profile for userId $userId: $e');
        }
      } else {
        debugPrint('No userId found in article. user_id: ${article['user_id']}, uploaded_by: ${article['uploaded_by']}');
      }
    } catch (e) {
      debugPrint('Error enriching article with profile: $e');
    }
    
    return article;
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });
    await _loadContent();
  }

  Future<void> _downloadFile(Map<String, dynamic> article) async {
    if (!article['has_valid_file']) {
      _showSnackBar('No file available for view', Colors.orange);
      return;
    }

    final String filePath = article['file_path'];
    final String fileName = article['file_name'];

    try {
      _showSnackBar('Opening $fileName...', Colors.blue);
      
      await _downloadToPrivateStorage(filePath, fileName);
      
    } catch (e) {
      ('❌ View failed: $e');
      _showSnackBar('View failed. Please try again.', Colors.red);
      
      await _tryPublicUrlFallback(filePath);
    }
  }
Future<void> _downloadToPrivateStorage(String filePath, String fileName) async {
    try {
      ('🔍 Starting download from: $filePath');
      
      final supabase = Supabase.instance.client;
      
      final Uint8List fileData = await supabase.storage
          .from('learning_files')
          .download(filePath);

      if (fileData.isEmpty) {
        throw Exception('Downloaded file is empty');
      }

      final directory = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${directory.path}/CodexHub_Downloads');
      
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      
      final localFile = File('${downloadsDir.path}/$fileName');
      await localFile.writeAsBytes(fileData);
      
      ('✅ Download successful!');
      ('📁 File saved to: ${localFile.path}');
      
      
      final result = await OpenFilex.open(localFile.path);
      ('🔗 Open file result: ${result.message}');
      
      if (result.type != ResultType.done) {
        _showFileOptionsDialog(localFile.path, fileName);
      }
      
    } catch (e) {
      ('❌ Private storage download failed: $e');
      rethrow; 
    }
  }
Future<void> _tryPublicUrlFallback(String filePath) async {
    try {
      final supabase = Supabase.instance.client;
      final publicUrl = supabase.storage
          .from('learning_files')
          .getPublicUrl(filePath);
      
      ('🔄 Fallback: Trying public URL: $publicUrl');
      
      if (await canLaunchUrl(Uri.parse(publicUrl))) {
        await launchUrl(
          Uri.parse(publicUrl),
          mode: LaunchMode.externalApplication,
        );
        _showSnackBar('Opening in browser...', Colors.blue);
      } else {
        throw Exception('Cannot launch URL');
      }
    } catch (e) {
      ('❌ Fallback also failed: $e');
      _showSnackBar('All download methods failed', Colors.red);
    }
  }

  void _showFileOptionsDialog(String filePath, String fileName) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_open, color: Colors.blue),
              title: const Text('Open File'),
              subtitle: Text('Open $fileName with a suitable app'),
              onTap: () {
                Navigator.pop(context);
                OpenFilex.open(filePath);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open, color: Colors.green),
              title: const Text('Show File Location'),
              subtitle: const Text('View where the file is stored'),
              onTap: () {
                Navigator.pop(context);
                _showFileLocation(filePath);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.purple),
              title: const Text('Share File'),
              subtitle: const Text('Share with other apps'),
              onTap: () {
                Navigator.pop(context);
                _showFileLocation(filePath); 
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showFileLocation(String filePath) {
    final file = File(filePath);
    final directory = file.parent;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('File Location'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('File downloaded successfully to:'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  directory.path,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'You can access this file through your device\'s file manager in the app storage section.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              OpenFilex.open(filePath);
            },
            child: const Text('Open File'),
          ),
        ],
      ),
    );
  }

Future<void> _testStorageConnection() async {
    try {
      final client = Supabase.instance.client;
      debugPrint('🔧 Testing storage connection...');
      
      final buckets = await client.storage.listBuckets();
      debugPrint('📦 Available buckets:');
      for (final bucket in buckets) {
        debugPrint('   - ${bucket.name} (id: ${bucket.id})');
      }
      
      final fileName = '1761797210317_Thank you for using Documents.docx';
      debugPrint('\n🔎 Testing file existence for: $fileName');
      
      final testBuckets = ['learning_files', 'resources'];
      for (final bucketName in testBuckets) {
        try {
          final files = await client.storage.from(bucketName).list();
          final matchingFiles = files.where((file) => file.name.contains(fileName)).toList();
          if (matchingFiles.isNotEmpty) {
            debugPrint('✅ File found in $bucketName:');
            for (final file in matchingFiles) {
              debugPrint('   - ${file.name}');
            }
          }
        } catch (e) {
          debugPrint('❌ Error checking $bucketName: $e');
        }
      }
      
    } catch (e) {
      debugPrint('💥 Storage connection test failed: $e');
    }
  }

  Future<void> _debugBucketContents() async {
    try {
      final client = Supabase.instance.client;
      
      debugPrint('🔍 DEBUG: Checking bucket contents...');
      
      try {
        final learningFiles = await client.storage.from('learning_files').list();
        debugPrint('📁 Files in learning_files bucket (${learningFiles.length}):');
        for (final file in learningFiles) {
          debugPrint('   - ${file.name}');
          
          if (file.name == 'codexhub' || file.name.endsWith('/')) {
            try {
              final folderFiles = await client.storage.from('learning_files').list(path: file.name);
              debugPrint('   📂 Contents of ${file.name} (${folderFiles.length}):');
              for (final folderFile in folderFiles) {
                debugPrint('     - ${folderFile.name}');
              }
            } catch (e) {
              debugPrint('   ❌ Error listing folder ${file.name}: $e');
            }
          }
        }
      } catch (e) {
        debugPrint('❌ Error accessing learning_files bucket: $e');
      }
      
      try {
        final resourcesFiles = await client.storage.from('resources').list();
        debugPrint('📁 Files in resources bucket (${resourcesFiles.length}):');
        for (final file in resourcesFiles) {
          debugPrint('   - ${file.name}');
        }
      } catch (e) {
        debugPrint('❌ Error accessing resources bucket: $e');
      }
      
    } catch (e) {
      debugPrint('💥 Error debugging bucket contents: $e');
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }
  String? _extractVideoIdFromUrl(String url) {
    final regExp = RegExp(
      r'^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#&?]*).*',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(url);
    return (match != null && match.group(7)!.length == 11) ? match.group(7) : null;
  }

  Future<void> _openYouTubeVideo(String videoId) async {
    final url = 'https://www.youtube.com/watch?v=$videoId';
    final uri = Uri.parse(url);
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        _showSnackBar('Cannot open YouTube', Colors.red);
      }
    } catch (e) {
      _showSnackBar('Error opening video: $e', Colors.red);
    }
  }

  @override
  void dispose() {
    _articlesSubscription?.cancel();
    _quizTimer.cancel();
    for (var controller in _essayControllers.values) {
      controller.dispose();
    }
    _essayControllers.clear();
    super.dispose();
  }

  List<Map<String, dynamic>> _processArticles(List<Map<String, dynamic>> articles) {
    return articles.map((article) {
      bool hasAttachment = article['has_attachment'] == true;
      String? fileName = article['file_name']?.toString();
      String? filePath = article['file_path']?.toString();

      bool hasValidFile = fileName != null &&
          filePath != null &&
          fileName.isNotEmpty &&
          filePath.isNotEmpty;

      String mentorName = _extractMentorName(article);

      return {
        ...article,
        'display_uploaded_by': mentorName,
        'mentor_name': mentorName,
        'has_attachment': hasAttachment,
        'has_valid_file': hasValidFile,
        'file_name': fileName,
        'file_path': filePath,
      };
    }).toList();
  }

  Future<void> _loadContent() async {
    try {
      final client = Supabase.instance.client;

      // Try to load articles with profile join, fall back to without join if it fails
      List<Map<String, dynamic>> articlesResponse = [];
      try {
        articlesResponse = await client
            .from('articles')
            .select('''
              *,
              profiles_new:user_id (username, full_name)
            ''')
            .order('created_at', ascending: false);
      } catch (e) {
        debugPrint('Error loading articles with profiles_new join: $e, trying without join...');
        // Fallback: load without the join
        articlesResponse = await client
            .from('articles')
            .select('*')
            .order('created_at', ascending: false);
      }

      List<Map<String, dynamic>> videosResponse = [];
      try {
        videosResponse = await client
            .from('video_urls')
            .select('''
              *,
              profiles_new:uploaded_by (username)
            ''')
            .eq('is_removed', false)
            .eq('is_uploaded_to_learning_tools', true)
            .order('created_at', ascending: false);
      } catch (e) {
        debugPrint('Error loading uploaded videos: $e');
      }

      List<Map<String, dynamic>> quizResponse = []; 
      try {
        final quizData = await client
            .from('quizzes')
            .select()
            .eq('is_active', true)
            .order('created_by')
            .order('quiz_group_name')
            .order('question_order');

        quizResponse = (quizData as List).map((item) => item as Map<String, dynamic>).toList().map((quiz) {
          final answers = List<String>.from(quiz['answers'] ?? []);
          final correctAnswers = List<String>.from(quiz['correct_answers'] ?? []);
          final questionType = quiz['question_type']?.toString() ?? 'multiple_choice';

          return {
            'id': quiz['id'],
            'question': quiz['question'] ?? 'Untitled Question',
            'category': quiz['category'] ?? 'General',
            'answers': answers,
            'correct_answers': correctAnswers,
            'question_type': questionType,
            'difficulty': quiz['difficulty'] ?? 'Medium',
            'quiz_group_name': quiz['quiz_group_name'],
            'question_order': quiz['question_order'],
            'created_by': quiz['created_by'] ?? 'Unknown Mentor',
            'user_id': quiz['user_id'],
          };
        }).toList();
      } catch (e) {
        debugPrint('Error loading quizzes: $e');
        quizResponse = _generateFallbackQuiz(); 
      }

      if (quizResponse.isEmpty) { 
        quizResponse = _generateFallbackQuiz(); 
      }

      final Map<String, List<Map<String, dynamic>>> mentorQuizzes = {};
      for (final quiz in quizResponse) {
        final mentorName = quiz['created_by'] as String? ?? 'System';
        if (!mentorQuizzes.containsKey(mentorName)) {
          mentorQuizzes[mentorName] = [];
        }
        mentorQuizzes[mentorName]!.add(quiz);
      }

      final mentors = mentorQuizzes.keys.toList();
      mentors.sort();

      final processedArticles = _processArticles(articlesResponse);
      
      debugPrint('Loaded data - Articles: ${articlesResponse.length}, Videos: ${videosResponse.length}, Quizzes: ${quizResponse.length}');

      setState(() {
        _articles = processedArticles;
        _quizQuestions = quizResponse;
        _videoIds = {};
        _videoData = videosResponse;
        _mentorQuizzes = mentorQuizzes;
        _availableMentors = mentors;
    
        
        for (var video in videosResponse) {
          final category = video['category'] as String? ?? 'General';
          final youtubeUrl = video['youtube_url'] as String?;
          
          String? videoId;
          if (youtubeUrl != null && youtubeUrl.isNotEmpty) {
            videoId = _extractVideoIdFromUrl(youtubeUrl);
          }

          if (videoId != null && videoId.isNotEmpty) {
            if (!_videoIds.containsKey(category)) {
              _videoIds[category] = [];
            }
            _videoIds[category]!.add(videoId);
          }
        }

        if (_videoIds.isEmpty) {
          _videoIds = {
            'Sample Videos': ['grEKMHGYyns'],
          };
        }

        _quizQuestions.shuffle(Random());
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading content: $e');
      setState(() {
        _articles = _generateFallbackArticles();
        _videoIds = {
          'Sample Videos': ['grEKMHGYyns'],
        };
        _quizQuestions = _generateFallbackQuiz();
        _isLoading = false;
      });
    }
  }

  Widget _buildMentorSelection() {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.school,
              size: isSmallScreen ? 64 : 80,
              color: Colors.purple,
            ),
            SizedBox(height: isSmallScreen ? 16 : 24),
            Text(
              'Choose Mentor\'s Quiz',
              style: TextStyle(
                fontSize: isSmallScreen ? 24 : 32,
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
            ),
            SizedBox(height: isSmallScreen ? 8 : 12),
            Text(
              'Select which mentor\'s quiz you want to take',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isSmallScreen ? 14 : 16,
                color: Colors.grey[600],
              ),
            ),
            SizedBox(height: isSmallScreen ? 24 : 32),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
                child: Column(
                  children: [
                    Text(
                      'Available Mentors',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 18 : 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 16 : 20),
                    if (_availableMentors.isNotEmpty)
                      ..._availableMentors.map((mentor) {
                        final mentorQuizzes = _mentorQuizzes[mentor] ?? [];
                        final totalQuestions = mentorQuizzes.length;
                        final categories = mentorQuizzes
                            .map((q) => q['category'] as String? ?? 'General')
                            .toSet()
                            .toList();
                        
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 4 : 6),
                          child: ListTile(
                            leading: Container(
                              width: isSmallScreen ? 40 : 48,
                              height: isSmallScreen ? 40 : 48,
                              decoration: BoxDecoration(
                                color: Colors.purple[100],
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Icon(
                                Icons.person,
                                color: Colors.purple,
                                size: isSmallScreen ? 20 : 24,
                              ),
                            ),
                            title: Text(
                              mentor,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: isSmallScreen ? 16 : 18,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$totalQuestions questions'),
                                if (categories.isNotEmpty)
                                  Text(
                                    'Categories: ${categories.take(2).join(', ')}${categories.length > 2 ? '...' : ''}',
                                    style: TextStyle(fontSize: isSmallScreen ? 12 : 14, color: Colors.grey[600]),
                                  ),
                              ],
                            ),
                            trailing: _selectedMentor == mentor
                                ? Icon(Icons.check_circle, color: Colors.green)
                                : Icon(Icons.arrow_forward_ios, size: isSmallScreen ? 16 : 18, color: Colors.grey),
                            onTap: () {
                              setState(() {
                                _selectedMentor = mentor;
                              });
                            },
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            tileColor: _selectedMentor == mentor
                                ? Colors.purple[50]
                                : Colors.grey[50],
                          ),
                        );
                      }),
                    SizedBox(height: isSmallScreen ? 20 : 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _selectedMentor != null ? _startQuiz : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 14 : 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Start ${_selectedMentor != null ? '${_selectedMentor!}\'s ' : ''}Quiz',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 16 : 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: isSmallScreen ? 20 : 24),
            Card(
              child: Padding(
                padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem(Icons.people, 'Mentors', '${_availableMentors.length}', isSmallScreen),
                    _buildStatItem(Icons.quiz, 'Total Questions', '${_quizQuestions.length}', isSmallScreen),
                    _buildStatItem(Icons.category, 'Quiz Groups', '${_mentorQuizzes.values.map((quizzes) => quizzes.map((q) => q['quiz_group_name']).toSet().length).fold(0, (sum, count) => sum + count)}', isSmallScreen),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startQuiz() {
    if (_selectedMentor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a mentor first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    final mentorQuizzes = _mentorQuizzes[_selectedMentor] ?? [];
    
    if (mentorQuizzes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No quizzes available for $_selectedMentor'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final List<Map<String, dynamic>> filteredQuestions = List<Map<String, dynamic>>.from(mentorQuizzes);

    if (filteredQuestions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No questions found for $_selectedMentor'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    filteredQuestions.sort((a, b) {
      final orderA = a['question_order'] as int? ?? 0;
      final orderB = b['question_order'] as int? ?? 0;
      return orderA.compareTo(orderB);
    });

    
    setState(() {
      _quizQuestions = filteredQuestions;
      _quizStarted = true;
      _quizIndex = 0;
      _score = 0;
      _quizFinished = false;
      _quizTimeSeconds = 0;
      _selectedAnswer = null;
      _showAnswerFeedback = false;
      _answeredQuestions.clear();
      _showCategorySelection = false;
    });
  }

  String _extractMentorName(Map<String, dynamic> data) {
    debugPrint('=== _extractMentorName DEBUG ===');
    debugPrint('All data keys: ${data.keys.toList()}');
    debugPrint('user_id: ${data['user_id']}');
    debugPrint('profiles_new: ${data['profiles_new']}');
    debugPrint('profiles: ${data['profiles']}');
    
    // Try to get from profiles_new (the correct table)
    if (data['profiles_new'] != null) {
      final profile = data['profiles_new'];
      debugPrint('profiles_new is Map: ${profile is Map<String, dynamic>}');
      if (profile is Map<String, dynamic>) {
        debugPrint('profiles_new keys: ${profile.keys.toList()}');
        debugPrint('profiles_new username: ${profile['username']}');
        debugPrint('profiles_new full_name: ${profile['full_name']}');
        
        if (profile['username'] != null && profile['username'].toString().isNotEmpty) {
          final result = profile['username'].toString();
          debugPrint('Returning from profiles_new.username: $result');
          return result;
        } else if (profile['full_name'] != null && profile['full_name'].toString().isNotEmpty) {
          final result = profile['full_name'].toString();
          debugPrint('Returning from profiles_new.full_name: $result');
          return result;
        }
      }
    }
    
    // Try to get from nested profiles object (fallback, from join)
    if (data['profiles'] != null) {
      final profile = data['profiles'];
      debugPrint('profiles is Map: ${profile is Map<String, dynamic>}');
      if (profile is Map<String, dynamic>) {
        debugPrint('profiles keys: ${profile.keys.toList()}');
        debugPrint('profiles username: ${profile['username']}');
        debugPrint('profiles full_name: ${profile['full_name']}');
        
        if (profile['username'] != null && profile['username'].toString().isNotEmpty) {
          final result = profile['username'].toString();
          debugPrint('Returning from profiles.username: $result');
          return result;
        } else if (profile['full_name'] != null && profile['full_name'].toString().isNotEmpty) {
          final result = profile['full_name'].toString();
          debugPrint('Returning from profiles.full_name: $result');
          return result;
        }
      }
    }
    
    // Fallback: try other fields
    if (data['mentor_name'] != null && data['mentor_name'].toString().isNotEmpty) {
      final result = data['mentor_name'].toString();
      debugPrint('Returning from mentor_name: $result');
      return result;
    } else if (data['uploaded_by_name'] != null && data['uploaded_by_name'].toString().isNotEmpty) {
      final result = data['uploaded_by_name'].toString();
      debugPrint('Returning from uploaded_by_name: $result');
      return result;
    } else if (data['user_name'] != null && data['user_name'].toString().isNotEmpty) {
      final result = data['user_name'].toString();
      debugPrint('Returning from user_name: $result');
      return result;
    } else if (data['display_uploaded_by'] != null && data['display_uploaded_by'].toString().isNotEmpty) {
      final result = data['display_uploaded_by'].toString();
      debugPrint('Returning from display_uploaded_by: $result');
      return result;
    } else if (data['uploaded_by'] != null && data['uploaded_by'].toString().isNotEmpty) {
      final uploadedBy = data['uploaded_by'].toString();
      if (uploadedBy.contains('@')) {
        debugPrint('Returning from uploaded_by (email): $uploadedBy');
        return uploadedBy;
      } else if (uploadedBy.length > 8) {
        final result = 'User ${uploadedBy.substring(0, 8)}...';
        debugPrint('Returning from uploaded_by (substring): $result');
        return result;
      } else {
        final result = 'User $uploadedBy';
        debugPrint('Returning from uploaded_by (full): $result');
        return result;
      }
    }
    debugPrint('Falling back to CodexHub Mentor');
    return 'CodexHub Mentor';
  }

  String _getVideoUploaderName(Map<String, dynamic> video) {
    try {

      if (video['profiles_new'] != null) {
        final profile = video['profiles_new'];
        if (profile is Map<String, dynamic> && profile['username'] != null) {
          return profile['username'] as String;
        }
      }
      
      final uploadedBy = video['uploaded_by'];
      if (uploadedBy != null) {
        final uploadedByStr = uploadedBy.toString();
        if (uploadedByStr.contains('@')) {
          return uploadedByStr;
        } else if (uploadedByStr.length > 8) {
          return 'User ${uploadedByStr.substring(0, 8)}...';
        } else {
          return 'User $uploadedByStr';
        }
      }
      
      return 'System';
    } catch (e) {
      return 'Unknown';
    }
  }

  String _formatUploadTime(dynamic uploadedAt) {
    try {
      if (uploadedAt != null) {
        final date = DateTime.parse(uploadedAt);
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      debugPrint('Error parsing upload time: $e');
    }
    return 'Unknown Date';
  }

  Widget _buildArticleCard(Map<String, dynamic> article) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    String title = article['title']?.toString() ?? "Untitled";
    String content = article['content']?.toString() ?? "";
    String preview = content.length > 80 ? "${content.substring(0, 80)}..." : content;

    // Use the pre-extracted mentor name from _processArticles
    String uploadedBy = article['display_uploaded_by']?.toString() ?? _extractMentorName(article);
    String uploadedAt = _formatUploadTime(article['created_at'] ?? article['uploaded_at']);
    
    debugPrint('Article card - uploadedBy: $uploadedBy, uploadedAt: $uploadedAt');
    debugPrint('Article card - display_uploaded_by: ${article['display_uploaded_by']}');
    debugPrint('Article card - mentor_name: ${article['mentor_name']}');

    bool hasValidFile = article['has_valid_file'] == true;
    String? fileName = article['file_name']?.toString();

    return Card(
      margin: EdgeInsets.symmetric(vertical: isSmallScreen ? 6 : 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          border: hasValidFile ? Border.all(color: Colors.green, width: 2) : null,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ExpansionTile(
          leading: Container(
            padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
            decoration: BoxDecoration(
              color: hasValidFile ? Colors.green[100] : Colors.indigo[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasValidFile ? Icons.attach_file : Icons.article,
              color: hasValidFile ? Colors.green : Colors.indigo,
              size: isSmallScreen ? 18 : 20,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 16 : 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (hasValidFile)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.attach_file, size: isSmallScreen ? 12 : 14, color: Colors.green[700]),
                      if (!isSmallScreen) ...[
                        const SizedBox(width: 4),
                        Text('File', style: TextStyle(fontSize: isSmallScreen ? 10 : 12, color: Colors.green[700], fontWeight: FontWeight.bold)),
                      ],
                    ],
                  ),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: isSmallScreen ? 12 : 14, color: Colors.grey)),
              SizedBox(height: isSmallScreen ? 2 : 4),
              Row(
                children: [
                  Icon(Icons.person_outline, size: isSmallScreen ? 10 : 12, color: Colors.grey),
                  SizedBox(width: isSmallScreen ? 2 : 4),
                  Expanded(child: Text('By: $uploadedBy', style: TextStyle(fontSize: isSmallScreen ? 10 : 12, color: Colors.grey[600]), overflow: TextOverflow.ellipsis)),
                  SizedBox(width: isSmallScreen ? 4 : 8),
                  Icon(Icons.calendar_today, size: isSmallScreen ? 10 : 12, color: Colors.grey),
                  SizedBox(width: isSmallScreen ? 2 : 4),
                  Text(uploadedAt, style: TextStyle(fontSize: isSmallScreen ? 10 : 12, color: Colors.grey[600])),
                ],
              ),
            ],
          ),
          trailing: hasValidFile ? IconButton(
            icon: Icon(Icons.visibility, color: Colors.green, size: isSmallScreen ? 20 : 24),
            onPressed: () => _downloadFile(article),
            tooltip: 'View $fileName',
          ) : null,
          children: [
            Padding(
              padding: EdgeInsets.all(isSmallScreen ? 12.0 : 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(content, style: TextStyle(fontSize: isSmallScreen ? 14 : 16, height: 1.5)),
                  SizedBox(height: isSmallScreen ? 12 : 16),

                  if (hasValidFile)
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(isSmallScreen ? 10.0 : 12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.attach_file, color: Colors.green),
                              SizedBox(width: isSmallScreen ? 6 : 8),
                              Text('Attached File:', 
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800], 
                              fontSize: isSmallScreen ? 14 : 16)),
                            ]),
                            SizedBox(height: isSmallScreen ? 6 : 8),
                            Text(fileName!, style: TextStyle(color: Colors.green[700], fontSize: isSmallScreen ? 12 : 14)),
                            SizedBox(height: isSmallScreen ? 8 : 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _downloadFile(article),
                                icon: Icon(Icons.visibility, size: isSmallScreen ? 18 : 20),
                                label: Text('View File', style: TextStyle(fontSize: isSmallScreen ? 14 : 16)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 10 : 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  SizedBox(height: isSmallScreen ? 12 : 16),
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: isSmallScreen ? 14 : 16, color: Colors.grey),
                        SizedBox(width: isSmallScreen ? 6 : 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Uploaded by $uploadedBy on $uploadedAt', style: TextStyle(fontSize: isSmallScreen ? 12 : 14, color: Colors.grey[700], fontStyle: FontStyle.italic)),
                              if (hasValidFile)
                                Padding(
                                  padding: EdgeInsets.only(top: isSmallScreen ? 2.0 : 4.0),
                                  child: Text('File: $fileName', style: TextStyle(fontSize: isSmallScreen ? 10 : 12, color: Colors.grey[600])),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildVideoSection(String title, List<String> videoIds) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    final categoryVideos = _videoData.where((video) {
      final videoCategory = video['category'] as String? ?? 'General';
      return videoCategory == title;
    }).toList();

    if (categoryVideos.isEmpty) {
      return _buildNoVideosPlaceholder(title, isSmallScreen);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title Tutorials', 
          style: TextStyle(
            fontSize: isSmallScreen ? 16 : 18, 
            fontWeight: FontWeight.bold
          ),
        ),
        SizedBox(height: isSmallScreen ? 6 : 8),
        SizedBox(
          height: isSmallScreen ? 200 : 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: categoryVideos.length,
            itemBuilder: (context, index) {
              final video = categoryVideos[index];
              final youtubeUrl = video['youtube_url'] as String? ?? '';
              final videoId = _extractVideoIdFromUrl(youtubeUrl);
              final videoTitle = video['title'] as String? ?? 'Untitled Video';
              final uploaderName = _getVideoUploaderName(video);
              final thumbnail = video['youtube_thumbnail'] as String?;

              return GestureDetector(
                onTap: () => _openYouTubeVideo(videoId ?? ''),
                child: Container(
                  width: isSmallScreen ? 260 : 300,
                  margin: EdgeInsets.only(
                    right: index == categoryVideos.length - 1 ? 0 : isSmallScreen ? 8 : 12,
                    left: index == 0 ? isSmallScreen ? 8 : 12 : 0,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: isSmallScreen ? 120 : 140,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                          image: thumbnail != null 
                              ? DecorationImage(
                                  image: NetworkImage(thumbnail),
                                  fit: BoxFit.cover,
                                )
                              : DecorationImage(
                                  image: NetworkImage('https://img.youtube.com/vi/$videoId/0.jpg'),
                                  fit: BoxFit.cover,
                                ),
                        ),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(isSmallScreen ? 8 : 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              videoTitle,
                              style: TextStyle(
                                fontSize: isSmallScreen ? 14 : 16,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: isSmallScreen ? 4 : 6),
                            Text(
                              'By: $uploaderName',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 12 : 14,
                                color: Colors.grey[600],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            SizedBox(height: isSmallScreen ? 2 : 4),
                            Text(
                              'Tap to watch on YouTube',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 11 : 13,
                                color: Colors.blue[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(height: isSmallScreen ? 12 : 16),
      ],
    );
  }

  Widget _buildNoVideosPlaceholder(String title, bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title Tutorials', 
          style: TextStyle(fontSize: isSmallScreen ? 16 : 18, fontWeight: FontWeight.bold)
        ),
        SizedBox(height: isSmallScreen ? 6 : 8),
        Container(
          height: isSmallScreen ? 150 : 200,
          decoration: BoxDecoration(
            color: Colors.grey[200], 
            borderRadius: BorderRadius.circular(12)
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam_off, size: isSmallScreen ? 30 : 40, color: Colors.grey),
                SizedBox(height: isSmallScreen ? 6 : 8),
                Text(
                  'No videos available', 
                  style: TextStyle(fontSize: isSmallScreen ? 14 : 16, color: Colors.grey)
                ),
                SizedBox(height: isSmallScreen ? 4 : 6),
                Text(
                  'Add videos from Resource Library', 
                  style: TextStyle(fontSize: isSmallScreen ? 12 : 14, color: Colors.grey)
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: isSmallScreen ? 12 : 16),
      ],
    );
  }

  void _answerQuestion(String answer) {
    if (_quizFinished || _showAnswerFeedback) return;

    final currentQuestion = _quizQuestions[_quizIndex];
    final questionType = currentQuestion['question_type']?.toString() ?? 'multiple_choice';
    
    setState(() {
      _selectedAnswer = answer;
      _showAnswerFeedback = true;
    });

    bool isCorrect = false;
    
    if (questionType == 'multiple_choice') {
      final correctAnswers = List<String>.from(currentQuestion['correct_answers'] ?? []);
      isCorrect = correctAnswers.contains(answer);
    } else {
      isCorrect = true;
      
      if (_essayControllers.containsKey(_quizIndex)) {
        _essayControllers[_quizIndex]!.clear();
      }
    }
    
    if (isCorrect) _score++;

    _answeredQuestions.add({
      'question': currentQuestion['question'],
      'userAnswer': answer,
      'correctAnswer': questionType == 'multiple_choice' 
          ? (currentQuestion['correct_answers'] as List).join(', ')
          : 'Essay - Manual Grading Required',
      'isCorrect': isCorrect,
      'question_type': questionType,
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _showAnswerFeedback = false;
          _selectedAnswer = null;
          _quizIndex++;
          if (_quizIndex >= _quizQuestions.length) {
            _quizFinished = true;
          }
        });
      }
    });
  }

  void _resetQuiz() {
    for (var controller in _essayControllers.values) {
      controller.dispose();
    }
    _essayControllers.clear();
    setState(() {
      _quizIndex = 0;
      _score = 0;
      _quizFinished = false;
      _quizTimeSeconds = 0;
      _selectedAnswer = null;
      _showAnswerFeedback = false;
      _answeredQuestions.clear();
      _quizStarted = false;
      _selectedMentor = null;
      _showCategorySelection = true;
      _quizQuestions.shuffle(Random());
    });
  }

  void _backToMentorSelection() {
    setState(() {
      _quizStarted = false;
      _quizFinished = false;
      _showCategorySelection = true;
      _selectedMentor = null;
      
      _quizIndex = 0;
      _score = 0;
      _quizTimeSeconds = 0;
      _selectedAnswer = null;
      _showAnswerFeedback = false;
      _answeredQuestions.clear();
      
      for (var controller in _essayControllers.values) {
        controller.dispose();
      }
      _essayControllers.clear();
    });
  }

  Widget _buildQuizHeader() {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Card(
      margin: EdgeInsets.only(bottom: isSmallScreen ? 12 : 16),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Question ${_quizIndex + 1} of ${_quizQuestions.length}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: isSmallScreen ? 14 : 16)),
                    SizedBox(height: isSmallScreen ? 2 : 4),
                    Container(
                      width: isSmallScreen ? 120 : 150,
                      height: 8,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: Colors.grey[300]),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (_quizIndex + 1) / _quizQuestions.length,
                        child: Container(decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), color: Colors.indigo)),
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer, size: isSmallScreen ? 14 : 16, color: Colors.grey[600]),
                    SizedBox(width: isSmallScreen ? 2 : 4),
                    Text('${_quizTimeSeconds}s', style: TextStyle(fontSize: isSmallScreen ? 12 : 14, color: Colors.grey[600], fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 6 : 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.quiz, size: isSmallScreen ? 14 : 16, color: Colors.indigo),
                SizedBox(width: isSmallScreen ? 2 : 4),
                Text('Score: $_score/${_quizQuestions.length}', style: TextStyle(fontSize: isSmallScreen ? 12 : 14, color: Colors.indigo, fontWeight: FontWeight.bold)),
                SizedBox(width: isSmallScreen ? 12 : 16),
                Icon(Icons.category, size: isSmallScreen ? 14 : 16, color: Colors.indigo),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(Map<String, dynamic> question) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;
    final questionType = question['question_type']?.toString() ?? 'multiple_choice';
    final isEssay = questionType == 'essay';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    question['question'] as String, 
                    style: TextStyle(
                      fontSize: isSmallScreen ? 16 : 18, 
                      fontWeight: FontWeight.w600, 
                      height: 1.4
                    )
                  ),
                ),
                // Question type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isEssay ? Colors.orange[100] : Colors.blue[100],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: isEssay ? Colors.orange : Colors.blue)
                  ),
                  child: Text(
                    isEssay ? 'ESSAY' : 'MULTIPLE CHOICE',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 10 : 12,
                      color: isEssay ? Colors.orange[800] : Colors.blue[700],
                      fontWeight: FontWeight.w500
                    ),
                  ),
                ),
              ],
            ),
            if (question['category'] != null) ...[
              SizedBox(height: isSmallScreen ? 8 : 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue[50], 
                  borderRadius: BorderRadius.circular(4), 
                  border: Border.all(color: Colors.blue)
                ),
                child: Text(
                  question['category'] as String, 
                  style: TextStyle(
                    fontSize: isSmallScreen ? 10 : 12, 
                    color: Colors.blue[700], 
                    fontWeight: FontWeight.w500
                  )
                ),
              ),
            ],
            // Essay instructions
            if (isEssay) ...[
              SizedBox(height: isSmallScreen ? 12 : 16),
              Container(
                padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: isSmallScreen ? 16 : 18),
                    SizedBox(width: isSmallScreen ? 8 : 12),
                    Expanded(
                      child: Text(
                        'This is an essay question. Write your answer in the text area below.',
                        style: TextStyle(
                          color: Colors.orange[800],
                          fontSize: isSmallScreen ? 12 : 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerOptions(Map<String, dynamic> question) {
    final questionType = question['question_type']?.toString() ?? 'multiple_choice';
    
    if (questionType == 'essay') {
      return _buildEssayAnswerInput();
    } else {
      return Column(
        children: (question['answers'] as List).asMap().entries.map((entry) {
          final index = entry.key;
          final answer = entry.value;
          return _buildEnhancedAnswerButton(question, answer, index);
        }).toList(),
      );
    }
  }

  Widget _buildEssayAnswerInput() {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    if (!_essayControllers.containsKey(_quizIndex)) {
      _essayControllers[_quizIndex] = TextEditingController();
    }
    final essayController = _essayControllers[_quizIndex]!;

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
          ),
          child: TextField(
            controller: essayController,
            maxLines: 6,
            minLines: 4,
            decoration: InputDecoration(
              hintText: 'Type your essay answer here...',
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(isSmallScreen ? 12 : 16),
              hintStyle: TextStyle(color: Colors.grey[500]),
            ),
            style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
          ),
        ),
        SizedBox(height: isSmallScreen ? 12 : 16),
        Row(
          children: [
            // Clear button
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  essayController.clear();
                  setState(() {});
                },
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 12 : 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: Colors.grey),
                ),
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 16,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ),
            SizedBox(width: isSmallScreen ? 12 : 16),
            // Submit button
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  final answer = essayController.text.trim();
                  if (answer.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Please write your essay answer before submitting.'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  _answerQuestion(answer);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 12 : 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'Submit Essay',
                  style: TextStyle(fontSize: isSmallScreen ? 14 : 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: isSmallScreen ? 8 : 12),
        Container(
          padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: isSmallScreen ? 16 : 18),
              SizedBox(width: isSmallScreen ? 8 : 12),
              Expanded(
                child: Text(
                  'Essay answers are automatically marked as correct. As long as you filled it up.',
                  style: TextStyle(
                    color: Colors.blue[800],
                    fontSize: isSmallScreen ? 12 : 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedAnswerButton(Map<String, dynamic> question, String answer, int index) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    final isSelected = _selectedAnswer == answer;
    final correctAnswers = List<String>.from(question['correct_answers'] ?? []);
    final isCorrect = correctAnswers.contains(answer);
    final showFeedback = _showAnswerFeedback;
    
    Color backgroundColor = Colors.grey[100]!;
    Color textColor = Colors.black;
    Color borderColor = Colors.grey[300]!;
    
    if (showFeedback) {
      if (isSelected) {
        backgroundColor = isCorrect ? Colors.green[50]! : Colors.red[50]!;
        textColor = isCorrect ? Colors.green[800]! : Colors.red[800]!;
        borderColor = isCorrect ? Colors.green : Colors.red;
      } else if (isCorrect) {
        backgroundColor = Colors.green[50]!;
        textColor = Colors.green[800]!;
        borderColor = Colors.green;
      }
    } else if (isSelected) {
      backgroundColor = Colors.indigo[50]!;
      borderColor = Colors.indigo;
    }
    
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 4 : 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 2),
          boxShadow: [if (isSelected && !showFeedback) BoxShadow(color: Colors.indigo.withAlpha(128), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: ListTile(
          leading: Container(
            width: isSmallScreen ? 28 : 32,
            height: isSmallScreen ? 28 : 32,
            decoration: BoxDecoration(
              color: Colors.white, 
              borderRadius: BorderRadius.circular(8), 
              border: Border.all(color: borderColor)
            ),
            child: Center(
              child: Text(
                String.fromCharCode(65 + index), 
                style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  color: textColor, 
                  fontSize: isSmallScreen ? 12 : 14
                )
              ),
            ),
          ),
          title: Text(
            answer, 
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16, 
              color: textColor, 
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal
            )
          ),
          trailing: showFeedback 
              ? Icon(
                  isCorrect ? Icons.check_circle : Icons.cancel, 
                  color: isCorrect ? Colors.green : Colors.red, 
                  size: isSmallScreen ? 20 : 24
                ) 
              : null,
          onTap: showFeedback ? null : () => _answerQuestion(answer),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildQuizQuestion() {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    if (_showCategorySelection || !_quizStarted) {
      return _buildMentorSelection();
    }

    if (_quizQuestions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.quiz_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No quiz questions available.', 
              style: TextStyle(fontSize: isSmallScreen ? 14 : 16, color: Colors.grey)
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _backToMentorSelection,
              child: Text('Choose Different Mentor'),
            ),
          ],
        ),
      );
    }

    if (_quizFinished) {
      return _buildQuizResult();
    }

    final currentQuestion = _quizQuestions[_quizIndex];
    final questionType = currentQuestion['question_type']?.toString() ?? 'multiple_choice';
    final correctAnswers = List<String>.from(currentQuestion['correct_answers'] ?? []);
    final isCorrect = _selectedAnswer != null && correctAnswers.contains(_selectedAnswer);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mentor info and back button
        if (!_quizFinished) ...[
          Card(
            margin: EdgeInsets.only(bottom: isSmallScreen ? 12 : 16),
            child: Padding(
              padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
              child: Row(
                children: [
                  Container(
                    width: isSmallScreen ? 40 : 48,
                    height: isSmallScreen ? 40 : 48,
                    decoration: BoxDecoration(
                      color: Colors.purple[100],
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(
                      Icons.person,
                      color: Colors.purple,
                      size: isSmallScreen ? 20 : 24,
                    ),
                  ),
                  SizedBox(width: isSmallScreen ? 12 : 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedMentor ?? 'Mentor',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isSmallScreen ? 16 : 18,
                            color: Colors.purple[800],
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Quiz by ${_selectedMentor ?? 'Mentor'}',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 14,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _backToMentorSelection,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[300],
                      foregroundColor: Colors.grey[800],
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Change Mentor',
                      style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        
        // Quiz content 
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_quizFinished) _buildQuizHeader(),
            _buildQuestionCard(currentQuestion),
            SizedBox(height: isSmallScreen ? 12 : 16),
            _buildAnswerOptions(currentQuestion),
            if (_showAnswerFeedback && questionType == 'multiple_choice') ...[
              SizedBox(height: isSmallScreen ? 12 : 16),
              Container(
                padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                decoration: BoxDecoration(
                  color: isCorrect ? Colors.green[50]! : Colors.red[50]!,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isCorrect ? Colors.green : Colors.red),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isCorrect ? 'Correct! Well done!' : 'Incorrect.',
                      style: TextStyle(
                        color: isCorrect ? Colors.green[800]! : Colors.red[800]!, 
                        fontWeight: FontWeight.bold, 
                        fontSize: isSmallScreen ? 14 : 16
                      ),
                    ),
                    if (!isCorrect && correctAnswers.isNotEmpty) ...[
                      SizedBox(height: isSmallScreen ? 4 : 6),
                      Text(
                        'Correct answer${correctAnswers.length > 1 ? 's' : ''}: ${correctAnswers.join(', ')}',
                        style: TextStyle(
                          color: Colors.green[800]!,
                          fontSize: isSmallScreen ? 12 : 14,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildQuizStats() {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem(Icons.timer, 'Time', '${_quizTimeSeconds}s', isSmallScreen),
            _buildStatItem(Icons.psychology, 'Questions', '${_quizQuestions.length}', isSmallScreen),
            _buildStatItem(Icons.category, 'Categories', 'Mixed', isSmallScreen),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value, bool isSmallScreen) {
    return Column(
      children: [
        Icon(icon, size: isSmallScreen ? 18 : 20, color: Colors.grey[600]),
        SizedBox(height: isSmallScreen ? 2 : 4),
        Text(label, style: TextStyle(fontSize: isSmallScreen ? 10 : 12, color: Colors.grey[600])),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: isSmallScreen ? 12 : 14)),
      ],
    );
  }

  String _getPerformanceMessage(double percentage) {
    if (percentage >= 90) return 'Excellent work! You have mastered this material.';
    if (percentage >= 70) return 'Good job! You have a solid understanding.';
    if (percentage >= 50) return 'Not bad! Some areas need more practice.';
    return 'Keep studying! Review the material and try again.';
  }

  Widget _buildQuizResult() {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    final percentage = (_score / _quizQuestions.length) * 100;
    final isPerfect = _score == _quizQuestions.length;
    final isGoodScore = percentage >= 70;
    
    return Column(
      children: [
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
            child: Column(
              children: [
                Icon(
                  isPerfect ? Icons.emoji_events : isGoodScore ? Icons.check_circle : Icons.autorenew,
                  size: isSmallScreen ? 48 : 64,
                  color: isPerfect ? Colors.amber : isGoodScore ? Colors.green : Colors.orange,
                ),
                SizedBox(height: isSmallScreen ? 12 : 16),
                Text(isPerfect ? 'Perfect Score!' : isGoodScore ? 'Great Job!' : 'Keep Practicing!', style: TextStyle(fontSize: isSmallScreen ? 20 : 24, fontWeight: FontWeight.bold)),
                SizedBox(height: isSmallScreen ? 6 : 8),
                Text('$_score / ${_quizQuestions.length} (${percentage.toStringAsFixed(1)}%)', style: TextStyle(fontSize: isSmallScreen ? 16 : 20, color: Colors.grey[700])),
                SizedBox(height: isSmallScreen ? 12 : 16),
                Text(_getPerformanceMessage(percentage), textAlign: TextAlign.center, style: TextStyle(fontSize: isSmallScreen ? 14 : 16, color: Colors.grey[600], height: 1.5)),
              ],
            ),
          ),
        ),
        SizedBox(height: isSmallScreen ? 16 : 24),
        _buildQuizStats(),
        SizedBox(height: isSmallScreen ? 16 : 24),
        Row(
          children: [
            // Back to mentor selection button
            Expanded(
              child: OutlinedButton(
                onPressed: _backToMentorSelection,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 14 : 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: Colors.indigo),
                ),
                child: Text(
                  'Choose Different Mentor',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 16 : 18,
                    color: Colors.indigo,
                    fontWeight: FontWeight.bold
                  ),
                ),
              ),
            ),
            SizedBox(width: isSmallScreen ? 12 : 16),
            // New quiz 
            Expanded(
              child: ElevatedButton(
                onPressed: _resetQuiz,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 14 : 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'New Quiz',
                  style: TextStyle(fontSize: isSmallScreen ? 16 : 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Map<String, dynamic>> _generateFallbackArticles() {
    return [
      {
        'title': 'Welcome to Learning Tools',
        'content': 'This is a sample article. Connect to the internet to load real content.',
        'mentor_name': 'CodexHub Team',
        'uploaded_at': DateTime.now().toString(),
        'has_attachment': false,
        'has_valid_file': false,
      }
    ];
  }

  List<Map<String, dynamic>> _generateFallbackQuiz() {
    return [
      {
        'question': 'What is Flutter primarily used for?',
        'category': 'Mobile Development',
        'answers': ['Web development', 'Mobile app development', 'Data analysis', 'Game development'],
        'correct_answers': ['Mobile app development'],
        'question_type': 'multiple_choice',
        'difficulty': 'Easy',
      },
      {
        'question': 'Which programming language does Flutter use?',
        'category': 'Mobile Development',
        'answers': ['Java', 'Kotlin', 'Dart', 'Swift'],
        'correct_answers': ['Dart'],
        'question_type': 'multiple_choice',
        'difficulty': 'Easy',
      },
      {
        'question': 'Explain the benefits of using Flutter for cross-platform development.',
        'category': 'Mobile Development',
        'answers': [],
        'correct_answers': [],
        'question_type': 'essay',
        'difficulty': 'Medium',
      },
    ];
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final isVerySmallScreen = screenSize.width < 400;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Learning Tools'),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshData,
              tooltip: 'Refresh content',
            ),
          ],
          bottom: TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.lightBlueAccent,
            tabs: [
              Tab(icon: const Icon(Icons.article), text: isVerySmallScreen ? null : 'Materials'),
              Tab(icon: const Icon(Icons.video_library), text: isVerySmallScreen ? null : 'Videos'),
              Tab(icon: const Icon(Icons.quiz), text: isVerySmallScreen ? null : 'Quiz'),
            ],
          ),
        ),
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  children: [
                    RefreshIndicator(
                      onRefresh: _refreshData,
                      child: _articles.isEmpty
                          ? Center(child: Text('No articles available', style: TextStyle(fontSize: isSmallScreen ? 14 : 16, color: Colors.grey)))
                          : ListView(
                              padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                              children: _articles.map((article) => _buildArticleCard(article)).toList(),
                            ),
                    ),
                    _videoIds.isEmpty
                        ? Center(child: Text('No videos available', style: TextStyle(fontSize: isSmallScreen ? 14 : 16, color: Colors.grey)))
                        : ListView(
                            padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                            children: _videoIds.entries.map((entry) => _buildVideoSection(entry.key, entry.value)).toList(),
                          ),
                    _buildQuizTab(isSmallScreen), 
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildQuizTab(bool isSmallScreen) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_showCategorySelection || !_quizStarted)
                  _buildMentorSelection()
                else if (_quizFinished)
                  _buildQuizResult()
                else
                  _buildQuizQuestion(),
                
                if (_quizStarted && !_quizFinished) ...[
                  SizedBox(height: isSmallScreen ? 16 : 20),
                  LinearProgressIndicator(
                    value: _quizIndex / _quizQuestions.length,
                    backgroundColor: Colors.grey[300],
                    color: Colors.indigo,
                    minHeight: isSmallScreen ? 10 : 12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  SizedBox(height: isSmallScreen ? 6 : 8),
                  Text(
                    'Progress: $_quizIndex/${_quizQuestions.length} questions', 
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: isSmallScreen ? 12 : 14)
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}