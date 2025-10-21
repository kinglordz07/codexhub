import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';

class ResourceLibraryScreen extends StatefulWidget {
  const ResourceLibraryScreen({super.key});

  @override
  State<ResourceLibraryScreen> createState() => _ResourceLibraryScreenState();
}

class _ResourceLibraryScreenState extends State<ResourceLibraryScreen>
    with SingleTickerProviderStateMixin {
  final SupabaseClient supabase = Supabase.instance.client;
  late TabController _tabController;

  // Hard-coded default resources - always shown
  final List<Map<String, dynamic>> _defaultResources = [
    {
      'id': -1, // Negative IDs to distinguish from database resources
      'title': "Python Best Practices",
      'category': "Programming Language",
      'description':
          "Improve your Python coding skills with efficient techniques and design patterns.",
      'link': "https://realpython.com",
      'file_name': null,
      'uploaded_by': 'System',
      'uploaded_at': '2024-01-01',
      'is_default': true, // Mark as default resource
    },
    {
      'id': -2,
      'title': "Advanced Java Programming",
      'category': "Software Development",
      'description':
          "Master Java concepts, from concurrency to design patterns and optimizations.",
      'link': "https://docs.oracle.com/javase/tutorial/",
      'file_name': null,
      'uploaded_by': 'System',
      'uploaded_at': '2024-01-01',
      'is_default': true,
    },
    {
      'id': -3,
      'title': "C# for Modern Applications",
      'category': "Application Development",
      'description':
          "Learn C# for building desktop, web, and mobile applications using .NET.",
      'link': "https://learn.microsoft.com/en-us/dotnet/csharp/",
      'file_name': null,
      'uploaded_by': 'System',
      'uploaded_at': '2024-01-01',
      'is_default': true,
    },
    {
      'id': -4,
      'title': "VB.NET Essentials",
      'category': "Windows Development",
      'description':
          "Explore VB.NET's capabilities for rapid application development in the .NET ecosystem.",
      'link': "https://learn.microsoft.com/en-us/dotnet/visual-basic/",
      'file_name': null,
      'uploaded_by': 'System',
      'uploaded_at': '2024-01-01',
      'is_default': true,
    },
  ];

  List<Map<String, dynamic>> _resources = [];
  List<Map<String, dynamic>> _databaseResources = [];
  List<Map<String, dynamic>> _uploadedFiles = [];
  List<Map<String, dynamic>> _removedFiles = [];
  bool _isLoading = true;
  bool _isLoadingFiles = true;
  bool _showRemovedFiles = false;
  int _currentTabIndex = 0; // Track current tab index

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
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    _loadResources();
    _loadUploadedFiles();
    _loadRemovedFiles();
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
      ('🔄 Loading resources from database for current user...');
      final response = await supabase
          .from('resources')
          .select()
          .eq('is_removed', false) // Only load non-removed resources
          .eq('user_id', _currentUserId) // FIXED: Use non-nullable user ID
          .order('uploaded_at', ascending: false);

      setState(() {
        _databaseResources = List<Map<String, dynamic>>.from(response);
        // Combine default resources with current user's database resources
        _resources = [..._defaultResources, ..._databaseResources];
        _isLoading = false;
      });

      (
        '✅ Loaded ${_databaseResources.length} resources from database for user $_currentUserId',
      );
      (
        '📊 Total resources: ${_resources.length} (${_defaultResources.length} default + ${_databaseResources.length} from current user)',
      );
    } catch (e) {
      ('❌ Error loading resources from database: $e');
      // If database fails, just use default resources
      setState(() {
        _resources = _defaultResources;
        _isLoading = false;
      });
      ('📋 Using default resources only');
    }
  }

  Future<void> _loadUploadedFiles() async {
    try {
      ('🔄 Loading uploaded files for current user...');
      setState(() {
        _isLoadingFiles = true;
      });

      // FIXED: Only show files that have been uploaded to Learning Tools
      final response = await supabase
          .from('resources')
          .select()
          .not('file_name', 'is', null) // Only get resources with files
          .eq('is_removed', false) // Only non-removed files
          .eq('user_id', _currentUserId) // FIXED: Use non-nullable user ID
          .eq(
            'is_uploaded_to_learning_tools',
            true,
          ) // NEW: Only show uploaded files
          .order('uploaded_at', ascending: false);

      setState(() {
        _uploadedFiles = List<Map<String, dynamic>>.from(response);
        _isLoadingFiles = false;
      });

      (
        '✅ Loaded ${_uploadedFiles.length} uploaded files for user $_currentUserId',
      );
    } catch (e) {
      ('❌ Error loading uploaded files: $e');
      setState(() {
        _isLoadingFiles = false;
      });
    }
  }

  Future<void> _loadRemovedFiles() async {
    try {
      ('🔄 Loading removed files for current user...');

      // FIXED: Only show removed files that were previously uploaded to Learning Tools
      final response = await supabase
          .from('resources')
          .select()
          .not('file_name', 'is', null) // Only get resources with files
          .eq('is_removed', true) // Only removed files
          .eq('user_id', _currentUserId) // FIXED: Use non-nullable user ID
          .eq(
            'is_uploaded_to_learning_tools',
            true,
          ) // NEW: Only show uploaded files that were removed
          .order('removed_at', ascending: false);

      setState(() {
        _removedFiles = List<Map<String, dynamic>>.from(response);
      });

      (
        '✅ Loaded ${_removedFiles.length} removed files for user $_currentUserId',
      );
    } catch (e) {
      ('❌ Error loading removed files: $e');
    }
  }

  void _addNewResourceWithAttachment() {
    showDialog(
      context: context,
      builder:
          (context) => AddResourceWithAttachmentDialog(
            currentUser: _currentUser?.email ?? 'Anonymous User',
            onResourceAdded: (newResource) async {
              await _saveResourceToDatabase(newResource);
              // Refresh both tabs after adding new resource
              await _loadResources();
              await _loadUploadedFiles();
            },
          ),
    );
  }

  Future<void> _saveResourceToDatabase(Map<String, dynamic> resource) async {
    try {
      ('💾 Saving resource to database for current user...');

      // Generate unique filename if file exists
      String? fileName = resource['fileName'];
      if (fileName != null) {
        fileName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      }

      final response =
          await supabase.from('resources').insert({
            'title': resource['title'],
            'category': resource['category'],
            'description': resource['description'],
            'link': resource['link'],
            'file_name': fileName, // Use the unique filename
            'uploaded_by': resource['uploadedBy'],
            'user_id': _currentUserId, // FIXED: Use non-nullable user ID
            'is_removed': false, // Initially not removed
            'is_uploaded_to_learning_tools':
                false, // NEW: Initially not uploaded to Learning Tools
          }).select();

      (
        '✅ Resource saved to database for user $_currentUserId: ${response.length} rows inserted',
      );

      // If there's a file, upload it to storage with the same unique filename
      if (resource['fileBytes'] != null && resource['fileName'] != null) {
        ('📎 File attachment found, uploading to storage...');
        await _uploadFileToStorage({
          ...resource,
          'fileName': fileName, // Use the unique filename for storage
        });
      }

      // FIXED: Add mounted check before using context
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ ${resource['title']} saved to Your Resource Library!',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ('❌ Error saving resource to database: $e');
      // FIXED: Add mounted check before using context
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error saving resource: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _uploadToLearningTools(int index) async {
    ('🎯 UPLOAD BUTTON CLICKED for index: $index');
    ('📋 Resource title: ${_resources[index]['title']}');

    try {
      final resource = _resources[index];
      await _uploadToArticlesTable(resource);
    } catch (e) {
      ('❌ ERROR in _uploadToLearningTools: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadToArticlesTable(Map<String, dynamic> resource) async {
    ('🚀 STARTING UPLOAD PROCESS');
    ('📝 Resource details:');
    ('   - Title: ${resource['title']}');
    ('   - Category: ${resource['category']}');
    ('   - User: $_currentUserId');
    ('   - Has file: ${resource['file_name'] != null}');
    ('   - File name: ${resource['file_name']}');

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

      // Create article content with all resource information
      String articleContent = '''
${resource['description']}

📁 Category: ${resource['category']}
${resource['link'] != null ? '🔗 Resource Link: ${resource['link']}' : ''}
${hasAttachment ? '📎 Attached File: $fileName' : ''}

---
👤 Uploaded by: ${resource['uploaded_by']}
⏰ Source: Resource Library
🕒 ${DateTime.now().toString()}
''';

      ('📄 Article content created');
      ('👤 Current user ID: $_currentUserId');
      ('📎 File attachment: $hasAttachment');
      ('📁 File name: $fileName');
      ('📁 File path: $filePath');

      ('📡 Attempting database insert...');

      // Prepare article data with file attachment information
      final Map<String, dynamic> articleData = {
        'title': resource['title'],
        'content': articleContent,
        'user_id': _currentUserId,
        'has_attachment': hasAttachment,
        'file_name': fileName,
        'file_path': filePath,
      };

      articleData.removeWhere((key, value) => value == null);

      ('📦 Article data to insert: $articleData');

      final response =
          await supabase.from('articles').insert(articleData).select();

      ('✅ DATABASE INSERT SUCCESSFUL');
      ('📊 Response: $response');

      // Update the resource to mark it as uploaded to Learning Tools
      if (resource['id'] != null &&
          resource['id'] is int &&
          resource['id'] > 0) {
        await supabase
            .from('resources')
            .update({'is_uploaded_to_learning_tools': true})
            .eq('id', resource['id'])
            .eq('user_id', _currentUserId);
        ('✅ Resource marked as uploaded to Learning Tools');
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
    } catch (e) {
      ('❌ DATABASE INSERT FAILED: $e');
      ('📋 Error details: ${e.toString()}');
      // FIXED: Add mounted check before using context
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
      ('📎 Starting file upload to storage...');

      // Upload file to Supabase storage using bytes
      final String fileName = resource['fileName'];
      final String uniqueFileName =
          '${DateTime.now().millisecondsSinceEpoch}_$fileName';
      final String filePath = 'resource-library/$uniqueFileName';

      ('📁 Uploading file: $uniqueFileName');
      ('📊 File size: ${resource['fileBytes']?.length} bytes');

      // Use the file bytes directly for upload
      await supabase.storage
          .from('learning_files')
          .upload(filePath, resource['fileBytes']!);

      ('✅ File uploaded successfully: $filePath');

      // Update the database with the actual stored filename
      await supabase
          .from('resources')
          .update({'file_name': uniqueFileName})
          .eq('file_name', fileName)
          .eq('user_id', _currentUserId); // FIXED: Use non-nullable user ID

      ('✅ Database updated with unique filename: $uniqueFileName');

      // Get the public URL for the uploaded file
      final String publicUrl = supabase.storage
          .from('learning_files')
          .getPublicUrl(filePath);

      ('🔗 File public URL: $publicUrl');
    } catch (e) {
      ('❌ Error uploading file to storage: $e');
      ('📋 Error details: ${e.toString()}');
    }
  }

  Future<void> _ensureStorageBucket() async {
    try {
      await supabase.storage.from('learning_files').list();
      ('✅ Storage bucket "learning_files" exists');
    } catch (e) {
      ('⚠️ Storage bucket might not exist, creating it...');
      ('💡 Please create a "learning_files" bucket in your Supabase storage',);
    }
  }

  Widget _buildResourceLibraryTab() {
    return _isLoading
        ? Center(child: CircularProgressIndicator())
        : ListView.builder(
          itemCount: _resources.length,
          itemBuilder: (context, index) {
            final resource = _resources[index];
            final isDefaultResource = resource['is_default'] == true;
            final isUploadedToLearningTools =
                resource['is_uploaded_to_learning_tools'] == true;
            final hasFile = resource['file_name'] != null;

            return Card(
              margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              elevation: 5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                title: Row(
                  children: [
                    Text(
                      resource['title'],
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (isDefaultResource) ...[
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Default',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    if (isUploadedToLearningTools && !isDefaultResource) ...[
                      SizedBox(width: 8),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Uploaded',
                          style: TextStyle(
                            fontSize: 10,
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
                    Text("Category: ${resource['category']}"),
                    Text("Description: ${resource['description']}"),
                    if (hasFile) ...[
                      SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.attach_file, size: 16, color: Colors.grey),
                          SizedBox(width: 4),
                          Text(
                            resource['file_name'],
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ],
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person, size: 12, color: Colors.grey),
                        SizedBox(width: 4),
                        Text(
                          'Uploaded by: ${resource['uploaded_by']}',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ],
                ),
                leading:
                    hasFile
                        ? Icon(Icons.attachment, size: 40, color: Colors.orange)
                        : Icon(Icons.book, size: 40, color: Colors.indigo),
                trailing:
                    isUploadedToLearningTools
                        ? Icon(Icons.check_circle, color: Colors.green)
                        : IconButton(
                          icon: Icon(Icons.upload_rounded, color: Colors.blue),
                          onPressed: () {
                            (
                              '🖱️ Upload icon pressed for: ${resource['title']}',
                            );
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
    return Column(
      children: [
        // Toggle button for showing/hiding removed files
        if (_removedFiles.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Show removed files',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
                Switch(
                  value: _showRemovedFiles,
                  onChanged: (value) {
                    setState(() {
                      _showRemovedFiles = value;
                    });
                  },
                ),
              ],
            ),
          ),
        Expanded(
          child:
              _isLoadingFiles
                  ? Center(child: CircularProgressIndicator())
                  : _showRemovedFiles
                  ? _buildRemovedFilesList()
                  : _buildActiveFilesList(),
        ),
      ],
    );
  }

  Widget _buildActiveFilesList() {
    return _uploadedFiles.isEmpty
        ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_open, size: 80, color: Colors.grey[400]),
              SizedBox(height: 16),
              Text(
                'No files uploaded to Learning Tools yet',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
              SizedBox(height: 8),
              Text(
                'Upload files to Learning Tools using the upload button in Resources tab',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        )
        : ListView.builder(
          itemCount: _uploadedFiles.length,
          itemBuilder: (context, index) {
            final file = _uploadedFiles[index];
            final fileName = file['file_name'] ?? 'Unknown File';
            final fileExtension = fileName.split('.').last.toLowerCase();

            return Card(
              margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              elevation: 5,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                title: Text(
                  file['title'] ?? fileName,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("File: $fileName"),
                    if (file['category'] != null)
                      Text("Category: ${file['category']}"),
                    if (file['description'] != null)
                      Text(
                        "Description: ${file['description']}",
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person, size: 12, color: Colors.grey),
                        SizedBox(width: 4),
                        Text(
                          'Uploaded by: ${file['uploaded_by'] ?? 'Unknown'}',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    if (file['uploaded_at'] != null) ...[
                      SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 12,
                            color: Colors.grey,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Uploaded: ${_formatDate(file['uploaded_at'])}',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                leading: _getFileIcon(fileExtension),
                trailing: IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () {
                    _markFileAsRemoved(file);
                  },
                  tooltip: 'Mark as Removed',
                ),
              ),
            );
          },
        );
  }

  Widget _buildRemovedFilesList() {
    return _removedFiles.isEmpty
        ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_outline, size: 80, color: Colors.grey[400]),
              SizedBox(height: 16),
              Text(
                'No removed files',
                style: TextStyle(fontSize: 18, color: Colors.grey[600]),
              ),
              SizedBox(height: 8),
              Text(
                'Files you remove will appear here',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            ],
          ),
        )
        : ListView.builder(
          itemCount: _removedFiles.length,
          itemBuilder: (context, index) {
            final file = _removedFiles[index];
            final fileName = file['file_name'] ?? 'Unknown File';
            final fileExtension = fileName.split('.').last.toLowerCase();

            return Card(
              margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey[300]!),
              ),
              color: Colors.grey[50],
              child: ListTile(
                title: Row(
                  children: [
                    Text(
                      file['title'] ?? fileName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[600],
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Removed',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.red[800],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "File: $fileName",
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    if (file['category'] != null)
                      Text(
                        "Category: ${file['category']}",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person, size: 12, color: Colors.grey),
                        SizedBox(width: 4),
                        Text(
                          'Uploaded by: ${file['uploaded_by'] ?? 'Unknown'}',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                    if (file['removed_at'] != null) ...[
                      SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.delete_outline,
                            size: 12,
                            color: Colors.red,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Removed: ${_formatDate(file['removed_at'])}',
                            style: TextStyle(fontSize: 12, color: Colors.red),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
                leading: _getFileIcon(fileExtension, isRemoved: true),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.restore, color: Colors.green),
                      onPressed: () {
                        _restoreFile(file);
                      },
                      tooltip: 'Restore File',
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_forever, color: Colors.red),
                      onPressed: () {
                        _permanentlyDeleteFile(file);
                      },
                      tooltip: 'Permanently Delete',
                    ),
                  ],
                ),
              ),
            );
          },
        );
  }

  Icon _getFileIcon(String extension, {bool isRemoved = false}) {
    switch (extension) {
      case 'pdf':
        return Icon(
          Icons.picture_as_pdf,
          size: 40,
          color: isRemoved ? Colors.grey : Colors.red,
        );
      case 'doc':
      case 'docx':
        return Icon(
          Icons.description,
          size: 40,
          color: isRemoved ? Colors.grey : Colors.blue,
        );
      case 'txt':
        return Icon(
          Icons.text_fields,
          size: 40,
          color: isRemoved ? Colors.grey : Colors.grey,
        );
      case 'pptx':
      case 'ppt':
        return Icon(
          Icons.slideshow,
          size: 40,
          color: isRemoved ? Colors.grey : Colors.orange,
        );
      case 'zip':
      case 'rar':
        return Icon(
          Icons.folder_zip,
          size: 40,
          color: isRemoved ? Colors.grey : Colors.amber,
        );
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icon(
          Icons.image,
          size: 40,
          color: isRemoved ? Colors.grey : Colors.green,
        );
      default:
        return Icon(
          Icons.insert_drive_file,
          size: 40,
          color: isRemoved ? Colors.grey : Colors.indigo,
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
      builder:
          (context) => AlertDialog(
            title: Text('Mark as Removed'),
            content: Text(
              'Are you sure you want to mark "${file['title'] ?? file['file_name']}" as removed? The file will be moved to removed files list.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  'Mark as Removed',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      try {
        // Update the database record to mark as removed - only for current user's files
        await supabase
            .from('resources')
            .update({
              'is_removed': true,
              'removed_at': DateTime.now().toIso8601String(),
              'removed_by': _currentUserId, // FIXED: Use non-nullable user ID
            })
            .eq('id', file['id'])
            .eq('user_id', _currentUserId); // FIXED: Use non-nullable user ID

        // Refresh all data
        await _loadResources();
        await _loadUploadedFiles();
        await _loadRemovedFiles();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ File marked as removed'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } catch (e) {
        ('❌ Error marking file as removed: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error marking file as removed: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _restoreFile(Map<String, dynamic> file) async {
    try {
      // Update the database record to restore the file - only for current user's files
      await supabase
          .from('resources')
          .update({'is_removed': false, 'removed_at': null, 'removed_by': null})
          .eq('id', file['id'])
          .eq('user_id', _currentUserId); // FIXED: Use non-nullable user ID

      // Refresh all data
      await _loadResources();
      await _loadUploadedFiles();
      await _loadRemovedFiles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ File restored successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ('❌ Error restoring file: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error restoring file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _permanentlyDeleteFile(Map<String, dynamic> file) async {
    final bool? confirm = await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Permanently Delete File'),
            content: Text(
              'Are you sure you want to permanently delete "${file['title'] ?? file['file_name']}"? This action cannot be undone and the file will be removed from storage.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  'Delete Permanently',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
    );

    if (confirm == true) {
      try {
        // Delete file from storage first
        if (file['file_name'] != null) {
          try {
            final String fileName = file['file_name'];

            // First, try to list files to find the actual file path with timestamp
            final storageResponse = await supabase.storage
                .from('learning_files')
                .list(path: 'resource-library');

            // Look for files that contain the original filename
            final matchingFiles =
                storageResponse
                    .where((fileObj) => fileObj.name.contains(fileName))
                    .toList();

            if (matchingFiles.isNotEmpty) {
              // Delete all matching files (should typically be just one)
              for (final fileObj in matchingFiles) {
                final String filePath = 'resource-library/${fileObj.name}';
                await supabase.storage.from('learning_files').remove([
                  filePath,
                ]);
                ('✅ File deleted from storage: ${fileObj.name}');
              }
            } else {
              // Fallback: try the original filename without timestamp
              final String filePath = 'resource-library/$fileName';
              try {
                await supabase.storage.from('learning_files').remove([
                  filePath,
                ]);
                ('✅ File deleted from storage: $fileName');
              } catch (fallbackError) {
                (
                  '⚠️ Could not delete file with original name: $fallbackError',
                );
              }
            }
          } catch (storageError) {
            ('⚠️ Could not delete file from storage: $storageError');
          }
        }

        // Delete from database - only current user's files
        await supabase
            .from('resources')
            .delete()
            .eq('id', file['id'])
            .eq('user_id', _currentUserId); // FIXED: Use non-nullable user ID

        // Refresh removed files list
        await _loadRemovedFiles();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ File permanently deleted'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        ('❌ Error permanently deleting file: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Error deleting file: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    (
      '🏗️ Building ResourceLibraryScreen for user $_currentUserId with ${_resources.length} resources and ${_uploadedFiles.length} uploaded files',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'My Resource Library',
        ), // Changed to indicate personal library
        backgroundColor: Colors.indigo,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: Icon(Icons.library_books),
              text: 'My Resources',
            ), // Changed text
            Tab(
              icon: Icon(Icons.attach_file),
              text:
                  'Uploaded to Learning Tools (${_uploadedFiles.length})', // Updated text
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildResourceLibraryTab(), _buildUploadedFilesTab()],
      ),
      floatingActionButton:
          _currentTabIndex == 0
              ? FloatingActionButton(
                onPressed: _addNewResourceWithAttachment,
                backgroundColor: Colors.indigo,
                tooltip: 'Add New Resource with Attachment',
                child: Icon(Icons.add, color: Colors.white),
              )
              : null,
    );
  }
}

class AddResourceWithAttachmentDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onResourceAdded;
  final String currentUser;

  const AddResourceWithAttachmentDialog({
    super.key,
    required this.onResourceAdded,
    required this.currentUser,
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

  Future<void> _pickFile() async {
    setState(() {
      _isPickingFile = true;
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'txt',
          'pptx',
          'zip',
          'jpg',
          'png',
        ],
        allowMultiple: false,
      );

      if (result != null && result.files.single.bytes != null) {
        final file = result.files.single;
        setState(() {
          _fileBytes = file.bytes;
          _fileName = file.name;
          _fileSize = file.size;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'File selected: ${file.name} (${_formatFileSize(file.size)})',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (result != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Could not read file bytes. Please try another file.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking file: ${e.toString()}'),
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

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
        'uploadedBy': widget.currentUser,
        'uploadedAt': DateTime.now().toIso8601String(),
      };

      widget.onResourceAdded(newResource);
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _fileName != null
                ? 'Resource with attachment added successfully!'
                : 'Resource added successfully!',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
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
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.add_circle, color: Colors.indigo),
          SizedBox(width: 8),
          Text('Add New Resource'),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Uploader Info
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[100]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.person, size: 16, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Uploading as: ${widget.currentUser}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[800],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),

              // File Attachment Section
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade50,
                ),
                child: Column(
                  children: [
                    Icon(Icons.attach_file, size: 40, color: Colors.indigo),
                    SizedBox(height: 8),

                    if (_fileName != null) ...[
                      Column(
                        children: [
                          Text(
                            _fileName!,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          SizedBox(height: 4),
                          Text(
                            _fileSize != null
                                ? _formatFileSize(_fileSize!)
                                : '',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _isPickingFile ? null : _pickFile,
                                icon: Icon(Icons.change_circle),
                                label: Text('Change'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _clearFile,
                                icon: Icon(Icons.delete),
                                label: Text('Remove'),
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
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _isPickingFile ? null : _pickFile,
                        icon:
                            _isPickingFile
                                ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                : Icon(Icons.attach_file),
                        label: Text('Attach File'),
                      ),
                    ],

                    if (_fileName != null) ...[
                      SizedBox(height: 8),
                      Text(
                        'File will be available in Resources tab. Use the upload button to add to Learning Tools.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: 16),

              // Resource Details Form
              TextFormField(
                controller: _titleController,
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
              SizedBox(height: 12),
              TextFormField(
                controller: _categoryController,
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
                  if (value == null || value.isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),
              SizedBox(height: 12),
              TextFormField(
                controller: _linkController,
                decoration: InputDecoration(
                  labelText: 'Resource Link (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
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
          onPressed: _addResource,
          style: ElevatedButton.styleFrom(backgroundColor: const Color.fromARGB(255, 14, 14, 88)),
          child: Text('Add Resource'),
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
