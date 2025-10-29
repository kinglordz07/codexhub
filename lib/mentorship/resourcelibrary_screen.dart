import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'package:url_launcher/url_launcher.dart';

class ResourceLibraryScreen extends StatefulWidget {
  const ResourceLibraryScreen({super.key});

  @override
  State<ResourceLibraryScreen> createState() => _ResourceLibraryScreenState();
}

class _ResourceLibraryScreenState extends State<ResourceLibraryScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  late TabController _tabController;

  List<Map<String, dynamic>> _resources = [];
  List<Map<String, dynamic>> _uploadedFiles = [];
  List<Map<String, dynamic>> _videoUrls = [];
  List<Map<String, dynamic>> _quizzes = []; // ADDED: Quizzes list
  bool _isLoading = true;
  bool _isLoadingFiles = true;
  bool _isLoadingVideos = true;
  bool _isLoadingQuizzes = true; // ADDED: Quiz loading state
  int _currentTabIndex = 0;

  // Get current user info
  User? get _currentUser {
    return supabase.auth.currentUser;
  }

  // Helper method to get current user ID or throw error if not logged in
  String get _currentUserId {
    final user = _currentUser;
    if (user == null) {
      throw Exception('User must be logged in to access resource library');
    }
    return user.id;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this); // CHANGED: 3 to 4 tabs
    _tabController.addListener(_handleTabChange);
    _loadResources();
    _loadUploadedFiles();
    _loadVideoUrls();
    _loadQuizzes(); // ADDED: Load quizzes
    _ensureStorageBucket();
  }

  void _handleTabChange() {
    setState(() {
      _currentTabIndex = _tabController.index;
    });
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadResources() async {
  try {
    debugPrint('🔄 Loading resources from database for current user...');
    debugPrint('👤 Current user ID: $_currentUserId');
    
    // Try the join query first
    try {
      final response = await supabase
          .from('resources')
          .select('''
            *,
            profiles_new:user_id (username)
          ''')
          .eq('is_removed', false)
          .or('user_id.eq.$_currentUserId,user_id.is.null')
          .order('uploaded_at', ascending: false);

      debugPrint('✅ Join query successful: ${response.length} resources');
      debugPrint('📋 First resource sample: ${response.isNotEmpty ? response[0] : "No resources"}');
      
      setState(() {
        _resources = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });

    } catch (joinError) {
      debugPrint('⚠️ Join query failed: $joinError');
      debugPrint('🔄 Falling back to simple query...');
      
      // Fallback to simple query without join
      final response = await supabase
          .from('resources')
          .select('*')
          .eq('is_removed', false)
          .or('user_id.eq.$_currentUserId,user_id.is.null')
          .order('uploaded_at', ascending: false);

      debugPrint('✅ Simple query successful: ${response.length} resources');
      
      setState(() {
        _resources = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    }

    debugPrint('✅ Loaded ${_resources.length} total resources');

  } catch (e) {
    debugPrint('❌ Error loading resources: $e');
    setState(() {
      _resources = [];
      _isLoading = false;
    });
  }
}

Future<void> _loadUploadedFiles() async {
  try {
    debugPrint('🔄 Loading uploaded files for current user...');
    debugPrint('👤 Current user ID: $_currentUserId');
    
    setState(() {
      _isLoadingFiles = true;
    });

    // Simple query without joins
    final response = await supabase
        .from('resources')
        .select('*')
        .eq('is_removed', false)
        .eq('user_id', _currentUserId)
        .eq('is_uploaded_to_learning_tools', true)
        .order('uploaded_at', ascending: false);

    debugPrint('🎯 Uploaded files raw result: ${response.length} items');
    
    for (var file in response) {
      debugPrint('📄 Uploaded file: ${file['title']} - ID: ${file['id']}');
    }

    setState(() {
      _uploadedFiles = List<Map<String, dynamic>>.from(response);
      _isLoadingFiles = false;
    });

    debugPrint('✅ Loaded ${_uploadedFiles.length} uploaded files');

  } catch (e) {
    debugPrint('❌ Error loading uploaded files: $e');
    setState(() {
      _isLoadingFiles = false;
    });
  }
}

// Load video URLs from video_urls table
Future<void> _loadVideoUrls() async {
  try {
    debugPrint('🔄 Loading video URLs from video_urls table...');
    
    setState(() {
      _isLoadingVideos = true;
    });

    final response = await supabase
        .from('video_urls')
        .select('''
          *,
          profiles_new:uploaded_by (username)
        ''')
        .eq('is_removed', false)
        .or('uploaded_by.eq.$_currentUserId,uploaded_by.is.null')
        .order('created_at', ascending: false);

    debugPrint('✅ Loaded ${response.length} video URLs');
    
    setState(() {
      _videoUrls = List<Map<String, dynamic>>.from(response);
      _isLoadingVideos = false;
    });

  } catch (e) {
    debugPrint('❌ Error loading video URLs: $e');
    setState(() {
      _isLoadingVideos = false;
    });
  }
}

// FIXED: Load quizzes - no need for profile joining
Future<void> _loadQuizzes() async {
  try {
    debugPrint('🔄 Loading quizzes from quizzes table...');
    
    setState(() {
      _isLoadingQuizzes = true;
    });

    // Simple query - no need for profile joining
    final response = await supabase
        .from('quizzes')
        .select('*')
        .eq('is_active', true)
        .or('user_id.eq.$_currentUserId,user_id.is.null')
        .order('created_at', ascending: false);

    debugPrint('✅ Loaded ${response.length} quizzes from database');
    
    setState(() {
      _quizzes = List<Map<String, dynamic>>.from(response);
      _isLoadingQuizzes = false;
    });

  } catch (e) {
    debugPrint('❌ Error loading quizzes: $e');
    setState(() {
      _isLoadingQuizzes = false;
      _quizzes = [];
    });
  }
}

  void _addNewResourceWithAttachment() {
    showDialog(
      context: context,
      builder: (context) => AddResourceWithAttachmentDialog(
        currentUserId: _currentUserId,
        onResourceAdded: (newResource) async {
          await _saveResourceToDatabase(newResource);
          await _loadResources();
          await _loadUploadedFiles();
        },
      ),
    );
  }

  // Add new video URL
  void _addNewVideoUrl() {
    showDialog(
      context: context,
      builder: (context) => AddVideoUrlDialog(
        currentUserId: _currentUserId,
        onVideoAdded: (newVideo) async {
          await _saveVideoUrlToDatabase(newVideo);
          await _loadVideoUrls();
        },
      ),
    );
  }

  void _createNewQuiz() {
    showDialog(
      context: context,
      builder: (context) => QuizCreationDialog(
        currentUserId: _currentUserId,
        onQuizCreated: (newQuiz) async {
          await _saveQuizToDatabase(newQuiz);
          await _loadQuizzes(); // ADDED: Refresh quizzes after creation
        },
      ),
    );
  }

  Future<void> _saveQuizToDatabase(Map<String, dynamic> quiz) async {
  try {
    debugPrint('💾 Saving quiz to database for current user...');

    // Prepare the correct answers
    List<String> correctAnswerTexts = [];
    for (int i = 0; i < quiz['correct_answers'].length; i++) {
      if (quiz['correct_answers'][i] == true) {
        correctAnswerTexts.add(quiz['answers'][i]);
      }
    }

    // Get current user's username for created_by field
    final currentUser = _currentUser;
    final createdBy = currentUser?.email?.split('@').first ?? 'User';

    // Prepare quiz data - match your table structure
    final Map<String, dynamic> quizData = {
      'question': quiz['question'],
      'category': quiz['category'],
      'answers': quiz['answers'],
      'correct_answers': correctAnswerTexts,
      'difficulty': quiz['difficulty'],
      'user_id': _currentUserId,
      'created_by': createdBy, // ADD THIS
      'is_active': true,
      'created_at': DateTime.now().toIso8601String(),
    };

    debugPrint('📦 Quiz data to insert: $quizData');

    final response = await supabase.from('quizzes').insert(quizData).select();

    debugPrint('✅ Quiz saved successfully! Response: $response');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Quiz question "${quiz['question']}" created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  } catch (e) {
    debugPrint('❌ Error saving quiz to database: $e');
    
    if (e is PostgrestException) {
      debugPrint('📋 Postgrest Error Details:');
      debugPrint('   - Message: ${e.message}');
      debugPrint('   - Code: ${e.code}');
      debugPrint('   - Details: ${e.details}');
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error creating quiz: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

  // UPDATED: Removed YouTube-related fields from resource saving
  Future<void> _saveResourceToDatabase(Map<String, dynamic> resource) async {
  try {
    debugPrint('💾 Saving resource to database for current user...');
    debugPrint('📋 Resource data:');
    debugPrint('   - Title: ${resource['title']}');
    debugPrint('   - Category: ${resource['category']}');
    debugPrint('   - User ID: $_currentUserId');
    debugPrint('   - Has file: ${resource['fileBytes'] != null}');
    debugPrint('   - File name: ${resource['fileName']}');

    // Generate unique filename if file exists
    String? fileName = resource['fileName'];
    String? uniqueFileName;
    if (fileName != null) {
      uniqueFileName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      debugPrint('📁 Generated unique filename: $uniqueFileName');
    }

    // BASIC resource data - REMOVED YouTube fields
    final Map<String, dynamic> resourceData = {
      'title': resource['title'],
      'category': resource['category'],
      'description': resource['description'],
      'link': resource['link'],
      'file_name': uniqueFileName ?? fileName,
      'user_id': _currentUserId,
      'is_removed': false,
      'is_uploaded_to_learning_tools': false,
      'is_system_resource': false,
    };

    debugPrint('📦 Database insert data: $resourceData');

    final response = await supabase.from('resources').insert(resourceData).select();

    debugPrint('✅ Resource saved to database: ${response.length} rows inserted');
    debugPrint('🆕 New resource ID: ${response.isNotEmpty ? response[0]['id'] : 'Unknown'}');

    // If there's a file, upload it to storage with the same unique filename
    if (resource['fileBytes'] != null && uniqueFileName != null) {
      debugPrint('📎 File attachment found, uploading to storage...');
      await _uploadFileToStorage({
        ...resource,
        'fileName': uniqueFileName,
      });
    } else {
      debugPrint('📎 No file attachment to upload');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ ${resource['title']} saved to Your Resource Library!'),
          backgroundColor: Colors.green,
        ),
      );
    }

    // Force immediate refresh
    await _loadResources();
    await _loadUploadedFiles();

  } catch (e) {
    debugPrint('❌ Error saving resource to database: $e');
    debugPrint('📋 Full error: ${e.toString()}');
    
    if (e is PostgrestException) {
      debugPrint('📋 Postgrest Error Details:');
      debugPrint('   - Message: ${e.message}');
      debugPrint('   - Code: ${e.code}');
      debugPrint('   - Details: ${e.details}');
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error saving resource: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

  // ADDED: Save video URL to video_urls table
  Future<void> _saveVideoUrlToDatabase(Map<String, dynamic> video) async {
    try {
      debugPrint('💾 Saving video URL to video_urls table...');

      final Map<String, dynamic> videoData = {
        'title': video['title'],
        'description': video['description'],
        'youtube_url': video['youtube_url'],
        'youtube_thumbnail': video['youtube_thumbnail'],
        'category': video['category'],
        'duration': video['duration'],
        'uploaded_by': _currentUserId,
      };

      final response = await supabase.from('video_urls').insert(videoData).select();

      debugPrint('✅ Video URL saved successfully! Response: $response');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "${video['title']}" video added to Video Tutorials!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error saving video URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error saving video: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _uploadToLearningTools(int index) async {
    debugPrint('🎯 UPLOAD BUTTON CLICKED for index: $index');
    debugPrint('📋 Resource title: ${_resources[index]['title']}');
    debugPrint('👤 Current user ID: $_currentUserId');

    try {
      final resource = _resources[index];
      
      // Check if this is a system resource (can't be uploaded by users)
      if (resource['is_system_resource'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('System resources cannot be uploaded to Learning Tools'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Check if already uploaded
      if (resource['is_uploaded_to_learning_tools'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('This resource is already uploaded to Learning Tools'),
              backgroundColor: Colors.blue,
            ),
          );
        }
        return;
      }

      await _uploadToArticlesTable(resource);
    } catch (e) {
      debugPrint('❌ ERROR in _uploadToLearningTools: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // UPDATED: Removed YouTube link from articles upload
  Future<void> _uploadToArticlesTable(Map<String, dynamic> resource) async {
    debugPrint('🚀 STARTING UPLOAD PROCESS');
    debugPrint('📝 Resource details:');
    debugPrint('   - Title: ${resource['title']}');
    debugPrint('   - Category: ${resource['category']}');
    debugPrint('   - User: $_currentUserId');
    debugPrint('   - Has file: ${resource['file_name'] != null}');
    debugPrint('   - File name: ${resource['file_name']}');
    debugPrint('   - Resource ID: ${resource['id']}');

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Text('Uploading ${resource['title']} to Learning Tools...'),
              ],
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }

      // Check if resource has a file attachment
      bool hasAttachment = resource['file_name'] != null;
      String? fileName = resource['file_name'];
      String? filePath = hasAttachment ? 'resource-library/$fileName' : null;

      // Get username for display
      String uploadedBy = 'Unknown User';
      if (resource['profiles_new'] != null && resource['profiles_new']['username'] != null) {
        uploadedBy = resource['profiles_new']['username'];
      } else if (resource['is_system_resource'] == true) {
        uploadedBy = 'System';
      }

      // Create article content with all resource information
      String articleContent = '''
${resource['description']}

📁 Category: ${resource['category']}
${resource['link'] != null ? '🔗 Resource Link: ${resource['link']}' : ''}
${hasAttachment ? '📎 Attached File: $fileName' : ''}

---
👤 Uploaded by: $uploadedBy
⏰ Source: Resource Library
🕒 ${DateTime.now().toString()}
''';

      debugPrint('📄 Article content created');
      debugPrint('👤 Current user ID: $_currentUserId');
      debugPrint('📎 File attachment: $hasAttachment');
      debugPrint('📁 File name: $fileName');
      debugPrint('📁 File path: $filePath');

      debugPrint('📡 Attempting database insert...');

      // Prepare article data - REMOVED youtube_link
      final Map<String, dynamic> articleData = {
        'title': resource['title'],
        'content': articleContent,
        'user_id': _currentUserId,
        'has_attachment': hasAttachment,
        'file_name': fileName,
        'file_path': filePath,
      };

      // Remove null values to avoid database errors
      articleData.removeWhere((key, value) => value == null);

      debugPrint('📦 Article data to insert: $articleData');

      final response = await supabase.from('articles').insert(articleData).select();

      debugPrint('✅ DATABASE INSERT SUCCESSFUL');
      debugPrint('📊 Response: $response');

      // Update the resource to mark it as uploaded to Learning Tools
      if (resource['id'] != null && resource['id'] is int && resource['id'] > 0) {
        debugPrint('🔄 Updating resource with ID: ${resource['id']}');
        
        final updateResponse = await supabase
            .from('resources')
            .update({
              'is_uploaded_to_learning_tools': true,
            })
            .eq('id', resource['id'])
            .eq('user_id', _currentUserId)
            .select();

        debugPrint('✅ Resource update response: $updateResponse');
        
        if (updateResponse.isNotEmpty) {
          debugPrint('🎉 Successfully marked resource as uploaded to Learning Tools');
        } else {
          debugPrint('⚠️ Resource update might have failed - no rows returned');
        }
      } else {
        debugPrint('⚠️ Cannot update resource - invalid ID: ${resource['id']}');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hasAttachment
                  ? '✅ ${resource['title']} uploaded to Learning Tools with file attachment!'
                  : '✅ ${resource['title']} uploaded to Learning Tools!',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }

      // Refresh both tabs to reflect the changes
      await _loadResources();
      await _loadUploadedFiles();
      
      debugPrint('🔄 Data refreshed after upload');

    } catch (e) {
      debugPrint('❌ DATABASE INSERT FAILED: $e');
      debugPrint('📋 Error details: ${e.toString()}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error uploading resource: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _uploadFileToStorage(Map<String, dynamic> resource) async {
    try {
      debugPrint('📎 Starting file upload to storage...');

      // Upload file to Supabase storage using bytes
      final String fileName = resource['fileName'];
      final String uniqueFileName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final String filePath = 'resource-library/$uniqueFileName';

      debugPrint('📁 Uploading file: $uniqueFileName');
      debugPrint('📊 File size: ${resource['fileBytes']?.length} bytes');

      // Use the file bytes directly for upload
      await supabase.storage
          .from('learning_files')
          .upload(filePath, resource['fileBytes']!);

      debugPrint('✅ File uploaded successfully: $filePath');

      // Update the database with the actual stored filename
      await supabase
          .from('resources')
          .update({'file_name': uniqueFileName})
          .eq('file_name', fileName)
          .eq('user_id', _currentUserId);

      debugPrint('✅ Database updated with unique filename: $uniqueFileName');

      // Get the public URL for the uploaded file
      final String publicUrl = supabase.storage
          .from('learning_files')
          .getPublicUrl(filePath);

      debugPrint('🔗 File public URL: $publicUrl');
    } catch (e) {
      debugPrint('❌ Error uploading file to storage: $e');
      debugPrint('📋 Error details: ${e.toString()}');
    }
  }

  // Upload video to Learning Tools
Future<void> _uploadVideoToLearningTools(Map<String, dynamic> video) async {
  debugPrint('🚀 UPLOADING VIDEO TO LEARNING TOOLS VIDEOS TAB');
  debugPrint('🎬 Video details:');
  debugPrint('   - Title: ${video['title']}');
  debugPrint('   - User: $_currentUserId');

  try {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 16),
              Text('Uploading "${video['title']}" to Learning Tools Videos...'),
            ],
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }

    // ✅ SIMPLE: Just mark the video as uploaded in video_urls table
    if (video['id'] != null) {
      await supabase
          .from('video_urls')
          .update({
            'is_uploaded_to_learning_tools': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', video['id'])
          .eq('uploaded_by', _currentUserId);
      
      debugPrint('✅ Video marked as uploaded in video_urls table');
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ "${video['title']}" now available in Learning Tools Videos!'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }

    // Refresh the video list
    await _loadVideoUrls();

  } catch (e) {
    debugPrint('❌ ERROR UPLOADING VIDEO: $e');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error uploading video: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

  // Delete video function
  void _markVideoAsRemoved(Map<String, dynamic> video) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Video Tutorial'),
        content: Text(
          'Are you sure you want to permanently delete "${video['title']}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Hard delete - permanently remove from video_urls table
        await supabase
            .from('video_urls')
            .delete()
            .eq('id', video['id'])
            .eq('uploaded_by', _currentUserId);

        // Refresh the video list
        await _loadVideoUrls();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Video deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint('❌ Error deleting video: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error deleting video: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // FIXED: Delete quiz function
void _markQuizAsRemoved(Map<String, dynamic> quiz) async {
  final bool? confirm = await showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete Quiz Question'),
      content: Text(
        'Are you sure you want to permanently delete "${quiz['question']}"? This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            'Delete',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    ),
  );

  if (confirm == true) {
    try {
      // Simple update - no updated_at field
      await supabase
          .from('quizzes')
          .update({
            'is_active': false,
          })
          .eq('id', quiz['id'])
          .eq('user_id', _currentUserId);

      // Refresh the quiz list
      await _loadQuizzes();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Quiz question deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error deleting quiz: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error deleting quiz: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

  Future<void> _ensureStorageBucket() async {
    try {
      await supabase.storage.from('learning_files').list();
      debugPrint('✅ Storage bucket "learning_files" exists');
    } catch (e) {
      debugPrint('⚠️ Storage bucket might not exist, creating it...');
      debugPrint('💡 Please create a "learning_files" bucket in your Supabase storage');
    }
  }

  String _getUploaderDisplayName(Map<String, dynamic> resource) {
  try {
    // Check if we have joined profile data
    if (resource['profiles_new'] != null) {
      final profile = resource['profiles_new'];
      if (profile is Map<String, dynamic> && profile['username'] != null) {
        return profile['username'];
      }
    }
    
    // Fallback to user_id comparison
    final userId = resource['user_id'];
    final isSystemResource = resource['is_system_resource'] == true;
    
    if (userId == null || isSystemResource) {
      return 'System';
    } else if (userId == _currentUserId) {
      return 'You';
    } else {
      return 'Other User';
    }
  } catch (e) {
    debugPrint('❌ Error getting uploader name: $e');
    return 'Unknown User';
  }
}

  // Helper for video uploader display name
  String _getVideoUploaderDisplayName(Map<String, dynamic> video) {
  try {
    // Check if we have joined profile data
    if (video['profiles_new'] != null) {
      final profile = video['profiles_new'];
      if (profile is Map<String, dynamic> && profile['username'] != null) {
        return profile['username'] as String;
      }
    }
    
    // Fallback to uploaded_by comparison
    final uploadedBy = video['uploaded_by'];
    
    if (uploadedBy == null) {
      return 'System';
    } else if (uploadedBy == _currentUserId) {
      return 'You';
    } else {
      return 'Other User';
    }
  } catch (e) {
    debugPrint('❌ Error getting video uploader name: $e');
    return 'Unknown User';
  }
}

 // FIXED: Helper for quiz creator display name
String _getQuizCreatorDisplayName(Map<String, dynamic> quiz) {
  try {
    // Use created_by field if available, otherwise fallback to user_id
    final createdBy = quiz['created_by'];
    final userId = quiz['user_id'];
    
    if (createdBy != null && createdBy is String && createdBy.isNotEmpty) {
      return createdBy;
    }
    
    // Fallback to user_id comparison
    if (userId == null) {
      return 'System';
    } else if (userId == _currentUserId) {
      return 'You';
    } else {
      return 'Other User';
    }
  } catch (e) {
    debugPrint('❌ Error getting quiz creator name: $e');
    return 'Unknown User';
  }
}

  // FIXED: Method to open YouTube video
void _openYoutubeVideo(String youtubeUrl) async {
  try {
    final uri = Uri.parse(youtubeUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cannot open YouTube video'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  } catch (e) {
    debugPrint('❌ Error opening YouTube video: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening video: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

  // UPDATED: Removed YouTube-related UI from resources tab
  Widget _buildResourceLibraryTab() {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    if (_resources.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 20 : 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.library_books, size: isSmallScreen ? 60 : 80, color: Colors.grey[400]),
              SizedBox(height: isSmallScreen ? 12 : 16),
              Text(
                'No Resources Available',
                style: TextStyle(
                  fontSize: isSmallScreen ? 16 : 18,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: isSmallScreen ? 8 : 12),
              Text(
                'Add your first resource using the + button below',
                style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: isSmallScreen ? 16 : 24),
              ElevatedButton.icon(
                onPressed: _addNewResourceWithAttachment,
                icon: Icon(Icons.add),
                label: Text('Add First Resource'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(
        vertical: isSmallScreen ? 8 : 12,
        horizontal: isSmallScreen ? 8 : 16,
      ),
      itemCount: _resources.length,
      itemBuilder: (context, index) {
        final resource = _resources[index];
        final isSystemResource = resource['is_system_resource'] == true;
        final isUploadedToLearningTools = resource['is_uploaded_to_learning_tools'] == true;
        final hasFile = resource['file_name'] != null;
        final uploaderName = _getUploaderDisplayName(resource);

        return Card(
          margin: EdgeInsets.symmetric(
            vertical: isSmallScreen ? 6 : 8,
            horizontal: isSmallScreen ? 4 : 0,
          ),
          elevation: 5,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: EdgeInsets.all(isSmallScreen ? 12 : 16),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    resource['title'],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isSmallScreen ? 14 : 16,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isSystemResource) ...[
                  SizedBox(width: isSmallScreen ? 4 : 8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 4 : 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'System',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 8 : 10,
                        color: Colors.blue[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                if (isUploadedToLearningTools && !isSystemResource) ...[
                  SizedBox(width: isSmallScreen ? 4 : 8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 4 : 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Uploaded',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 8 : 10,
                        color: Colors.green[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Category: ${resource['category']}",
                  style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                ),
                Text(
                  "Description: ${resource['description']}",
                  style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (hasFile) ...[
                  SizedBox(height: isSmallScreen ? 2 : 4),
                  Row(
                    children: [
                      Icon(Icons.attach_file, size: isSmallScreen ? 14 : 16, color: Colors.grey),
                      SizedBox(width: isSmallScreen ? 2 : 4),
                      Expanded(
                        child: Text(
                          resource['file_name'],
                          style: TextStyle(
                            fontSize: isSmallScreen ? 10 : 12,
                            color: Colors.blue,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                SizedBox(height: isSmallScreen ? 2 : 4),
                Row(
                  children: [
                    Icon(Icons.person, size: isSmallScreen ? 12 : 14, color: Colors.grey),
                    SizedBox(width: isSmallScreen ? 2 : 4),
                    Expanded(
                      child: Text(
                        'Uploaded by: $uploaderName',
                        style: TextStyle(fontSize: isSmallScreen ? 10 : 12, color: Colors.grey),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            leading: hasFile
                ? Icon(Icons.attachment, size: isSmallScreen ? 32 : 40, color: Colors.orange)
                : Icon(Icons.book, size: isSmallScreen ? 32 : 40, color: Colors.indigo),
            trailing: isSystemResource
                ? Icon(Icons.lock, color: Colors.grey, size: isSmallScreen ? 20 : 24)
                : isUploadedToLearningTools
                    ? Icon(Icons.check_circle, color: Colors.green, size: isSmallScreen ? 20 : 24)
                    : IconButton(
                        icon: Icon(Icons.upload_rounded, color: Colors.blue, size: isSmallScreen ? 18 : 20),
                        onPressed: () {
                          debugPrint('🖱️ Upload icon pressed for: ${resource['title']}');
                          _uploadToLearningTools(index);
                        },
                        tooltip: 'Upload to Learning Tools',
                      ),
          ),
        );
      },
    );
  }

  Widget _buildUploadedFilesTab() {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return _isLoadingFiles
        ? Center(child: CircularProgressIndicator())
        : _uploadedFiles.isEmpty
            ? Center(
                child: Padding(
                  padding: EdgeInsets.all(isSmallScreen ? 20 : 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open, size: isSmallScreen ? 60 : 80, color: Colors.grey[400]),
                      SizedBox(height: isSmallScreen ? 12 : 16),
                      Text(
                        'No files uploaded to Learning Tools yet',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 16 : 18,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: isSmallScreen ? 8 : 12),
                      Text(
                        'Upload files to Learning Tools using the upload button in Resources tab',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 12 : 14,
                          color: Colors.grey[500],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                padding: EdgeInsets.symmetric(
                  vertical: isSmallScreen ? 8 : 12,
                  horizontal: isSmallScreen ? 8 : 16,
                ),
                itemCount: _uploadedFiles.length,
                itemBuilder: (context, index) {
                  final file = _uploadedFiles[index];
                  final fileName = file['file_name'] ?? 'Unknown File';
                  final fileExtension = fileName.split('.').last.toLowerCase();
                  final uploaderName = _getUploaderDisplayName(file);

                  return Card(
                    margin: EdgeInsets.symmetric(
                      vertical: isSmallScreen ? 6 : 8,
                      horizontal: isSmallScreen ? 4 : 0,
                    ),
                    elevation: 5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                      title: Text(
                        file['title'] ?? fileName,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: isSmallScreen ? 14 : 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (fileName != 'Unknown File') ...[
                            Text(
                              "File: $fileName",
                              style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                            ),
                          ],
                          if (file['category'] != null)
                            Text(
                              "Category: ${file['category']}",
                              style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                            ),
                          if (file['description'] != null)
                            Text(
                              "Description: ${file['description']}",
                              style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          SizedBox(height: isSmallScreen ? 2 : 4),
                          Row(
                            children: [
                              Icon(Icons.person, size: isSmallScreen ? 12 : 14, color: Colors.grey),
                              SizedBox(width: isSmallScreen ? 2 : 4),
                              Text(
                                'Uploaded by: $uploaderName',
                                style: TextStyle(fontSize: isSmallScreen ? 10 : 12, color: Colors.grey),
                              ),
                            ],
                          ),
                          if (file['uploaded_at'] != null) ...[
                            SizedBox(height: isSmallScreen ? 1 : 2),
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: isSmallScreen ? 12 : 14,
                                  color: Colors.grey,
                                ),
                                SizedBox(width: isSmallScreen ? 2 : 4),
                                Text(
                                  'Uploaded: ${_formatDate(file['uploaded_at'])}',
                                  style: TextStyle(fontSize: isSmallScreen ? 10 : 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                      leading: _getFileIcon(fileExtension, size: isSmallScreen ? 32 : 40),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                          size: isSmallScreen ? 18 : 20,
                        ),
                        onPressed: () {
                          _markFileAsRemoved(file);
                        },
                        tooltip: 'Remove from Learning Tools',
                      ),
                    ),
                  );
                },
              );
  }

  // Video tutorials tab with delete functionality
  Widget _buildVideoTutorialsTab() {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    if (_isLoadingVideos) {
      return Center(child: CircularProgressIndicator());
    }

    if (_videoUrls.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 20 : 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.video_library, size: isSmallScreen ? 60 : 80, color: Colors.grey[400]),
              SizedBox(height: isSmallScreen ? 12 : 16),
              Text(
                'No Video Tutorials Yet',
                style: TextStyle(
                  fontSize: isSmallScreen ? 16 : 18,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: isSmallScreen ? 8 : 12),
              Text(
                'Add your first video tutorial using the + button',
                style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: isSmallScreen ? 16 : 24),
              ElevatedButton.icon(
                onPressed: _addNewVideoUrl,
                icon: Icon(Icons.video_call),
                label: Text('Add Video Tutorial'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(
        vertical: isSmallScreen ? 8 : 12,
        horizontal: isSmallScreen ? 8 : 16,
      ),
      itemCount: _videoUrls.length,
      itemBuilder: (context, index) {
        final video = _videoUrls[index];
        final uploaderName = _getVideoUploaderDisplayName(video);
        final isUploadedToLearningTools = video['is_uploaded_to_learning_tools'] == true;
        final isOwnVideo = video['uploaded_by'] == _currentUserId;

        return Card(
          margin: EdgeInsets.symmetric(vertical: isSmallScreen ? 6 : 8),
          elevation: 5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: EdgeInsets.all(isSmallScreen ? 12 : 16),
            leading: Container(
              width: isSmallScreen ? 60 : 80,
              height: isSmallScreen ? 45 : 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.red[100],
                image: video['youtube_thumbnail'] != null 
                    ? DecorationImage(
                        image: NetworkImage(video['youtube_thumbnail']!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: video['youtube_thumbnail'] == null
                  ? Icon(Icons.videocam, color: Colors.red, size: isSmallScreen ? 24 : 30)
                  : null,
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    video['title'],
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isSmallScreen ? 14 : 16,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isUploadedToLearningTools) ...[
                  SizedBox(width: isSmallScreen ? 4 : 8),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 4 : 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Uploaded',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 8 : 10,
                        color: Colors.green[800],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (video['category'] != null)
                  Text(
                    "Category: ${video['category']}",
                    style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                  ),
                if (video['description'] != null)
                  Text(
                    video['description'],
                    style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (video['duration'] != null)
                  Text(
                    "Duration: ${video['duration']}",
                    style: TextStyle(fontSize: isSmallScreen ? 11 : 12, color: Colors.grey),
                  ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.person, size: 12, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(
                      'By: $uploaderName',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // DELETE BUTTON - only show for own videos
                if (isOwnVideo)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.red, size: isSmallScreen ? 18 : 20),
                    onPressed: () {
                      _markVideoAsRemoved(video);
                    },
                    tooltip: 'Delete Video',
                  ),
                // UPLOAD BUTTON - only show for own videos that aren't uploaded yet
                if (isOwnVideo && !isUploadedToLearningTools)
                  IconButton(
                    icon: Icon(Icons.upload, color: Colors.blue, size: isSmallScreen ? 18 : 20),
                    onPressed: () {
                      _uploadVideoToLearningTools(video);
                    },
                    tooltip: 'Upload to Learning Tools',
                  ),
                // PLAY BUTTON
                IconButton(
                  icon: Icon(Icons.play_circle_fill, color: Colors.red, size: isSmallScreen ? 24 : 30),
                  onPressed: () => _openYoutubeVideo(video['youtube_url']),
                ),
              ],
            ),
            onTap: () => _openYoutubeVideo(video['youtube_url']),
          ),
        );
      },
    );
  }

  // ADDED: Quiz tab with delete functionality
  Widget _buildQuizzesTab() {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    if (_isLoadingQuizzes) {
      return Center(child: CircularProgressIndicator());
    }

    if (_quizzes.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 20 : 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.quiz, size: isSmallScreen ? 60 : 80, color: Colors.grey[400]),
              SizedBox(height: isSmallScreen ? 12 : 16),
              Text(
                'No Quiz Questions Yet',
                style: TextStyle(
                  fontSize: isSmallScreen ? 16 : 18,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: isSmallScreen ? 8 : 12),
              Text(
                'Create your first quiz question using the + button in Resources tab',
                style: TextStyle(
                  fontSize: isSmallScreen ? 12 : 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(
        vertical: isSmallScreen ? 8 : 12,
        horizontal: isSmallScreen ? 8 : 16,
      ),
      itemCount: _quizzes.length,
      itemBuilder: (context, index) {
        final quiz = _quizzes[index];
        final creatorName = _getQuizCreatorDisplayName(quiz);
        final isOwnQuiz = quiz['user_id'] == _currentUserId;
        final correctAnswers = quiz['correct_answers'] is List ? quiz['correct_answers'] as List<dynamic> : [];
        final answers = quiz['answers'] is List ? quiz['answers'] as List<dynamic> : [];

        
      // ✅ DITO ILALAGAY ANG DEBUG PRINT (LINE 1033-1037)
      debugPrint('📊 Building quiz ${quiz['id']}:');
      debugPrint('   - Question: ${quiz['question']}');
      debugPrint('   - User ID: ${quiz['user_id']}');
      debugPrint('   - Profile Data: ${quiz['profiles_new']}');
      debugPrint('   - Creator Name: $creatorName');

        return Card(
          margin: EdgeInsets.symmetric(vertical: isSmallScreen ? 6 : 8),
          elevation: 5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding: EdgeInsets.all(isSmallScreen ? 12 : 16),
            leading: Container(
              width: isSmallScreen ? 50 : 60,
              height: isSmallScreen ? 50 : 60,
              decoration: BoxDecoration(
                color: Colors.purple[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.quiz, color: Colors.purple, size: isSmallScreen ? 24 : 30),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    quiz['question'] ?? 'Untitled Question',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isSmallScreen ? 14 : 16,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Difficulty badge
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 4 : 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _getDifficultyColor(quiz['difficulty']),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    quiz['difficulty'] ?? 'Medium',
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
                if (quiz['category'] != null)
                  Text(
                    "Category: ${quiz['category']}",
                    style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                  ),
                Text(
                  "Answers: ${answers.length} options, ${correctAnswers.length} correct",
                  style: TextStyle(fontSize: isSmallScreen ? 11 : 12, color: Colors.grey),
                ),
                SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.person, size: 12, color: Colors.grey),
                    SizedBox(width: 4),
                    Text(
                      'By: $creatorName',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                if (quiz['created_at'] != null) ...[
                  SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 12, color: Colors.grey),
                      SizedBox(width: 4),
                      Text(
                        'Created: ${_formatDate(quiz['created_at'])}',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // DELETE BUTTON - only show for own quizzes
                if (isOwnQuiz)
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: Colors.red, size: isSmallScreen ? 18 : 20),
                    onPressed: () {
                      _markQuizAsRemoved(quiz);
                    },
                    tooltip: 'Delete Quiz',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ADDED: Helper method for difficulty color
  Color _getDifficultyColor(String? difficulty) {
    switch (difficulty?.toLowerCase()) {
      case 'easy':
        return Colors.green;
      case 'hard':
        return Colors.red;
      case 'medium':
      default:
        return Colors.orange;
    }
  }

  Icon _getFileIcon(String extension, {double size = 40}) {
    switch (extension) {
      case 'pdf':
        return Icon(
          Icons.picture_as_pdf,
          size: size,
          color: Colors.red,
        );
      case 'doc':
      case 'docx':
        return Icon(
          Icons.description,
          size: size,
          color: Colors.blue,
        );
      case 'txt':
        return Icon(
          Icons.text_fields,
          size: size,
          color: Colors.grey,
        );
      case 'pptx':
      case 'ppt':
        return Icon(
          Icons.slideshow,
          size: size,
          color: Colors.orange,
        );
      case 'zip':
      case 'rar':
        return Icon(
          Icons.folder_zip,
          size: size,
          color: Colors.amber,
        );
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icon(
          Icons.image,
          size: size,
          color: Colors.green,
        );
      // Video file icons
      case 'mp4': case 'avi': case 'mov': case 'wmv': case 'flv': case 'mkv': case 'webm':
        return Icon(Icons.videocam, size: size, color: Colors.purple);
      default:
        return Icon(
          Icons.insert_drive_file,
          size: size,
          color: Colors.indigo,
        );
    }
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  void _markFileAsRemoved(Map<String, dynamic> file) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove from Learning Tools'),
        content: Text(
          'Are you sure you want to remove "${file['title'] ?? file['file_name']}" from Learning Tools? This will also remove it from your resources.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Remove',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        // Mark the resource as removed (this will remove it from both resources and uploaded files)
        await supabase
            .from('resources')
            .update({
              'is_removed': true,
              'is_uploaded_to_learning_tools': false, // Also remove from learning tools
              'removed_at': DateTime.now().toIso8601String(),
            })
            .eq('id', file['id'])
            .eq('user_id', _currentUserId);

        // Refresh both lists
        await _loadResources();
        await _loadUploadedFiles();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ File removed from Learning Tools and Resources'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        debugPrint('❌ Error removing file: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error removing file: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final isVerySmallScreen = screenSize.width < 400;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'My Resource Library',
          style: TextStyle(fontSize: isSmallScreen ? 18 : 20),
        ),
        backgroundColor: Colors.indigo,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.lightBlueAccent,
          tabs: [
            Tab(
              icon: Icon(Icons.library_books),
              text: isVerySmallScreen ? 'Resources' : 'My Resources',
            ),
            Tab(
              icon: Icon(Icons.attach_file),
              text: isVerySmallScreen 
                  ? 'Uploaded (${_uploadedFiles.length})'
                  : 'Uploaded to Learning Tools (${_uploadedFiles.length})',
            ),
            Tab(
              icon: Icon(Icons.video_library),
              text: isVerySmallScreen 
                  ? 'Videos (${_videoUrls.length})'
                  : 'Video Tutorials (${_videoUrls.length})',
            ),
            // ADDED: Quizzes tab
            Tab(
              icon: Icon(Icons.quiz),
              text: isVerySmallScreen 
                  ? 'Quizzes (${_quizzes.length})'
                  : 'Quiz Questions (${_quizzes.length})',
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildResourceLibraryTab(), 
            _buildUploadedFilesTab(),
            _buildVideoTutorialsTab(),
            _buildQuizzesTab() // ADDED: Quizzes tab
          ],
        ),
      ),
      floatingActionButton: _currentTabIndex == 0
          ? Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // Quiz Creation FAB
                FloatingActionButton(
                  onPressed: _createNewQuiz,
                  backgroundColor: Colors.purple,
                  tooltip: 'Create Quiz Question',
                  heroTag: 'quiz_fab',
                  child: Icon(Icons.quiz, color: Colors.white),
                ),
                SizedBox(height: 16),
                // Resource Creation FAB
                FloatingActionButton(
                  onPressed: _addNewResourceWithAttachment,
                  backgroundColor: Colors.indigo,
                  tooltip: 'Add New Resource with Attachment',
                  heroTag: 'resource_fab',
                  child: Icon(Icons.add, color: Colors.white),
                ),
              ],
            )
          : _currentTabIndex == 2
              ? FloatingActionButton( // Video FAB for video tab
                  onPressed: _addNewVideoUrl,
                  backgroundColor: Colors.red,
                  tooltip: 'Add Video Tutorial',
                  heroTag: 'video_fab',
                  child: Icon(Icons.video_call, color: Colors.white),
                )
              : null,
    );
  }
}

// ADDED: Video URL Dialog class
class AddVideoUrlDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onVideoAdded;
  final String currentUserId;

  const AddVideoUrlDialog({
    super.key,
    required this.onVideoAdded,
    required this.currentUserId,
  });

  @override
  State<AddVideoUrlDialog> createState() => _AddVideoUrlDialogState();
}

class _AddVideoUrlDialogState extends State<AddVideoUrlDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _durationController = TextEditingController();
  final _youtubeUrlController = TextEditingController();

  bool _isValidYoutubeUrl = false;
  String? _youtubeThumbnail;

  @override
  Widget build(BuildContext context) {

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.video_library, color: Colors.red),
          SizedBox(width: 8),
          Text('Add Video Tutorial'),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _youtubeUrlController,
                decoration: InputDecoration(
                  labelText: 'YouTube URL *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                  hintText: 'https://youtube.com/watch?v=...',
                ),
                onChanged: _validateYoutubeUrl,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter YouTube URL';
                  if (!_isValidYoutubeUrl) return 'Please enter valid YouTube URL';
                  return null;
                },
              ),
              SizedBox(height: 16),
              
              if (_youtubeThumbnail != null) ...[
                Container(
                  width: double.infinity,
                  height: 120,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    image: DecorationImage(
                      image: NetworkImage(_youtubeThumbnail!),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                SizedBox(height: 16),
              ],
              
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Video Title *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter title';
                  return null;
                },
              ),
              SizedBox(height: 12),
              
              TextFormField(
                controller: _categoryController,
                decoration: InputDecoration(
                  labelText: 'Category *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                  hintText: 'e.g., Flutter, Programming, Tutorial',
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter category';
                  return null;
                },
              ),
              SizedBox(height: 12),
              
              TextFormField(
                controller: _durationController,
                decoration: InputDecoration(
                  labelText: 'Duration (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.timer),
                  hintText: 'e.g., 15:30, 1 hour 20 min',
                ),
              ),
              SizedBox(height: 12),
              
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter description';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _addVideo,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          child: Text('Add Video Tutorial'),
        ),
      ],
    );
  }

  void _validateYoutubeUrl(String url) {
    final youtubeRegex = RegExp(
      r'^(https?:\/\/)?(www\.)?(youtube\.com|youtu\.?be)\/.+$',
      caseSensitive: false,
    );
    
    setState(() {
      _isValidYoutubeUrl = youtubeRegex.hasMatch(url);
      if (_isValidYoutubeUrl) {
        _youtubeThumbnail = _getYoutubeThumbnail(url);
      } else {
        _youtubeThumbnail = null;
      }
    });
  }

  String _getYoutubeThumbnail(String url) {
    final videoId = _extractYoutubeId(url);
    return videoId != null 
        ? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg'
        : '';
  }

  String? _extractYoutubeId(String url) {
    final regExp = RegExp(
      r'^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#&?]*).*',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(url);
    return (match != null && match.group(7)!.length == 11) ? match.group(7) : null;
  }

  void _addVideo() {
    if (_formKey.currentState!.validate() && _isValidYoutubeUrl) {
      final newVideo = {
        'title': _titleController.text,
        'description': _descriptionController.text,
        'youtube_url': _youtubeUrlController.text,
        'youtube_thumbnail': _youtubeThumbnail,
        'category': _categoryController.text,
        'duration': _durationController.text.isNotEmpty ? _durationController.text : null,
        'uploaded_by': widget.currentUserId,
      };

      widget.onVideoAdded(newVideo);
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _durationController.dispose();
    _youtubeUrlController.dispose();
    super.dispose();
  }
}

// UPDATED: Removed YouTube option from resource dialog
class AddResourceWithAttachmentDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onResourceAdded;
  final String currentUserId;

  const AddResourceWithAttachmentDialog({
    super.key,
    required this.onResourceAdded,
    required this.currentUserId,
  });

  @override
  State<AddResourceWithAttachmentDialog> createState() =>
      _AddResourceWithAttachmentDialogState();
}

class _AddResourceWithAttachmentDialogState
    extends State<AddResourceWithAttachmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _linkController = TextEditingController();

  Uint8List? _fileBytes;
  String? _fileName;
  int? _fileSize;
  bool _isPickingFile = false;

  void _addResource() {
    if (_formKey.currentState!.validate()) {
      final newResource = {
        'title': _titleController.text,
        'category': _categoryController.text,
        'description': _descriptionController.text,
        'link': _linkController.text.isNotEmpty ? _linkController.text : null,
        'fileBytes': _fileBytes,
        'fileName': _fileName,
        'fileSize': _fileSize,
        'user_id': widget.currentUserId,
        'uploadedAt': DateTime.now().toIso8601String(),
      };

      widget.onResourceAdded(newResource);
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fileName != null ? 'Resource with attachment added successfully!' 
            : 'Resource added successfully!',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _pickFile() async {
  setState(() {
    _isPickingFile = true;
  });

  try {
    // Request permissions first
    final hasPermission = await _requestFilePermissions();
    
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File access permission is required to select files'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'Open Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return;
    }

    // Allow video files in addition to existing file types
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'pdf', 'doc', 'docx', 'txt', 
        'pptx', 'ppt', 'zip', 'rar',
        'jpg', 'jpeg', 'png', 'gif',
        // Video formats
        'mp4', 'avi', 'mov', 'wmv', 'flv', 'mkv', 'webm'
      ],
      allowMultiple: false,
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.single;
      await _handleSelectedFile(file);
    } else {
      debugPrint('File selection cancelled');
    }
  } catch (e, stackTrace) {
    debugPrint('❌ Error picking file: $e');
    debugPrint('📋 Stack trace: $stackTrace');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting file: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    setState(() {
      _isPickingFile = false;
    });
  }
}

Future<void> _handleSelectedFile(PlatformFile file) async {
  try {
    // Check file size (limit to 10MB)
    const maxFileSize = 10 * 1024 * 1024;
    if (file.size > maxFileSize) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File size too large. Maximum 10MB allowed.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    Uint8List? fileBytes = file.bytes;

    // If bytes are null, try to read from path
    if (fileBytes == null && file.path != null) {
      final fileObj = File(file.path!);
      if (await fileObj.exists()) {
        fileBytes = await fileObj.readAsBytes();
      }
    }

    // Null check before using fileBytes
    if (fileBytes != null) {
      final fileSize = fileBytes.length; // This is safe now
      
      setState(() {
        _fileBytes = fileBytes;
        _fileName = file.name;
        _fileSize = fileSize;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'File selected: ${file.name} (${_formatFileSize(fileSize)})',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      throw Exception('Could not read file bytes');
    }
  } catch (e) {
    debugPrint('❌ Error handling selected file: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error reading file: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Future<bool> _requestFilePermissions() async {
  try {
    if (Platform.isAndroid) {
      // Check Android version
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkVersion = androidInfo.version.sdkInt;

      if (sdkVersion >= 33) {
        // Android 13+ - request new media permissions
        final Map<Permission, PermissionStatus> statuses = await [
          Permission.photos,
          Permission.videos,
          Permission.audio,
        ].request();

        final allGranted = statuses.values.every((status) => status.isGranted);
        
        if (!allGranted) {
          // If not all granted, try with storage permission as fallback
          final storageStatus = await Permission.storage.request();
          return storageStatus.isGranted;
        }
        
        return allGranted;
      } else {
        // Android < 13 - use storage permission
        final storageStatus = await Permission.storage.request();
        return storageStatus.isGranted;
      }
    } else if (Platform.isIOS) {
      // iOS - request photos permission
      final photosStatus = await Permission.photos.request();
      return photosStatus.isGranted;
    }
    
    return true; // For other platforms
  } catch (e) {
    debugPrint('❌ Permission error: $e');
    return false;
  }
}

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  void _clearFile() {
    setState(() {
      _fileBytes = null;
      _fileName = null;
      _fileSize = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.add_circle, color: Colors.indigo),
          SizedBox(width: 8),
          Text(
            'Add New Resource',
            style: TextStyle(fontSize: isSmallScreen ? 18 : 20),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // File Attachment Section
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade50,
                ),
                child: Column(
                  children: [
                    Icon(Icons.attach_file, size: isSmallScreen ? 32 : 40, color: Colors.indigo),
                    SizedBox(height: isSmallScreen ? 6 : 8),

                    if (_fileName != null) ...[
                      Column(
                        children: [
                          Text(
                            _fileName!,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                              fontSize: isSmallScreen ? 14 : 16,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          SizedBox(height: isSmallScreen ? 2 : 4),
                          Text(
                            _fileSize != null ? _formatFileSize(_fileSize!) : '',
                            style: TextStyle(fontSize: isSmallScreen ? 11 : 12, color: Colors.grey),
                          ),
                          SizedBox(height: isSmallScreen ? 8 : 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _isPickingFile ? null : _pickFile,
                                icon: Icon(Icons.change_circle, size: isSmallScreen ? 16 : 18),
                                label: Text(
                                  'Change',
                                  style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _clearFile,
                                icon: Icon(Icons.delete, size: isSmallScreen ? 16 : 18),
                                label: Text(
                                  'Remove',
                                  style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ] else ...[
                      Text(
                        'No file attached',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          fontSize: isSmallScreen ? 14 : 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: isSmallScreen ? 8 : 12),
                      ElevatedButton.icon(
                        onPressed: _isPickingFile ? null : _pickFile,
                        icon: _isPickingFile
                            ? SizedBox(
                                width: isSmallScreen ? 14 : 16,
                                height: isSmallScreen ? 14 : 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(Icons.attach_file, size: isSmallScreen ? 16 : 18),
                        label: Text(
                          'Attach File',
                          style: TextStyle(fontSize: isSmallScreen ? 12 : 14),
                        ),
                      ),
                    ],

                    if (_fileName != null) ...[
                      SizedBox(height: isSmallScreen ? 6 : 8),
                      Text(
                        'File will be available in Resources tab. Use the upload button to add to Learning Tools.',
                        style: TextStyle(fontSize: isSmallScreen ? 10 : 12, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),

              // Common Resource Details
              TextFormField(
                controller: _titleController,
                style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
                decoration: InputDecoration(
                  labelText: 'Title *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a title';
                  }
                  return null;
                },
              ),
              SizedBox(height: isSmallScreen ? 10 : 12),
              
              TextFormField(
                controller: _categoryController,
                style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
                decoration: InputDecoration(
                  labelText: 'Category *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a category';
                  }
                  return null;
                },
              ),
              SizedBox(height: isSmallScreen ? 10 : 12),
              
              TextFormField(
                controller: _descriptionController,
                style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
                decoration: InputDecoration(
                  labelText: 'Description *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),
              SizedBox(height: isSmallScreen ? 10 : 12),
              
              // Regular resource link (optional)
              TextFormField(
                controller: _linkController,
                style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
                decoration: InputDecoration(
                  labelText: 'Additional Resource Link (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                  hintText: 'https://example.com',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
          ),
        ),
        ElevatedButton(
          onPressed: _addResource,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
          child: Text(
            'Add Resource',
            style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _linkController.dispose();
    super.dispose();
  }
}

// Keep your existing QuizCreationDialog class as is
class QuizCreationDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onQuizCreated;
  final String currentUserId;

  const QuizCreationDialog({
    super.key,
    required this.onQuizCreated,
    required this.currentUserId,
  });

  @override
  State<QuizCreationDialog> createState() => _QuizCreationDialogState();
}

class _QuizCreationDialogState extends State<QuizCreationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  final List<TextEditingController> _answerControllers = [
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
    TextEditingController(),
  ];
  final List<bool> _correctAnswers = [false, false, false, false];
  String _difficulty = 'Medium';
   final String _selectedCategory = 'Python';
   String? _customCategory;

  @override
  void dispose() {
    _questionController.dispose();
    for (var controller in _answerControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _createQuiz() {
    if (_formKey.currentState!.validate()) {
      // Validate that at least one answer is marked as correct
      if (!_correctAnswers.contains(true)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please mark at least one answer as correct'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Validate that all answers are filled
      for (int i = 0; i < _answerControllers.length; i++) {
        if (_answerControllers[i].text.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Please fill all answer options'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      final String finalCategory = _selectedCategory == 'Other' && _customCategory != null && _customCategory!.isNotEmpty
          ? _customCategory!
          : _selectedCategory;

      final newQuiz = {
        'question': _questionController.text,
        'category': finalCategory,
        'answers': _answerControllers.map((c) => c.text).toList(),
        'correct_answers': _correctAnswers,
        'difficulty': _difficulty,
        'user_id': widget.currentUserId,
        'created_at': DateTime.now().toIso8601String(),
      };

      widget.onQuizCreated(newQuiz);
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Quiz question created successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildAnswerField(int index) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return Card(
      margin: EdgeInsets.symmetric(vertical: isSmallScreen ? 4 : 6),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
        child: Row(
          children: [
            // Checkbox for correct answer
            Checkbox(
              value: _correctAnswers[index],
              onChanged: (value) {
                setState(() {
                  _correctAnswers[index] = value!;
                });
              },
            ),
            SizedBox(width: isSmallScreen ? 8 : 12),
            
            // Answer letter indicator
            Container(
              width: isSmallScreen ? 24 : 28,
              height: isSmallScreen ? 24 : 28,
              decoration: BoxDecoration(
                color: Colors.purple[100],
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  String.fromCharCode(65 + index), // A, B, C, D
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.purple[800],
                    fontSize: isSmallScreen ? 12 : 14,
                  ),
                ),
              ),
            ),
            SizedBox(width: isSmallScreen ? 8 : 12),
            
            // Answer text field
            Expanded(
              child: TextFormField(
                controller: _answerControllers[index],
                decoration: InputDecoration(
                  labelText: 'Answer ${String.fromCharCode(65 + index)}',
                  border: OutlineInputBorder(),
                  hintText: 'Enter answer option...',
                  filled: _correctAnswers[index],
                  fillColor: _correctAnswers[index] ? Colors.green[50] : null,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter answer text';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

 @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.quiz, color: Colors.purple),
          SizedBox(width: 8),
          Text(
            'Create Quiz Question',
            style: TextStyle(fontSize: isSmallScreen ? 18 : 20),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
              controller: _questionController,
              decoration: InputDecoration(
                labelText: 'Question *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.question_mark),
                hintText: 'Enter your quiz question...',
              ),
              maxLines: 3,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a question';
                }
                return null;
              },
            ),
            SizedBox(height: isSmallScreen ? 16 : 20),
              // Difficulty Dropdown
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Difficulty',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isSmallScreen ? 14 : 16,
                      color: Colors.grey[700],
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 6 : 8),
                  DropdownButtonFormField<String>(
                    initialValue: _difficulty,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.flag, color: Colors.red),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 12 : 16,
                        vertical: isSmallScreen ? 14 : 16,
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'Easy',
                        child: Row(
                          children: [
                            Icon(Icons.sentiment_satisfied, color: Colors.green),
                            SizedBox(width: 8),
                            Text('Easy'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Medium',
                        child: Row(
                          children: [
                            Icon(Icons.sentiment_neutral, color: Colors.orange),
                            SizedBox(width: 8),
                            Text('Medium'),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Hard',
                        child: Row(
                          children: [
                            Icon(Icons.sentiment_dissatisfied, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Hard'),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _difficulty = value!;
                      });
                    },
                  ),
                ],
              ),
              SizedBox(height: isSmallScreen ? 16 : 20),

              // Answer Options
              Text(
                'Answer Options:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: isSmallScreen ? 14 : 16,
                ),
              ),
              SizedBox(height: isSmallScreen ? 8 : 12),
              ...List.generate(4, (index) => _buildAnswerField(index)),

              SizedBox(height: isSmallScreen ? 8 : 12),
              
              // Instructions
              Container(
                padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, size: isSmallScreen ? 14 : 16, color: Colors.orange),
                        SizedBox(width: isSmallScreen ? 6 : 8),
                        Text(
                          'Instructions:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isSmallScreen ? 12 : 14,
                            color: Colors.orange[800],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: isSmallScreen ? 4 : 6),
                    Text(
                      '• Check the box next to correct answers\n• Multiple correct answers are allowed\n• Fill all four answer options\n• Select appropriate category and difficulty',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 10 : 12,
                        color: Colors.orange[800],
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
          ),
        ),
        ElevatedButton(
          onPressed: _createQuiz,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 16 : 20,
              vertical: isSmallScreen ? 12 : 14,
            ),
          ),
          child: Text(
            'Create Question',
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}