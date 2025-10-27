import 'package:flutter/material.dart';
import '../services/sessionservice.dart';
import 'package:codexhub01/mentorship/schedulesession_screen.dart'; 

class MySessionsScreen extends StatefulWidget {
  const MySessionsScreen({super.key});

  @override
  State<MySessionsScreen> createState() => _MySessionsScreenState();
}

class _MySessionsScreenState extends State<MySessionsScreen>
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
      final data = await _sessionService.getUserSessions();
      setState(() {
        sessions = data;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if (mounted) {
  ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text("Failed to load sessions: $e")));
}}
  }

  List<Map<String, dynamic>> _filterByStatus(String status) {
    return sessions.where((s) => s['status'] == status).toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final isVerySmallScreen = screenSize.width < 400;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "My Sessions",
          style: TextStyle(fontSize: isSmallScreen ? 18 : 20),
          
        ),
        backgroundColor: Colors.indigo,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.lightBlueAccent,
          tabs: [
            Tab(
              text: isVerySmallScreen ? "Pending" : "Pending",
              icon: isVerySmallScreen ? const Icon(Icons.pending) : null,
            ),
            Tab(
              text: isVerySmallScreen ? "Accepted" : "Accepted",
              icon: isVerySmallScreen ? const Icon(Icons.check_circle) : null,
            ),
            Tab(
              text: isVerySmallScreen ? "Declined" : "Declined",
              icon: isVerySmallScreen ? const Icon(Icons.cancel) : null,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.add,
              color: Colors.white,
              size: isSmallScreen ? 20 : 24,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ScheduleSessionScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildSessionList(_filterByStatus('pending'), screenSize, isSmallScreen),
                  _buildSessionList(_filterByStatus('accepted'), screenSize, isSmallScreen),
                  _buildSessionList(_filterByStatus('declined'), screenSize, isSmallScreen),
                ],
              ),
      ),
    );
  }

  Widget _buildSessionList(List<Map<String, dynamic>> sessions, Size screenSize, bool isSmallScreen) {
    if (sessions.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_today,
                size: isSmallScreen ? 48 : 64,
                color: Colors.grey[400],
              ),
              SizedBox(height: isSmallScreen ? 12 : 16),
              Text(
                "No sessions here",
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                  fontSize: isSmallScreen ? 16 : 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: isSmallScreen ? 8 : 12),
              Text(
                "Schedule a new session to get started",
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: isSmallScreen ? 14 : 16,
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
        horizontal: isSmallScreen ? 8 : 12,
        vertical: isSmallScreen ? 6 : 8,
      ),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        Color statusColor;
        IconData statusIcon;
        
        switch (session['status']) {
          case 'accepted':
            statusColor = Colors.green;
            statusIcon = Icons.check_circle;
            break;
          case 'declined':
            statusColor = Colors.red;
            statusIcon = Icons.cancel;
            break;
          case 'pending':
          default:
            statusColor = Colors.amber;
            statusIcon = Icons.pending;
        }

        return Card(
          color: Theme.of(context).cardColor,
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: EdgeInsets.symmetric(
            horizontal: isSmallScreen ? 4 : 0,
            vertical: isSmallScreen ? 6 : 8,
          ),
          child: Padding(
            padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row with session type and status
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        session['session_type'] ?? 'Session',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: isSmallScreen ? 16 : 18,
                          color: Theme.of(context).textTheme.titleMedium?.color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 8 : 12,
                        vertical: isSmallScreen ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            statusIcon,
                            size: isSmallScreen ? 14 : 16,
                            color: statusColor,
                          ),
                          if (!isSmallScreen) ...[
                            SizedBox(width: 4),
                            Text(
                              session['status'],
                              style: TextStyle(
                                fontSize: isSmallScreen ? 12 : 14,
                                fontWeight: FontWeight.w600,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: isSmallScreen ? 8 : 12),
                
                // Mentor info
                Row(
                  children: [
                    Icon(
                      Icons.person,
                      size: isSmallScreen ? 16 : 18,
                      color: Colors.grey[600],
                    ),
                    SizedBox(width: isSmallScreen ? 6 : 8),
                    Expanded(
                      child: Text(
                        "Mentor: ${session['mentor_name'] ?? 'Unknown'}",
                        style: TextStyle(
                          fontSize: isSmallScreen ? 14 : 16,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: isSmallScreen ? 6 : 8),
                
                // Date and time
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: isSmallScreen ? 16 : 18,
                      color: Colors.grey[600],
                    ),
                    SizedBox(width: isSmallScreen ? 6 : 8),
                    Expanded(
                      child: Text(
                        "Date: ${session['session_date']} at ${session['session_time']}",
                        style: TextStyle(
                          fontSize: isSmallScreen ? 14 : 16,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: isSmallScreen ? 6 : 8),
                
                // Notes
                if (session['notes'] != null && session['notes'].toString().isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.note,
                            size: isSmallScreen ? 16 : 18,
                            color: Colors.grey[600],
                          ),
                          SizedBox(width: isSmallScreen ? 6 : 8),
                          Text(
                            "Notes:",
                            style: TextStyle(
                              fontSize: isSmallScreen ? 14 : 16,
                              color: Theme.of(context).textTheme.bodyMedium?.color,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: isSmallScreen ? 4 : 6),
                      Padding(
                        padding: EdgeInsets.only(left: isSmallScreen ? 24 : 28),
                        child: Text(
                          session['notes'] ?? 'None',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 13 : 15,
                            color: Colors.grey[700],
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}