// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import '../services/sessionservice.dart';

class SessionListScreen extends StatefulWidget {
  const SessionListScreen({super.key});

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen>
    with SingleTickerProviderStateMixin {
  final SessionService _sessionService = SessionService();
  bool isLoading = true;
  List<Map<String, dynamic>> sessions = [];

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSessions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSessions() async {
    setState(() => isLoading = true);
    try {
      final data = await _sessionService.getMentorSessions();
      setState(() {
        sessions = data;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load sessions: $e")),
      );
    }
  }

  Future<void> _updateSessionStatus(String sessionId, String status) async {
    try {
      await _sessionService.updateSessionStatus(sessionId, status);
      _loadSessions(); // refresh
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Session $status")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to update session: $e")),
      );
    }
  }

  Future<void> _rescheduleSession(Map<String, dynamic> session) async {
    final DateTime? newDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (newDate == null) return;

    final TimeOfDay? newTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (newTime == null) return;

    final DateTime newDateTime = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      newTime.hour,
      newTime.minute,
    );

    try {
      await _sessionService.rescheduleSession(
        session['id'],
        newDateTime.toIso8601String().split('T')[0], // Date part
        "${newTime.hour.toString().padLeft(2, '0')}:${newTime.minute.toString().padLeft(2, '0')}", // Time part
      );
      
      _loadSessions(); // refresh
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Session rescheduled successfully!")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to reschedule session: $e")),
      );
    }
  }

  List<Map<String, dynamic>> _filterByStatus(String status) {
    return sessions.where((s) => s['status'] == status).toList();
  }

  // Responsive layout detection
  bool get isSmallScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width < 600;
  }

  bool get isMediumScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width >= 600 && mediaQuery.size.width < 1024;
  }

  bool get isLargeScreen {
    final mediaQuery = MediaQuery.of(context);
    return mediaQuery.size.width >= 1024;
  }

  Widget _buildSessionList(List<Map<String, dynamic>> list) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 16.0 : 24.0),
          child: Text(
            "No sessions here.",
            style: TextStyle(
              fontSize: isSmallScreen ? 16 : 18,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
        ),
      );
    }

    // Use different layouts based on screen size
    if (isLargeScreen) {
      return _buildGridView(list);
    } else {
      return _buildListView(list);
    }
  }

  Widget _buildListView(List<Map<String, dynamic>> list) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: ListView.builder(
        padding: EdgeInsets.symmetric(
          vertical: isSmallScreen ? 12 : 16,
          horizontal: isSmallScreen ? 16 : 24,
        ),
        itemCount: list.length,
        itemBuilder: (context, index) {
          return _buildSessionCard(list[index], isDark);
        },
      ),
    );
  }

  Widget _buildGridView(List<Map<String, dynamic>> list) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: GridView.builder(
        padding: const EdgeInsets.all(24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: isMediumScreen ? 1.5 : 1.8,
        ),
        itemCount: list.length,
        itemBuilder: (context, index) {
          return _buildSessionCard(list[index], isDark);
        },
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session, bool isDark) {
    final status = session['status'] ?? 'pending';
    final isPending = status == 'pending';
    final isAccepted = status == 'accepted';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? Colors.grey[850] : Colors.white,
      margin: EdgeInsets.symmetric(vertical: isSmallScreen ? 8 : 12),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 16.0 : 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Icon(
                  Icons.person,
                  color: Colors.indigo,
                  size: isSmallScreen ? 20 : 24,
                ),
                SizedBox(width: isSmallScreen ? 12 : 16),
                Expanded(
                  child: Text(
                    "${session['profiles_new']?['username'] ?? 'Unknown User'} "
                    "(${session['session_type'] ?? 'N/A'})",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isSmallScreen ? 16 : 18,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isPending)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 8 : 12,
                      vertical: isSmallScreen ? 4 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: status == 'accepted' 
                          ? Colors.green.withAlpha(25)
                          : status == 'rescheduled'
                          ? Colors.orange.withAlpha(25)
                          : Colors.red.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isSmallScreen ? 12 : 14,
                        color: status == 'accepted' 
                            ? Colors.green 
                            : status == 'rescheduled'
                            ? Colors.orange
                            : Colors.red,
                      ),
                    ),
                  ),
              ],
            ),
            
            SizedBox(height: isSmallScreen ? 8 : 12),
            
            // Session Details
            _buildDetailRow(
              Icons.calendar_today,
              "Date: ${session['session_date'] ?? 'N/A'} at ${session['session_time'] ?? 'N/A'}",
              isDark,
            ),
            
            SizedBox(height: isSmallScreen ? 4 : 8),
            
            _buildDetailRow(
              Icons.note,
              "Notes: ${session['notes'] ?? 'None'}",
              isDark,
            ),

            // Rescheduled info if applicable
            if (session['rescheduled_at'] != null) ...[
              SizedBox(height: isSmallScreen ? 4 : 8),
              _buildDetailRow(
                Icons.schedule,
                "Rescheduled on: ${_formatRescheduledDate(session['rescheduled_at'])}",
                isDark,
              ),
            ],
            
            // Action Buttons
            SizedBox(height: isSmallScreen ? 12 : 16),
            _buildActionButtons(session, isPending, isAccepted),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: isSmallScreen ? 16 : 18,
          color: isDark ? Colors.white60 : Colors.black54,
        ),
        SizedBox(width: isSmallScreen ? 8 : 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> session, bool isPending, bool isAccepted) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isPending) ...[
          // Pending session actions
          Flexible(
            child: ElevatedButton.icon(
              icon: Icon(Icons.check, size: isSmallScreen ? 18 : 20),
              label: Text(
                "Accept",
                style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 12 : 16,
                  vertical: isSmallScreen ? 8 : 12,
                ),
              ),
              onPressed: () => _updateSessionStatus(session['id'], 'accepted'),
            ),
          ),
          SizedBox(width: isSmallScreen ? 8 : 12),
          Flexible(
            child: ElevatedButton.icon(
              icon: Icon(Icons.schedule, size: isSmallScreen ? 18 : 20),
              label: Text(
                "Reschedule",
                style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 12 : 16,
                  vertical: isSmallScreen ? 8 : 12,
                ),
              ),
              onPressed: () => _rescheduleSession(session),
            ),
          ),
          SizedBox(width: isSmallScreen ? 8 : 12),
          Flexible(
            child: ElevatedButton.icon(
              icon: Icon(Icons.close, size: isSmallScreen ? 18 : 20),
              label: Text(
                "Decline",
                style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 12 : 16,
                  vertical: isSmallScreen ? 8 : 12,
                ),
              ),
              onPressed: () => _updateSessionStatus(session['id'], 'declined'),
            ),
          ),
        ] else if (isAccepted) ...[
          // Accepted session actions - can still reschedule
          Flexible(
            child: ElevatedButton.icon(
              icon: Icon(Icons.schedule, size: isSmallScreen ? 18 : 20),
              label: Text(
                "Reschedule",
                style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 12 : 16,
                  vertical: isSmallScreen ? 8 : 12,
                ),
              ),
              onPressed: () => _rescheduleSession(session),
            ),
          ),
          SizedBox(width: isSmallScreen ? 8 : 12),
          Flexible(
            child: ElevatedButton.icon(
              icon: Icon(Icons.cancel, size: isSmallScreen ? 18 : 20),
              label: Text(
                "Cancel",
                style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 12 : 16,
                  vertical: isSmallScreen ? 8 : 12,
                ),
              ),
              onPressed: () => _updateSessionStatus(session['id'], 'cancelled'),
            ),
          ),
        ],
      ],
    );
  }

  String _formatRescheduledDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Session Requests"),
        backgroundColor: primaryColor,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: "Pending"),
            Tab(text: "Accepted"),
            Tab(text: "Declined"),
          ],
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSessionList(_filterByStatus('pending')),
                _buildSessionList(_filterByStatus('accepted')),
                _buildSessionList(_filterByStatus('declined')),
              ],
            ),
    );
  }
}