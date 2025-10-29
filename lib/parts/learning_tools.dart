import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';

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
  List<Map<String, dynamic>> _videoData = []; // ADDED: Store full video data

  // Quiz state
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

  void _subscribeToArticles() {
    final client = Supabase.instance.client;
    _articlesSubscription = client
        .from('articles')
        .stream(primaryKey: ['id'])
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

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });
    await _loadContent();
  }

  Future<void> _downloadFile(Map<String, dynamic> article) async {
    try {
      final String? fileName = article['file_name'];
      final String? filePath = article['file_path'];

      if (fileName == null || filePath == null) {
        _showSnackBar('No file available for download', Colors.orange);
        return;
      }

      final permissionStatus = await _requestStoragePermissions();
      if (!permissionStatus) {
        _showSnackBar('Storage permission required', Colors.red);
        return;
      }

      setState(() {
        _isLoading = true;
      });

      final client = Supabase.instance.client;
      final Directory downloadsDir = await getApplicationDocumentsDirectory();
      final String localPath = '${downloadsDir.path}/$fileName';
      final File file = File(localPath);

      if (await file.exists()) {
        await OpenFilex.open(localPath);
        _showSnackBar('File already exists. Opening...', Colors.blue);
        setState(() {
          _isLoading = false;
        });
        return;
      }

      String storageBucket = 'resources';
      String actualFilePath = filePath;

      if (filePath.contains('resource-library/')) {
        storageBucket = 'learning_files';
        actualFilePath = filePath.replaceFirst('resource-library/', '');
      }

      final response = await client.storage
          .from(storageBucket)
          .download(actualFilePath);

      await file.writeAsBytes(response);

      setState(() {
        _isLoading = false;
      });

      await OpenFilex.open(localPath);
      _showSnackBar('"$fileName" downloaded successfully!', Colors.green);

    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Download failed: ${e.toString()}', Colors.red);
    }
  }

  Future<bool> _requestStoragePermissions() async {
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
        return status.isGranted;
      }
    }
    return true;
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

  // ADDED: Extract video ID from YouTube URL
  String? _extractVideoIdFromUrl(String url) {
    final regExp = RegExp(
      r'^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#&?]*).*',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(url);
    return (match != null && match.group(7)!.length == 11) ? match.group(7) : null;
  }

  // ADDED: Open YouTube video
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

    final articlesResponse = await client
        .from('articles')
        .select()
        .order('created_at', ascending: false);

    // Load uploaded videos from video_urls table
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

    // ✅ FIX: Make sure this variable is named correctly
    List<Map<String, dynamic>> quizResponse = []; // ✅ CORRECT NAME
    try {
      quizResponse = await client.from('quizzes').select().eq('is_active', true);
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
      quizResponse = _generateFallbackQuiz(); // ✅ CORRECT NAME
    }

    if (quizResponse.isEmpty) { // ✅ CORRECT NAME
      quizResponse = _generateFallbackQuiz(); // ✅ CORRECT NAME
    }

    final processedArticles = _processArticles(articlesResponse);

    setState(() {
      _articles = processedArticles;

      _videoIds = {};
      _videoData = videosResponse;
      
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

      // ✅ FIX: Use the correct variable name
      _quizQuestions = quizResponse; // ✅ NOW THIS SHOULD WORK
      _quizQuestions.shuffle(Random());
      _isLoading = false;
    });
  } catch (e) {
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

  String _extractMentorName(Map<String, dynamic> data) {
    if (data['mentor_name'] != null && data['mentor_name'].toString().isNotEmpty) {
      return data['mentor_name'].toString();
    } else if (data['uploaded_by_name'] != null && data['uploaded_by_name'].toString().isNotEmpty) {
      return data['uploaded_by_name'].toString();
    } else if (data['user_name'] != null && data['user_name'].toString().isNotEmpty) {
      return data['user_name'].toString();
    } else if (data['display_uploaded_by'] != null && data['display_uploaded_by'].toString().isNotEmpty) {
      return data['display_uploaded_by'].toString();
    } else if (data['uploaded_by'] != null && data['uploaded_by'].toString().isNotEmpty) {
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

  // ADDED: Helper to get video uploader name
  String _getVideoUploaderName(Map<String, dynamic> video) {
    try {
      // Check if we have joined profile data
      if (video['profiles_new'] != null) {
        final profile = video['profiles_new'];
        if (profile is Map<String, dynamic> && profile['username'] != null) {
          return profile['username'] as String;
        }
      }
      
      // Fallback to uploaded_by
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
    return 'Recently';
  }

  Widget _buildArticleCard(Map<String, dynamic> article) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    String title = article['title']?.toString() ?? "Untitled";
    String content = article['content']?.toString() ?? "";
    String preview = content.length > 80 ? "${content.substring(0, 80)}..." : content;

    String uploadedBy = _extractMentorName(article);
    String uploadedAt = _formatUploadTime(article['uploaded_at']);

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
            icon: Icon(Icons.download, color: Colors.green, size: isSmallScreen ? 20 : 24),
            onPressed: () => _downloadFile(article),
            tooltip: 'Download $fileName',
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
                              Text('Attached File:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green[800], fontSize: isSmallScreen ? 14 : 16)),
                            ]),
                            SizedBox(height: isSmallScreen ? 6 : 8),
                            Text(fileName!, style: TextStyle(color: Colors.green[700], fontSize: isSmallScreen ? 12 : 14)),
                            SizedBox(height: isSmallScreen ? 8 : 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _downloadFile(article),
                                icon: Icon(Icons.download, size: isSmallScreen ? 18 : 20),
                                label: Text('Download File', style: TextStyle(fontSize: isSmallScreen ? 14 : 16)),
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

  // UPDATED: Enhanced video section that shows video_urls data
  Widget _buildVideoSection(String title, List<String> videoIds) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    // Find videos in this category from video_urls table
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
                    children: [
                      // YouTube thumbnail
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
        Text('$title Tutorials', style: TextStyle(fontSize: isSmallScreen ? 16 : 18, fontWeight: FontWeight.bold)),
        SizedBox(height: isSmallScreen ? 6 : 8),
        Container(
          height: isSmallScreen ? 150 : 200,
          decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(12)),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam_off, size: isSmallScreen ? 30 : 40, color: Colors.grey),
                SizedBox(height: isSmallScreen ? 6 : 8),
                Text('No videos available', style: TextStyle(fontSize: isSmallScreen ? 14 : 16, color: Colors.grey)),
                SizedBox(height: isSmallScreen ? 4 : 6),
                Text('Add videos from Resource Library', style: TextStyle(fontSize: isSmallScreen ? 12 : 14, color: Colors.grey)),
              ],
            ),
          ),
        ),
        SizedBox(height: isSmallScreen ? 12 : 16),
      ],
    );
  }

  // Quiz Methods (remain the same)
  void _answerQuestion(String answer) {
    if (_quizFinished || _showAnswerFeedback) return;

    setState(() {
      _selectedAnswer = answer;
      _showAnswerFeedback = true;
    });

    final correct = _quizQuestions[_quizIndex]['correct'] as String;
    final isCorrect = answer == correct;
    
    if (isCorrect) _score++;

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
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestionCard(Map<String, dynamic> question) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(question['question'] as String, style: TextStyle(fontSize: isSmallScreen ? 16 : 18, fontWeight: FontWeight.w600, height: 1.4)),
            if (question['category'] != null) ...[
              SizedBox(height: isSmallScreen ? 8 : 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.blue)),
                child: Text(question['category'] as String, style: TextStyle(fontSize: isSmallScreen ? 10 : 12, color: Colors.blue[700], fontWeight: FontWeight.w500)),
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
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

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
          boxShadow: [if (isSelected && !showFeedback) BoxShadow(color: Colors.indigo.withAlpha(128), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: ListTile(
          leading: Container(
            width: isSmallScreen ? 28 : 32,
            height: isSmallScreen ? 28 : 32,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: borderColor)),
            child: Center(child: Text(String.fromCharCode(65 + index), style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: isSmallScreen ? 12 : 14))),
          ),
          title: Text(answer, style: TextStyle(fontSize: isSmallScreen ? 14 : 16, color: textColor, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
          trailing: showFeedback ? Icon(isCorrect ? Icons.check_circle : Icons.cancel, color: isCorrect ? Colors.green : Colors.red, size: isSmallScreen ? 20 : 24) : null,
          onTap: showFeedback ? null : () => _answerQuestion(answer),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildQuizQuestion() {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    if (_quizQuestions.isEmpty) {
      return Center(child: Text('No quiz questions available.', style: TextStyle(fontSize: isSmallScreen ? 14 : 16, color: Colors.grey)));
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
              isCorrect ? 'Correct! Well done!' : 'Incorrect. The correct answer is: $correctAnswer',
              style: TextStyle(color: isCorrect ? Colors.green[800]! : Colors.red[800]!, fontWeight: FontWeight.bold, fontSize: isSmallScreen ? 14 : 16),
            ),
          ),
        ],
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
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _resetQuiz,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 14 : 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('New Quiz', style: TextStyle(fontSize: isSmallScreen ? 16 : 18, fontWeight: FontWeight.bold)),
          ),
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
                    SingleChildScrollView(
                      padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                      child: Column(
                        children: [
                          _quizFinished ? _buildQuizResult() : _buildQuizQuestion(),
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
                            Text('Progress: $_quizIndex/${_quizQuestions.length} questions', style: TextStyle(fontWeight: FontWeight.w500, fontSize: isSmallScreen ? 12 : 14)),
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