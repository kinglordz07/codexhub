// ignore_for_file: deprecated_member_use

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

  int _quizIndex = 0;
  int _score = 0;
  bool _quizFinished = false;
  String? _selectedAnswer;
  bool _showAnswerFeedback = false;

  @override
  void initState() {
    super.initState();
    _loadContent();
    _subscribeToArticles();
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
        quizResponse = await client.from('quizzes').select();
        ('✅ Quizzes loaded successfully: ${quizResponse.length} questions',);
      } catch (e) {
        ('⚠️ Quizzes table not found, using generated questions instead');
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

        if (quizResponse.isNotEmpty) {
          _quizQuestions = List<Map<String, dynamic>>.from(quizResponse);
        } else {
          _quizQuestions = _generateFallbackQuiz();
        }

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

  List<Map<String, dynamic>> _generateFallbackQuiz() {
    return [
      {
        "question":
            "Which language is best known for object-oriented programming?",
        "answers": ["Java", "Python", "VB.NET", "C#"],
        "correct": "Java",
      },
      {
        "question": "Which language commonly uses indentation syntax?",
        "answers": ["Java", "Python", "VB.NET", "C#"],
        "correct": "Python",
      },
    ];
  }

  List<Map<String, dynamic>> _generateFallbackArticles() {
    return [
      {
        'title': 'Java Programming',
        'content': 'Learn Java programming basics and advanced concepts.',
        'uploaded_by': 'System Admin',
        'uploaded_at': DateTime.now().toIso8601String(),
        'has_attachment': false,
        'has_valid_file': false,
      },
      {
        'title': 'Python Tutorial',
        'content': 'Complete Python tutorial for beginners.',
        'uploaded_by': 'System Admin',
        'uploaded_at': DateTime.now().toIso8601String(),
        'has_attachment': false,
        'has_valid_file': false,
      },
    ];
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
      margin: const EdgeInsets.symmetric(vertical: 8),
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
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: hasValidFile ? Colors.green[100] : Colors.indigo[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasValidFile ? Icons.attach_file : Icons.article,
              color: hasValidFile ? Colors.green : Colors.indigo,
              size: 20,
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (hasValidFile)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
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
                        size: 14,
                        color: Colors.green[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'File',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.person_outline, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'By: $uploadedBy',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    uploadedAt,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
          ),
          trailing:
              hasValidFile
                  ? IconButton(
                    icon: Icon(Icons.download, color: Colors.green, size: 24),
                    onPressed: () => _downloadFile(article),
                    tooltip: 'Download $fileName',
                  )
                  : null,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Content
                  Text(
                    content,
                    style: const TextStyle(fontSize: 16, height: 1.5),
                  ),
                  const SizedBox(height: 16),

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
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.attach_file, color: Colors.green),
                                const SizedBox(width: 8),
                                Text(
                                  'Attached File:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green[800],
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              fileName!,
                              style: TextStyle(
                                color: Colors.green[700],
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _downloadFile(article),
                                icon: const Icon(Icons.download, size: 20),
                                label: const Text(
                                  'Download File',
                                  style: TextStyle(fontSize: 16),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
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

                  const SizedBox(height: 16),

                  // Upload info section
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Uploaded by $uploadedBy on $uploadedAt',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[700],
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              if (hasValidFile)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text(
                                    'File: $fileName',
                                    style: TextStyle(
                                      fontSize: 12,
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
    final controllers = _videoControllers[title] ?? [];

    if (controllers.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title Tutorials',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_off, size: 40, color: Colors.grey),
                  SizedBox(height: 8),
                  Text(
                    'No videos available',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title Tutorials',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 220,
          child: PageView.builder(
            itemCount: controllers.length,
            itemBuilder: (context, index) {
              final controller = controllers[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.3),
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
        const SizedBox(height: 16),
      ],
    );
  }

  void _answerQuestion(String answer) {
    if (_quizFinished) return;

    setState(() {
      _selectedAnswer = answer;
      _showAnswerFeedback = true;
    });

    final correct = _quizQuestions[_quizIndex]['correct'] as String;
    if (answer == correct) _score++;

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showAnswerFeedback = false;
          _selectedAnswer = null;
          _quizIndex++;
          if (_quizIndex >= _quizQuestions.length) _quizFinished = true;
        });
      }
    });
  }

  void _resetQuiz() {
    setState(() {
      _quizIndex = 0;
      _score = 0;
      _quizFinished = false;
      _quizQuestions.shuffle(Random());
    });
  }

  Widget _buildQuizQuestion() {
    if (_quizQuestions.isEmpty) {
      return const Text('No quiz questions available.');
    }

    final q = _quizQuestions[_quizIndex];
    final correctAnswer = q['correct'] as String;
    final isCorrect = _selectedAnswer == correctAnswer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Question ${_quizIndex + 1} of ${_quizQuestions.length}',
          style: const TextStyle(fontSize: 14, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.indigo[50],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            q['question'] as String,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.indigo,
            ),
          ),
        ),
        const SizedBox(height: 16),
        ...(q['answers'] as List).map((ans) {
          final isSelected = _selectedAnswer == ans;
          final isActuallyCorrect = ans == correctAnswer;

          Color buttonColor = Colors.indigo;
          if (_showAnswerFeedback) {
            if (isSelected) {
              buttonColor = isCorrect ? Colors.green : Colors.red;
            } else if (isActuallyCorrect) {
              buttonColor = Colors.green;
            }
          }

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: ElevatedButton(
              onPressed:
                  _showAnswerFeedback
                      ? null
                      : () => _answerQuestion(ans.toString()),
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(ans.toString()),
            ),
          );
        }),
        if (_showAnswerFeedback) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isCorrect ? Colors.green[50] : Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: isCorrect ? Colors.green : Colors.red),
            ),
            child: Text(
              isCorrect
                  ? 'Correct! Well done!'
                  : 'Incorrect. The correct answer is: $correctAnswer',
              style: TextStyle(
                color: isCorrect ? Colors.green[800] : Colors.red[800],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildQuizResult() {
    final percentage = (_score / _quizQuestions.length) * 100;
    final isGoodScore = percentage >= 70;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isGoodScore ? Colors.green[50] : Colors.orange[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isGoodScore ? Colors.green : Colors.orange,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quiz Completed!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isGoodScore ? Colors.green[800] : Colors.orange[800],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your score: $_score / ${_quizQuestions.length} (${percentage.toStringAsFixed(1)}%)',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                isGoodScore
                    ? 'Great job! You have a good understanding of the material.'
                    : 'Keep practicing! You\'ll improve with more study.',
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton(
            onPressed: _resetQuiz,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Try Again'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
          bottom: const TabBar(
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.article), text: 'Articles'),
              Tab(icon: Icon(Icons.video_library), text: 'Videos'),
              Tab(icon: Icon(Icons.quiz), text: 'Quiz'),
            ],
          ),
        ),
        body:
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                  children: [
                    RefreshIndicator(
                      onRefresh: _refreshData,
                      child:
                          _articles.isEmpty
                              ? const Center(
                                child: Text(
                                  'No articles available',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                              )
                              : ListView(
                                padding: const EdgeInsets.all(16),
                                children:
                                    _articles
                                        .map(
                                          (article) =>
                                              _buildArticleCard(article),
                                        )
                                        .toList(),
                              ),
                    ),
                    _videoIds.isEmpty
                        ? const Center(
                          child: Text(
                            'No videos available',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        )
                        : ListView(
                          padding: const EdgeInsets.all(16),
                          children:
                              _videoIds.entries
                                  .map(
                                    (entry) => _buildVideoSection(
                                      entry.key,
                                      entry.value,
                                    ),
                                  )
                                  .toList(),
                        ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _quizFinished
                              ? _buildQuizResult()
                              : _buildQuizQuestion(),
                          const SizedBox(height: 20),
                          LinearProgressIndicator(
                            value:
                                _quizFinished
                                    ? 1.0
                                    : _quizIndex / _quizQuestions.length,
                            backgroundColor: Colors.grey[300],
                            color: Colors.indigo,
                            minHeight: 12,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _quizFinished
                                ? 'Completed! Score: $_score/${_quizQuestions.length}'
                                : 'Progress: $_quizIndex/${_quizQuestions.length} questions',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}
