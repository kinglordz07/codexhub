import 'package:flutter/material.dart';
import '../services/sessionservice.dart';

class SessionListScreen extends StatefulWidget {
  const SessionListScreen({super.key});

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  final SessionService _sessionService = SessionService();
  bool isLoading = true;
  List<Map<String, dynamic>> sessions = [];

  @override
  void initState() {
    super.initState();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to load sessions: $e")));
    }
  }

  Future<void> _updateSessionStatus(String sessionId, String status) async {
    try {
      await _sessionService.updateSessionStatus(sessionId, status);
      _loadSessions(); // refresh after update
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Session $status")));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed to update session: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("My Session Requests"),
        backgroundColor: Colors.indigo,
      ),
      body:
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : sessions.isEmpty
              ? const Center(child: Text("No session requests yet."))
              : ListView.builder(
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.person, color: Colors.indigo),
                      title: Text(
                        "${session['profiles']?['username'] ?? 'Unknown User'} "
                        "(${session['session_type']})",
                      ),
                      subtitle: Text(
                        "Date: ${session['session_date'] ?? 'N/A'} "
                        "at ${session['session_time'] ?? 'N/A'}\n"
                        "Notes: ${session['notes'] ?? 'None'}\n"
                        "Status: ${session['status']}",
                      ),
                      isThreeLine: true,
                      trailing:
                          session['status'] == 'pending'
                              ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.check,
                                      color: Colors.green,
                                    ),
                                    onPressed:
                                        () => _updateSessionStatus(
                                          session['id'],
                                          'accepted',
                                        ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.close,
                                      color: Colors.red,
                                    ),
                                    onPressed:
                                        () => _updateSessionStatus(
                                          session['id'],
                                          'declined',
                                        ),
                                  ),
                                ],
                              )
                              : Text(
                                session['status'].toUpperCase(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      session['status'] == 'accepted'
                                          ? Colors.green
                                          : Colors.red,
                                ),
                              ),
                    ),
                  );
                },
              ),
    );
  }
}
