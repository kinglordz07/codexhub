// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import '../services/sessionservice.dart';
import 'package:codexhub01/mentorship/schedulesession_screen.dart'; // ✅ import

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

  Future<void> _loadSessions() async {
    setState(() => isLoading = true);

    try {
      final data = await _sessionService.getUserSessions(); // function sa SessionService
      setState(() {
        sessions = data;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Failed to load sessions: $e")));
    }
  }

  List<Map<String, dynamic>> _filterByStatus(String status) {
    return sessions.where((s) => s['status'] == status).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(

// sa AppBar:
appBar: AppBar(
  title: const Text("My Sessions"),
  backgroundColor: Colors.indigo,
  bottom: TabBar(
    controller: _tabController,
    tabs: const [
      Tab(text: "Pending"),
      Tab(text: "Accepted"),
      Tab(text: "Declined"),
    ],
  ),
  actions: [
    IconButton(
      icon: const Icon(Icons.add),
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

  Widget _buildSessionList(List<Map<String, dynamic>> sessions) {
  if (sessions.isEmpty) {
    return Center(
      child: Text(
        "No sessions here.",
        style: TextStyle(
          color: Theme.of(context).textTheme.bodyMedium?.color,
          fontSize: 16,
        ),
      ),
    );
  }

  return ListView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    itemCount: sessions.length,
    itemBuilder: (context, index) {
      final session = sessions[index];
      Color statusColor;
      switch (session['status']) {
        case 'accepted':
          statusColor = Colors.green;
          break;
        case 'declined':
          statusColor = Colors.red;
          break;
        case 'pending':
        default:
          statusColor = Colors.amber;
      }

      return Card(
        color: Theme.of(context).cardColor,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                session['session_type'] ?? 'Session',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Theme.of(context).textTheme.titleMedium?.color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Mentor: ${session['mentor_name'] ?? 'Unknown'}",
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
              Text(
                "Date: ${session['session_date']} at ${session['session_time']}",
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
              Text(
                "Notes: ${session['notes'] ?? 'None'}",
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "Status: ${session['status']}",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
    }