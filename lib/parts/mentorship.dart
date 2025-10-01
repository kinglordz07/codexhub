import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MentorshipScreen extends StatefulWidget {
  const MentorshipScreen({super.key});

  @override
  State<MentorshipScreen> createState() => _MentorshipScreenState();
}

class _MentorshipScreenState extends State<MentorshipScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = true;
  List<Map<String, dynamic>> _allMentors = [];

  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadMentors();
  }

  Future<void> _loadMentors() async {
    try {
      final response = await _supabase
          .from('mentors')
          .select()
          .eq('status', 'active')
          .order('name');

      setState(() {
        _allMentors = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (error) {
      print('Error loading mentors: $error');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load mentors: $error')));
    }
  }

  List<Map<String, dynamic>> get _filteredMentors {
    if (_searchQuery.isEmpty) return _allMentors;

    return _allMentors.where((mentor) {
      final nameLower = mentor['name']?.toString().toLowerCase() ?? '';
      final expertiseLower =
          mentor['expertise']?.toString().toLowerCase() ?? '';
      final bioLower = mentor['bio']?.toString().toLowerCase() ?? '';
      final queryLower = _searchQuery.toLowerCase();

      return nameLower.contains(queryLower) ||
          expertiseLower.contains(queryLower) ||
          bioLower.contains(queryLower);
    }).toList();
  }

  void _openChat(BuildContext context, Map<String, dynamic> mentor) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ChatScreen(mentor: mentor)),
    );
  }

  void _startVideoCall(BuildContext context, String mentorName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Video call feature with $mentorName coming soon!"),
      ),
    );
  }

  Future<void> _sendMentorshipRequest(
    BuildContext context,
    Map<String, dynamic> mentor,
  ) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login to send mentorship requests'),
          ),
        );
        return;
      }

      // Get current user profile
      final userResponse =
          await _supabase
              .from('profiles')
              .select('full_name')
              .eq('id', user.id)
              .single();

      await _supabase.from('mentorship_requests').insert({
        'mentor_id': mentor['id'],
        'mentor_name': mentor['name'],
        'mentee_id': user.id,
        'mentee_name': userResponse['full_name'] ?? 'User',
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mentorship request sent to ${mentor['name']}!'),
        ),
      );
    } catch (error) {
      print('Error sending request: $error');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send request: $error')));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mentorship'),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadMentors),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search mentors by name or expertise...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon:
                    _searchQuery.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                              _searchController.clear();
                            });
                          },
                        )
                        : null,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            ),
          ),
          Expanded(
            child:
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _filteredMentors.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 64,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty
                                ? 'No mentors available'
                                : 'No mentors found for "$_searchQuery"',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (_searchQuery.isEmpty)
                            TextButton(
                              onPressed: _loadMentors,
                              child: const Text('Refresh'),
                            ),
                        ],
                      ),
                    )
                    : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredMentors.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final mentor = _filteredMentors[index];
                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.indigo,
                                    radius: 24,
                                    child: Text(
                                      mentor['name']?[0] ?? '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    mentor['name']?.toString() ??
                                        'Unknown Mentor',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        'Expertise: ${mentor['expertise']?.toString() ?? 'Not specified'}',
                                        style: const TextStyle(
                                          color: Colors.grey,
                                        ),
                                      ),
                                      if (mentor['bio'] != null &&
                                          mentor['bio'].toString().isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 8.0,
                                          ),
                                          child: Text(
                                            mentor['bio'].toString(),
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.black54,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed:
                                            () => _openChat(context, mentor),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.chat,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          "Chat",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed:
                                            () => _startVideoCall(
                                              context,
                                              mentor['name']?.toString() ??
                                                  'Mentor',
                                            ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.purple,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.video_call,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Video Call',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed:
                                            () => _sendMentorshipRequest(
                                              context,
                                              mentor,
                                            ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.indigo,
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                          ),
                                        ),
                                        icon: const Icon(
                                          Icons.group_add,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        label: const Text(
                                          'Request',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> mentor;
  const ChatScreen({super.key, required this.mentor});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final List<Map<String, dynamic>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final SupabaseClient _supabase = Supabase.instance.client;

  void _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;

    final messageText = _controller.text.trim();
    _controller.clear();

    // Add message to UI immediately
    setState(() {
      _messages.add({
        "sender": "You",
        "message": messageText,
        "timestamp": DateTime.now().toIso8601String(),
        "is_sent": true,
      });
    });
    _scrollToBottom();

    try {
      // Save message to Supabase
      await _supabase.from('chat_messages').insert({
        'mentor_id': widget.mentor['id'],
        'sender_id': _supabase.auth.currentUser?.id,
        'message': messageText,
        'sent_at': DateTime.now().toIso8601String(),
      });

      // Update message status to sent
      if (_messages.isNotEmpty) {
        setState(() {
          _messages.last['is_sent'] = true;
        });
      }

      // Simulate mentor reply after 2 seconds
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _messages.add({
              "sender": widget.mentor['name']?.toString() ?? 'Mentor',
              "message": "Thanks for your message! I'll get back to you soon.",
              "timestamp": DateTime.now().toIso8601String(),
              "is_mentor": true,
            });
          });
          _scrollToBottom();
        }
      });
    } catch (error) {
      print('Error sending message: $error');
      // Show error status
      if (_messages.isNotEmpty) {
        setState(() {
          _messages.last['is_sent'] = false;
          _messages.last['error'] = true;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _loadChatHistory() async {
    try {
      final response = await _supabase
          .from('chat_messages')
          .select()
          .eq('mentor_id', widget.mentor['id'])
          .order('sent_at', ascending: true);

      setState(() {
        _messages.addAll(
          response.map(
            (msg) => {
              "sender":
                  msg['sender_id'] == _supabase.auth.currentUser?.id
                      ? "You"
                      : widget.mentor['name'],
              "message": msg['message']?.toString() ?? '',
              "timestamp": msg['sent_at']?.toString() ?? '',
              "is_sent": true,
              "is_mentor": msg['sender_id'] != _supabase.auth.currentUser?.id,
            },
          ),
        );
      });
      _scrollToBottom();
    } catch (error) {
      print('Error loading chat history: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
    _scrollToBottom();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Chat with ${widget.mentor['name']?.toString() ?? 'Mentor'}"),
            Text(
              widget.mentor['expertise']?.toString() ?? '',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.video_call),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    "Video call with ${widget.mentor['name']} coming soon!",
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child:
                _messages.isEmpty
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.indigo[100],
                            radius: 32,
                            child: Text(
                              widget.mentor['name']?[0] ?? '?',
                              style: TextStyle(
                                color: Colors.indigo,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "Start a conversation with ${widget.mentor['name']?.toString() ?? 'your mentor'}",
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            "Expertise: ${widget.mentor['expertise']?.toString() ?? ''}",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                    : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        final isMe = message["sender"] == "You";
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment:
                                isMe
                                    ? MainAxisAlignment.end
                                    : MainAxisAlignment.start,
                            children: [
                              if (!isMe)
                                CircleAvatar(
                                  backgroundColor: Colors.indigo,
                                  radius: 16,
                                  child: Text(
                                    widget.mentor['name']?[0] ?? '?',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color:
                                        isMe ? Colors.indigo : Colors.grey[300],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (!isMe)
                                        Text(
                                          message["sender"]!,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.indigo[800],
                                            fontSize: 12,
                                          ),
                                        ),
                                      Text(
                                        message["message"]!,
                                        style: TextStyle(
                                          fontSize: 16,
                                          color:
                                              isMe
                                                  ? Colors.white
                                                  : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatTime(message["timestamp"]),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color:
                                              isMe
                                                  ? Colors.white70
                                                  : Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (isMe) const SizedBox(width: 8),
                              if (isMe)
                                CircleAvatar(
                                  backgroundColor: Colors.green,
                                  radius: 16,
                                  child: const Text(
                                    "Y",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
          ),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText:
                          "Type a message to ${widget.mentor['name']?.toString() ?? 'mentor'}...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.indigo,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }
}
