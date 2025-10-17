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

  List<Map<String, dynamic>> _filterByStatus(String status) {
    return sessions.where((s) => s['status'] == status).toList();
  }

  Widget _buildSessionList(List<Map<String, dynamic>> list) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (list.isEmpty) {
      return Center(
        child: Text(
          "No sessions here.",
          style: TextStyle(
            fontSize: 16,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final session = list[index];
        final status = session['status'] ?? 'pending';
        final isPending = status == 'pending';

        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: isDark ? Colors.grey[850] : Colors.white,
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, color: Colors.indigo),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "${session['profiles']?['username'] ?? 'Unknown User'} "
                        "(${session['session_type'] ?? 'N/A'})",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                    if (!isPending)
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: status == 'accepted'
                              ? Colors.green
                              : Colors.red,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Date: ${session['session_date'] ?? 'N/A'} "
                  "at ${session['session_time'] ?? 'N/A'}",
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  "Notes: ${session['notes'] ?? 'None'}",
                  style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54),
                ),
                if (isPending) const SizedBox(height: 12),
                if (isPending)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.check),
                        label: const Text("Accept"),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green),
                        onPressed: () =>
                            _updateSessionStatus(session['id'], 'accepted'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.close),
                        label: const Text("Decline"),
                        style:
                            ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () =>
                            _updateSessionStatus(session['id'], 'declined'),
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
