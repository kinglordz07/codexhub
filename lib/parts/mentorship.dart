// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class MentorshipScreen extends StatefulWidget {
  const MentorshipScreen({super.key});

  @override
  State<MentorshipScreen> createState() => _MentorshipScreenState();
}

class _MentorshipScreenState extends State<MentorshipScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = true;
  List<Map<String, dynamic>> _allMentors = [];
  List<Map<String, dynamic>> _acceptedMentors = [];
  
  late TabController _tabController;
  final SupabaseClient _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMentors();
  }

  Future<void> _loadMentors() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Load all mentors
      final mentorsResponse = await _supabase
          .from('profiles')
          .select()
          .eq('role', 'mentor')
          .order('username');

      // Load accepted mentorship requests
      final acceptedRequestsResponse = await _supabase
          .from('mentor_friend_requests')
          .select('receiver_id, status')
          .eq('sender_id', user.id)
          .eq('status', 'accepted');

      // Get the profile data for accepted mentors
      final acceptedMentorIds = acceptedRequestsResponse
          .map<String>((request) => request['receiver_id'].toString())
          .toList();

      List<Map<String, dynamic>> acceptedMentorsProfiles = [];
      if (acceptedMentorIds.isNotEmpty) {
        // Use the correct 'in' method (without underscore)
        final profilesResponse = await _supabase
            .from('profiles')
            .select()
            .inFilter('id', acceptedMentorIds);

        acceptedMentorsProfiles = List<Map<String, dynamic>>.from(profilesResponse);
      }

      setState(() {
        _allMentors = List<Map<String, dynamic>>.from(mentorsResponse);
      
        _acceptedMentors = acceptedMentorsProfiles;
        _isLoading = false;
      });
    } catch (error) {
      ('Error loading mentors: $error');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load mentors: $error')),
      );
    }
  }

  List<Map<String, dynamic>> get _filteredMentors {
    final List<Map<String, dynamic>> currentList;
    
    if (_tabController.index == 0) {
      // My Mentors tab - show accepted mentors
      currentList = _acceptedMentors;
    } else {
      // Suggested Mentors tab - show all mentors except accepted ones
      final acceptedMentorIds = _acceptedMentors.map((m) => m['id']).toSet();
      currentList = _allMentors
          .where((mentor) => !acceptedMentorIds.contains(mentor['id']))
          .toList();
    }

    if (_searchQuery.isEmpty) return currentList;

    return currentList.where((mentor) {
      final usernameLower = mentor['username']?.toString().toLowerCase() ?? '';
      final queryLower = _searchQuery.toLowerCase();
      return usernameLower.contains(queryLower);
    }).toList();
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

      await _supabase.from('mentor_friend_requests').insert({
        'sender_id': user.id,
        'receiver_id': mentor['id'],
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Mentorship request sent to ${mentor['username']}!'),
        ),
      );
    } catch (error) {
      ('Error sending request: $error');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send request: $error')),
      );
    }
  }

  Future<void> _sendMessage(BuildContext context, Map<String, dynamic> mentor) async {
    // In a real app, this would navigate to a chat screen
    // For now, we'll show a dialog or snackbar
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Message'),
        content: Text('Would you like to send a message to ${mentor['username']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Message sent to ${mentor['username']}!'),
                ),
              );
              // Here you would navigate to the chat screen
              // Navigator.push(context, MaterialPageRoute(builder: (context) => ChatScreen(mentor: mentor)));
            },
            child: const Text('Send Message'),
          ),
        ],
      ),
    );
  }

  Future<void> _initiateCall(BuildContext context, Map<String, dynamic> mentor) async {
    // Check if the mentor has a phone number
    final phoneNumber = mentor['phone_number']?.toString();
    
    if (phoneNumber == null || phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${mentor['username']} has no phone number available'),
        ),
      );
      return;
    }

    final url = 'tel:$phoneNumber';
    
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not launch phone app'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mentors'),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMentors,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
              icon: Icon(Icons.group),
              text: 'My Mentors',
            ),
            Tab(
              icon: Icon(Icons.people_alt_outlined),
              text: 'Suggested',
            ),
          ],
          onTap: (index) {
            setState(() {}); // Refresh the list when tab changes
          },
        ),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: _tabController.index == 0 
                    ? 'Search my mentors...' 
                    : 'Search suggested mentors...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: _searchQuery.isNotEmpty
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

          // Tab content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // My Mentors Tab
                      _buildMentorsList(isAcceptedMentors: true),
                      
                      // Suggested Mentors Tab
                      _buildMentorsList(isAcceptedMentors: false),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMentorsList({required bool isAcceptedMentors}) {
    final mentors = _filteredMentors;
    
    if (mentors.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isAcceptedMentors ? Icons.group_off : Icons.people_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              isAcceptedMentors
                  ? _searchQuery.isEmpty
                      ? 'No mentors yet'
                      : 'No mentors found for "$_searchQuery"'
                  : _searchQuery.isEmpty
                      ? 'No suggested mentors available'
                      : 'No mentors found for "$_searchQuery"',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            if (_searchQuery.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: TextButton(
                  onPressed: _loadMentors,
                  child: const Text('Refresh'),
                ),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: mentors.length,
      itemBuilder: (context, index) {
        final mentor = mentors[index];
        return _MentorListItem(
          mentor: mentor,
          isAcceptedMentor: isAcceptedMentors,
          onRequest: () => _sendMentorshipRequest(context, mentor),
          onMessage: isAcceptedMentors 
              ? () => _sendMessage(context, mentor)
              : null,
          onCall: isAcceptedMentors 
              ? () => _initiateCall(context, mentor)
              : null,
        );
      },
    );
  }
}

class _MentorListItem extends StatelessWidget {
  final Map<String, dynamic> mentor;
  final bool isAcceptedMentor;
  final VoidCallback onRequest;
  final VoidCallback? onMessage;
  final VoidCallback? onCall;

  const _MentorListItem({
    required this.mentor,
    required this.isAcceptedMentor,
    required this.onRequest,
    this.onMessage,
    this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mentor Header
            Row(
              children: [
                _buildAvatar(mentor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mentor['username']?.toString() ?? 'Unknown Mentor',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Mentor',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                      if (isAcceptedMentor) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Connected',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Online Status Indicator
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: (mentor['online_status'] == true) 
                        ? Colors.green 
                        : Colors.grey,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ],
            ),

            // Action Buttons - Different based on whether it's accepted or suggested
            const SizedBox(height: 16),
            if (isAcceptedMentor)
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(
                        Icons.message,
                        color: Colors.white,
                        size: 20,
                      ),
                      label: const Text(
                        'Message',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onCall,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(
                        Icons.phone,
                        color: Colors.white,
                        size: 20,
                      ),
                      label: const Text(
                        'Call',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(
                    Icons.group_add,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: const Text(
                    'Send Mentorship Request',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(Map<String, dynamic> mentor) {
    final avatarUrl = mentor['avatar_url'];
    final username = mentor['username']?.toString() ?? '?';
    final firstLetter = username.isNotEmpty ? username[0].toUpperCase() : '?';

    if (avatarUrl != null && avatarUrl.toString().isNotEmpty) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(avatarUrl.toString()),
        onBackgroundImageError: (exception, stackTrace) {
          ('Failed to load avatar image: $exception');
        },
        child: avatarUrl.toString().isEmpty ? Text(firstLetter) : null,
      );
    }

    return CircleAvatar(
      backgroundColor: isAcceptedMentor ? Colors.green : Colors.indigo,
      radius: 24,
      child: Text(
        firstLetter,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}