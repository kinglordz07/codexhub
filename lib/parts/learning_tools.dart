import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';

/// LEARNING TOOLS WIDGET
class LearningTools extends StatefulWidget {
  const LearningTools({super.key});

  @override
  State<LearningTools> createState() => _LearningToolsState();
}

class _LearningToolsState extends State<LearningTools> {
  bool _isLoading = true;
  StreamSubscription? _articlesSubscription;

  List<Map<String, dynamic>> _articles = [];
  List<Map<String, dynamic>> _quizQuestions = [];
  Map<String, List<String>> _videoIds = {};
  final Map<String, List<YoutubePlayerController>> _videoControllers = {};

  // Quiz state variables
  int _quizIndex = 0;
  int _score = 0;
  bool _quizFinished = false;
  String? _selectedAnswer;
  bool _showAnswerFeedback = false;
  int _quizTimeSeconds = 0;
  late Timer _quizTimer;
  final List<Map<String, dynamic>> _answeredQuestions = [];

  @override
  void initState() {
    super.initState();
    _loadContent();
    _subscribeToArticles();
    _startQuizTimer();
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

  // Add real-time subscription
  void _subscribeToArticles() {
    ('🔔 Subscribing to articles real-time updates...');
    final client = Supabase.instance.client;

    _articlesSubscription = client
        .from('articles')
        .stream(primaryKey: ['id'])
        .listen(
          (List<Map<String, dynamic>> data) {
            ('🔄 Real-time update: ${data.length} articles');
            setState(() {
              _articles = _processArticles(data);
            });
          },
          onError: (error) {
            ('❌ Real-time subscription error: $error');
          },
        );
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });
    await _loadContent();
  }

  // Enhanced download method that handles files from both sources
  Future<void> _downloadFile(Map<String, dynamic> article) async {
    try {
      final String? fileName = article['file_name'];
      final String? filePath = article['file_path'];

      ('📥 Starting download: $fileName, path: $filePath');

      if (fileName == null || filePath == null) {
        _showSnackBar('No file available for download', Colors.orange);
        return;
      }

      // Request storage permissions
      final permissionStatus = await _requestStoragePermissions();
      if (!permissionStatus) {
        _showSnackBar(
          'Storage permission is required to download files',
          Colors.red,
        );
        return;
      }

      setState(() {
        _isLoading = true;
      });

      final client = Supabase.instance.client;

      // Get the downloads directory
      final Directory downloadsDir = await getApplicationDocumentsDirectory();
      final String localPath = '${downloadsDir.path}/$fileName';
      final File file = File(localPath);

      ('📁 Downloading to: $localPath');

      // Check if file already exists
      if (await file.exists()) {
        final result = await OpenFilex.open(localPath);
        _showSnackBar('File already exists. Opening...', Colors.blue);
        ('File open result: ${result.message}');
        setState(() {
          _isLoading = false;
        });
        return;
      }

      // Determine which storage bucket to use based on file path
      String storageBucket = 'resources'; // Default bucket
      String actualFilePath = filePath;

      // If file path contains 'resource-library/', use 'learning_files' bucket
      if (filePath.contains('resource-library/')) {
        storageBucket = 'learning_files';
        // Extract just the filename for learning_files bucket
        actualFilePath = filePath.replaceFirst('resource-library/', '');
      }

      ('🪣 Using storage bucket: $storageBucket');
      ('📁 Actual file path: $actualFilePath');

      // Download the file from the appropriate Supabase storage bucket
      final response = await client.storage
          .from(storageBucket)
          .download(actualFilePath);

      // Write the file
      await file.writeAsBytes(response);

      setState(() {
        _isLoading = false;
      });

      ('✅ File downloaded successfully: $localPath');

      // Try to open the file
      final result = await OpenFilex.open(localPath);

      _showSnackBar('"$fileName" downloaded successfully!', Colors.green);

      ('File open result: ${result.message}');
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ('❌ Error downloading file: $e');
      _showSnackBar('Download failed: ${e.toString()}', Colors.red);
    }
  }

  // Helper method to request storage permissions
  Future<bool> _requestStoragePermissions() async {
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
        if (!status.isGranted) {
          return false;
        }
      }
    }
    return true;
  }

  // Helper method to show snackbars
  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _articlesSubscription?.cancel();
    _quizTimer.cancel();
    for (final controllerList in _videoControllers.values) {
      for (final controller in controllerList) {
        controller.close();
      }
    }
    super.dispose();
  }

  // Process articles to extract file information
  List<Map<String, dynamic>> _processArticles(
    List<Map<String, dynamic>> articles,
  ) {
    return articles.map((article) {
      // Enhanced file attachment detection
      bool hasAttachment = article['has_attachment'] == true;
      String? fileName = article['file_name']?.toString();
      String? filePath = article['file_path']?.toString();

      bool hasValidFile =
          fileName != null &&
          filePath != null &&
          fileName.isNotEmpty &&
          filePath.isNotEmpty;

      // Extract mentor name
      String mentorName = _extractMentorName(article);

      return {
        ...article,
        'display_uploaded_by': mentorName,
        'mentor_name': mentorName,
        // Enhanced file detection
        'has_attachment': hasAttachment,
        'has_valid_file': hasValidFile,
        'file_name': fileName,
        'file_path': filePath,
      };
    }).toList();
  }

  Future<void> _loadContent() async {
  try {
    ('🔄 Loading content for Learning Tools...');
    final client = Supabase.instance.client;

    // Query articles with file attachment information
    final articlesResponse = await client
        .from('articles')
        .select()
        .order('created_at', ascending: false);

    final videosResponse = await client.from('videos').select();

    List<Map<String, dynamic>> quizResponse = [];
    try {
      quizResponse = await client.from('quizzes').select().eq('is_active', true);
      ('✅ Quizzes loaded successfully: ${quizResponse.length} questions');
      
      // Process quiz questions to match the expected format
      quizResponse = quizResponse.map((quiz) {
        return {
          'question': quiz['question'],
          'category': quiz['category'],
          'answers': quiz['answers'] ?? [],
          'correct': (quiz['correct_answers'] as List?)?.first ?? '', 
          'difficulty': quiz['difficulty'] ?? 'Medium',
        };
      }).toList();
      
    } catch (e) {
      ('⚠️ Quizzes table not found or error loading, using generated questions instead: $e');
      quizResponse = _generateFallbackQuiz();
    }

    if (quizResponse.isEmpty) {
      ('⚠️ No quiz questions found, using fallback');
      quizResponse = _generateFallbackQuiz();
    }

    ('📚 Articles fetched: ${articlesResponse.length}');

    // Debug: Print file information for each article
    for (var article in articlesResponse) {
      ('📄 Article: ${article['title']}');
      ('   - Has attachment: ${article['has_attachment']}');
      ('   - File name: ${article['file_name']}');
      ('   - File path: ${article['file_path']}');
    }

    // Process articles to include file information
    final processedArticles = _processArticles(articlesResponse);

    setState(() {
      _articles = processedArticles;
      ('📝 Articles in state: ${_articles.length}');

      // Process videos
      _videoIds = {};
      for (var v in videosResponse) {
        final lang = v['title'] as String? ?? 'Unknown';
        final videoId = v['youtube_id'] as String?;

        if (videoId != null && videoId.isNotEmpty) {
          if (!_videoIds.containsKey(lang)) {
            _videoIds[lang] = [];
          }
          _videoIds[lang]!.add(videoId);
        }
      }

      // If no videos from database, use fallback videos
      if (_videoIds.isEmpty) {
        ('⚠️ No videos found in database, using fallback videos');
        _videoIds = {
          'Java': ['grEKMHGYyns', 'm-5NkCgFz-s', 'WPvGqX-TXP0'],
          'Python': ['rfscVS0vtbw', 'kqtD5dpn9C8', 'JJmcL1N2KQs'],
          'VB.NET': ['m3g8Ma0Tye0', 'F3Fk6s7LQ_c'],
          'C#': ['GhQdlIFylQ8', 'pSiIHe2uEY2', 'gCyGa2aBAl8'],
        };
      }

      _quizQuestions = quizResponse;
      _quizQuestions.shuffle(Random());
      _createVideoControllers();
      _isLoading = false;
    });
  } catch (e) {
    ('❌ Error loading content: $e');
    setState(() {
      _articles = _generateFallbackArticles();
      _videoIds = {
        'Java': ['grEKMHGYyns', 'm-5NkCgFz-s', 'WPvGqX-TXP0'],
        'Python': ['rfscVS0vtbw', 'kqtD5dpn9C8', 'JJmcL1N2KQs'],
        'VB.NET': ['m3g8Ma0Tye0', 'F3Fk6s7LQ_c'],
        'C#': ['GhQdlIFylQ8', 'pSiIHe2uEY2', 'gCyGa2aBAl8'],
      };
      _quizQuestions = _generateFallbackQuiz();
      _createVideoControllers();
      _isLoading = false;
    });
  }
}

  void _createVideoControllers() {
    for (final controllerList in _videoControllers.values) {
      for (final controller in controllerList) {
        controller.close();
      }
    }
    _videoControllers.clear();

    for (final lang in _videoIds.keys) {
      if (!_videoControllers.containsKey(lang)) {
        _videoControllers[lang] = [];
      }

      for (final id in _videoIds[lang]!) {
        try {
          final controller = YoutubePlayerController(
            params: const YoutubePlayerParams(
              showFullscreenButton: true,
              mute: false,
              playsInline: false,
              strictRelatedVideos: true,
              enableCaption: false,
            ),
          );
          controller.loadVideoById(videoId: id);
          _videoControllers[lang]!.add(controller);
        } catch (e) {
          ('Error creating controller for $lang: $id - $e');
        }
      }
    }
  }

  // Helper method to extract mentor name
  String _extractMentorName(Map<String, dynamic> data) {
    if (data['mentor_name'] != null &&
        data['mentor_name'].toString().isNotEmpty) {
      return data['mentor_name'].toString();
    } else if (data['uploaded_by_name'] != null &&
        data['uploaded_by_name'].toString().isNotEmpty) {
      return data['uploaded_by_name'].toString();
    } else if (data['user_name'] != null &&
        data['user_name'].toString().isNotEmpty) {
      return data['user_name'].toString();
    } else if (data['display_uploaded_by'] != null &&
        data['display_uploaded_by'].toString().isNotEmpty) {
      return data['display_uploaded_by'].toString();
    } else if (data['uploaded_by'] != null &&
        data['uploaded_by'].toString().isNotEmpty) {
      final uploadedBy = data['uploaded_by'].toString();
      if (uploadedBy.contains('@')) {
        return uploadedBy;
      } else if (uploadedBy.length > 8) {
        return 'User ${uploadedBy.substring(0, 8)}...';
      } else {
        return 'User $uploadedBy';
      }
    }
    return 'CodexHub Mentor';
  }

  // Helper method to format upload time
  String _formatUploadTime(dynamic uploadedAt) {
    try {
      if (uploadedAt != null) {
        final date = DateTime.parse(uploadedAt);
        return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      ('⚠️ Error parsing upload time: $e');
    }
    return 'Recently';
  }

  Widget _buildArticleCard(Map<String, dynamic> article) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final isVerySmallScreen = screenSize.width < 400;

    String title = article['title']?.toString() ?? "Untitled";
    String content = article['content']?.toString() ?? "";
    String preview =
        content.length > 80 ? "${content.substring(0, 80)}..." : content;

    String uploadedBy = _extractMentorName(article);
    String uploadedAt = _formatUploadTime(article['uploaded_at']);

    // File detection
    bool hasValidFile = article['has_valid_file'] == true;
    String? fileName = article['file_name']?.toString();

    ('🔄 Building article card: $title');
    ('   - Has valid file: $hasValidFile');
    ('   - File name: $fileName');

    return Card(
      margin: EdgeInsets.symmetric(vertical: isSmallScreen ? 6 : 8),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          border:
              hasValidFile ? Border.all(color: Colors.green, width: 2) : null,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.attach_file,
                        size: isSmallScreen ? 12 : 14,
                        color: Colors.green[700],
                      ),
                      if (!isVerySmallScreen) ...[
                        const SizedBox(width: 4),
                        Text(
                          'File',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 10 : 12,
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 14, 
                  color: Colors.grey
                ),
              ),
              SizedBox(height: isSmallScreen ? 2 : 4),
              Row(
                children: [
                  Icon(Icons.person_outline, size: isSmallScreen ? 10 : 12, color: Colors.grey),
                  SizedBox(width: isSmallScreen ? 2 : 4),
                  Expanded(
                    child: Text(
                      'By: $uploadedBy',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 10 : 12, 
                        color: Colors.grey[600]
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: isSmallScreen ? 4 : 8),
                  Icon(Icons.calendar_today, size: isSmallScreen ? 10 : 12, color: Colors.grey),
                  SizedBox(width: isSmallScreen ? 2 : 4),
                  Text(
                    uploadedAt,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 10 : 12, 
                      color: Colors.grey[600]
                    ),
                  ),
                ],
              ),
            ],
          ),
          trailing:
              hasValidFile
                  ? IconButton(
                    icon: Icon(
                      Icons.download, 
                      color: Colors.green, 
                      size: isSmallScreen ? 20 : 24
                    ),
                    onPressed: () => _downloadFile(article),
                    tooltip: 'Download $fileName',
                  )
                  : null,
          children: [
            Padding(
              padding: EdgeInsets.all(isSmallScreen ? 12.0 : 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Content
                  Text(
                    content,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16, 
                      height: 1.5
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 12 : 16),

                  // File Download Section
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
                            Row(
                              children: [
                                Icon(Icons.attach_file, color: Colors.green),
                                SizedBox(width: isSmallScreen ? 6 : 8),
                                Text(
                                  'Attached File:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[800],
                                    fontSize: isSmallScreen ? 14 : 16,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: isSmallScreen ? 6 : 8),
                            Text(
                              fileName!,
                              style: TextStyle(
                                color: Colors.green[700],
                                fontSize: isSmallScreen ? 12 : 14,
                              ),
                            ),
                            SizedBox(height: isSmallScreen ? 8 : 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _downloadFile(article),
                                icon: Icon(
                                  Icons.download, 
                                  size: isSmallScreen ? 18 : 20
                                ),
                                label: Text(
                                  'Download File',
                                  style: TextStyle(
                                    fontSize: isSmallScreen ? 14 : 16
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                    vertical: isSmallScreen ? 10 : 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  SizedBox(height: isSmallScreen ? 12 : 16),

                  // Upload info section
                  Container(
                    padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline, 
                          size: isSmallScreen ? 14 : 16, 
                          color: Colors.grey
                        ),
                        SizedBox(width: isSmallScreen ? 6 : 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Uploaded by $uploadedBy on $uploadedAt',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 12 : 14,
                                  color: Colors.grey[700],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              if (hasValidFile)
                                Padding(
                                  padding: EdgeInsets.only(top: isSmallScreen ? 2.0 : 4.0),
                                  child: Text(
                                    'File: $fileName',
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 10 : 12,
                                      color: Colors.grey[600],
                                    ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSection(String title, List<String> videoIds) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
   

    final controllers = _videoControllers[title] ?? [];

    if (controllers.isEmpty) {
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
          Container(
            height: isSmallScreen ? 150 : 200,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.videocam_off, 
                    size: isSmallScreen ? 30 : 40, 
                    color: Colors.grey
                  ),
                  SizedBox(height: isSmallScreen ? 6 : 8),
                  Text(
                    'No videos available',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      color: Colors.grey
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: isSmallScreen ? 12 : 16),
        ],
      );
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
          height: isSmallScreen ? 180 : 220,
          child: PageView.builder(
            itemCount: controllers.length,
            itemBuilder: (context, index) {
              final controller = controllers[index];
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 6 : 8),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Color.lerp(Colors.black, Colors.transparent, 0.7)!,
                        blurRadius: 5,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: YoutubePlayer(
                      controller: controller,
                      aspectRatio: 16 / 9,
                    ),
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

  // Enhanced Quiz Methods

  void _answerQuestion(String answer) {
    if (_quizFinished || _showAnswerFeedback) return;

    setState(() {
      _selectedAnswer = answer;
      _showAnswerFeedback = true;
    });

    final correct = _quizQuestions[_quizIndex]['correct'] as String;
    final isCorrect = answer == correct;
    
    if (isCorrect) _score++;

    // Store answer for tracking
    _answeredQuestions.add({
      'question': _quizQuestions[_quizIndex]['question'],
      'userAnswer': answer,
      'correctAnswer': correct,
      'isCorrect': isCorrect,
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
    setState(() {
      _quizIndex = 0;
      _score = 0;
      _quizFinished = false;
      _quizTimeSeconds = 0;
      _selectedAnswer = null;
      _showAnswerFeedback = false;
      _answeredQuestions.clear();
      _quizQuestions.shuffle(Random());
    });
  }

  Widget _buildQuizHeader() {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Card(
      margin: EdgeInsets.only(bottom: isSmallScreen ? 12 : 16),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Progress indicator
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Question ${_quizIndex + 1} of ${_quizQuestions.length}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isSmallScreen ? 14 : 16,
                      ),
                    ),
                    SizedBox(height: isSmallScreen ? 2 : 4),
                    Container(
                      width: isSmallScreen ? 120 : 150,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: Colors.grey[300],
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (_quizIndex + 1) / _quizQuestions.length,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: Colors.indigo,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                
                // Timer
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer, 
                      size: isSmallScreen ? 14 : 16, 
                      color: Colors.grey[600]
                    ),
                    SizedBox(width: isSmallScreen ? 2 : 4),
                    Text(
                      '${_quizTimeSeconds}s',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 12 : 14,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            SizedBox(height: isSmallScreen ? 6 : 8),
            
            // Score indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.quiz, 
                  size: isSmallScreen ? 14 : 16, 
                  color: Colors.indigo
                ),
                SizedBox(width: isSmallScreen ? 2 : 4),
                Text(
                  'Score: $_score/${_quizQuestions.length}',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 12 : 14,
                    color: Colors.indigo,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(Map<String, dynamic> question) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question text
            Text(
              question['question'] as String,
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 18,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            
            // Category tag
            if (question['category'] != null) ...[
              SizedBox(height: isSmallScreen ? 8 : 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue),
                ),
                child: Text(
                  question['category'] as String,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 10 : 12,
                    color: Colors.blue[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnswerOptions(Map<String, dynamic> question) {
    return Column(
      children: (question['answers'] as List).asMap().entries.map((entry) {
        final index = entry.key;
        final answer = entry.value;
        return _buildEnhancedAnswerButton(question, answer, index);
      }).toList(),
    );
  }

  Widget _buildEnhancedAnswerButton(Map<String, dynamic> question, String answer, int index) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    final isSelected = _selectedAnswer == answer;
    final isCorrect = answer == question['correct'];
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
          boxShadow: [
            if (isSelected && !showFeedback)
              BoxShadow(
                color: Colors.indigo.withAlpha(51), // 0.2 opacity
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: ListTile(
          leading: Container(
            width: isSmallScreen ? 28 : 32,
            height: isSmallScreen ? 28 : 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
            ),
            child: Center(
              child: Text(
                String.fromCharCode(65 + index), // A, B, C, D
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  fontSize: isSmallScreen ? 12 : 14,
                ),
              ),
            ),
          ),
          title: Text(
            answer,
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              color: textColor,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          trailing: showFeedback
              ? Icon(
                  isCorrect ? Icons.check_circle : Icons.cancel,
                  color: isCorrect ? Colors.green : Colors.red,
                  size: isSmallScreen ? 20 : 24,
                )
              : null,
          onTap: showFeedback ? null : () => _answerQuestion(answer),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildQuizQuestion() {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    if (_quizQuestions.isEmpty) {
      return Center(
        child: Text(
          'No quiz questions available.',
          style: TextStyle(
            fontSize: isSmallScreen ? 14 : 16, 
            color: Colors.grey
          ),
        ),
      );
    }

    final q = _quizQuestions[_quizIndex];
    final correctAnswer = q['correct'] as String;
    final isCorrect = _selectedAnswer == correctAnswer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildQuizHeader(),
        _buildQuestionCard(q),
        SizedBox(height: isSmallScreen ? 12 : 16),
        _buildAnswerOptions(q),
        if (_showAnswerFeedback) ...[
          SizedBox(height: isSmallScreen ? 12 : 16),
          Container(
            padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
            decoration: BoxDecoration(
              color: isCorrect ? Colors.green[50]! : Colors.red[50]!,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isCorrect ? Colors.green : Colors.red),
            ),
            child: Text(
              isCorrect
                  ? 'Correct! Well done!'
                  : 'Incorrect. The correct answer is: $correctAnswer',
              style: TextStyle(
                color: isCorrect ? Colors.green[800]! : Colors.red[800]!,
                fontWeight: FontWeight.bold,
                fontSize: isSmallScreen ? 14 : 16,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQuizStats() {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

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
        Text(
          label,
          style: TextStyle(
            fontSize: isSmallScreen ? 10 : 12, 
            color: Colors.grey[600]
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isSmallScreen ? 12 : 14,
          ),
        ),
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
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

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
                  isPerfect ? Icons.emoji_events : 
                  isGoodScore ? Icons.check_circle : Icons.autorenew,
                  size: isSmallScreen ? 48 : 64,
                  color: isPerfect ? Colors.amber : 
                         isGoodScore ? Colors.green : Colors.orange,
                ),
                SizedBox(height: isSmallScreen ? 12 : 16),
                Text(
                  isPerfect ? 'Perfect Score!' :
                  isGoodScore ? 'Great Job!' : 'Keep Practicing!',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 20 : 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: isSmallScreen ? 6 : 8),
                Text(
                  '$_score / ${_quizQuestions.length} (${percentage.toStringAsFixed(1)}%)',
                  style: TextStyle(
                    fontSize: isSmallScreen ? 16 : 20,
                    color: Colors.grey[700],
                  ),
                ),
                SizedBox(height: isSmallScreen ? 12 : 16),
                Text(
                  _getPerformanceMessage(percentage),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 14 : 16,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: isSmallScreen ? 16 : 24),
        _buildQuizStats(),
        SizedBox(height: isSmallScreen ? 16 : 24),
        // REMOVED "Try Again" button - only keep "New Quiz"
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _resetQuiz,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 14 : 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'New Quiz',
              style: TextStyle(
                fontSize: isSmallScreen ? 16 : 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Add missing helper methods
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
        'correct': 'Mobile app development',
        'difficulty': 'Easy',
      },
      {
        'question': 'Which programming language does Flutter use?',
        'category': 'Mobile Development',
        'answers': ['Java', 'Kotlin', 'Dart', 'Swift'],
        'correct': 'Dart',
        'difficulty': 'Easy',
      },
      {
        'question': 'What widget would you use for a scrollable list?',
        'category': 'Flutter Widgets',
        'answers': ['Container', 'Column', 'ListView', 'Stack'],
        'correct': 'ListView',
        'difficulty': 'Medium',
      },
      {
        'question': 'Which method is called when a StatefulWidget is first created?',
        'category': 'Flutter Basics',
        'answers': ['initState()', 'build()', 'createState()', 'dispose()'],
        'correct': 'initState()',
        'difficulty': 'Medium',
      },
      {
        'question': 'What does "hot reload" do in Flutter?',
        'category': 'Development',
        'answers': [
          'Restarts the app completely',
          'Updates the UI without losing app state',
          'Clears all data',
          'Deploys to production'
        ],
        'correct': 'Updates the UI without losing app state',
        'difficulty': 'Easy',
      },
      {
        'question': 'Which widget is used for responsive layouts?',
        'category': 'Layout',
        'answers': ['Flexible', 'Expanded', 'Container', 'Both Flexible and Expanded'],
        'correct': 'Both Flexible and Expanded',
        'difficulty': 'Medium',
      },
      {
        'question': 'What is the purpose of the pubspec.yaml file?',
        'category': 'Project Structure',
        'answers': [
          'Defines app permissions',
          'Manages dependencies and assets',
          'Configures app themes',
          'Sets up routing'
        ],
        'correct': 'Manages dependencies and assets',
        'difficulty': 'Easy',
      },
      {
        'question': 'Which package is commonly used for HTTP requests?',
        'category': 'Networking',
        'answers': ['http', 'dio', 'chopper', 'All of the above'],
        'correct': 'All of the above',
        'difficulty': 'Medium',
      },
      {
        'question': 'What is a "BuildContext" in Flutter?',
        'category': 'Advanced Concepts',
        'answers': [
          'The current location in the widget tree',
          'A build configuration file',
          'The app execution context',
          'A debugging tool'
        ],
        'correct': 'The current location in the widget tree',
        'difficulty': 'Hard',
      },
      {
        'question': 'How do you handle state management in large Flutter apps?',
        'category': 'State Management',
        'answers': [
          'setState only',
          'Provider package',
          'Riverpod or Bloc',
          'Both Provider and Riverpod/Bloc'
        ],
        'correct': 'Both Provider and Riverpod/Bloc',
        'difficulty': 'Hard',
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
              Tab(
                icon: const Icon(Icons.article),
                text: isVerySmallScreen ? null : 'Materials',
              ),
              Tab(
                icon: const Icon(Icons.video_library),
                text: isVerySmallScreen ? null : 'Videos',
              ),
              Tab(
                icon: const Icon(Icons.quiz),
                text: isVerySmallScreen ? null : 'Quiz',
              ),
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
                          ? Center(
                              child: Text(
                                'No articles available',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 14 : 16,
                                  color: Colors.grey,
                                ),
                              ),
                            )
                          : ListView(
                              padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                              children: _articles
                                  .map((article) => _buildArticleCard(article))
                                  .toList(),
                            ),
                    ),
                    _videoIds.isEmpty
                        ? Center(
                            child: Text(
                              'No videos available',
                              style: TextStyle(
                                fontSize: isSmallScreen ? 14 : 16, 
                                color: Colors.grey
                              ),
                            ),
                          )
                        : ListView(
                            padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                            children: _videoIds.entries
                                .map((entry) => _buildVideoSection(entry.key, entry.value))
                                .toList(),
                          ),
                    SingleChildScrollView(
                      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                      child: Column(
                        children: [
                          _quizFinished
                              ? _buildQuizResult()
                              : _buildQuizQuestion(),
                          SizedBox(height: isSmallScreen ? 16 : 20),
                          if (!_quizFinished) ...[
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
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: isSmallScreen ? 12 : 14,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}