import 'package:flutter/material.dart';

class ProgressTrackerScreen extends StatelessWidget {
  final List<Map<String, dynamic>> menteeProgress = [
    {'name': 'Juan Dela Cruz', 'progress': 80, 'status': 'Near Completion', 'tasksCompleted': 15, 'totalTasks': 20},
    {'name': 'Maria Santos', 'progress': 60, 'status': 'Improving', 'tasksCompleted': 12, 'totalTasks': 20},
    {'name': 'Luis Gomez', 'progress': 90, 'status': 'Excellent', 'tasksCompleted': 19, 'totalTasks': 20},
    {'name': 'Ana Lopez', 'progress': 45, 'status': 'Needs Guidance', 'tasksCompleted': 9, 'totalTasks': 20},
  ];

  ProgressTrackerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Progress Tracker'),
        backgroundColor: Colors.indigo,
      ),
      body: ListView.builder(
        itemCount: menteeProgress.length,
        itemBuilder: (context, index) {
          return Card(
            margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            elevation: 5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              title: Text(
                menteeProgress[index]['name'],
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Status: ${menteeProgress[index]['status']}'),
                  Text('Tasks Completed: ${menteeProgress[index]['tasksCompleted']} / ${menteeProgress[index]['totalTasks']}'),
                  SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: menteeProgress[index]['progress'] / 100,
                    color: menteeProgress[index]['progress'] > 75 ? Colors.green : menteeProgress[index]['progress'] > 50 ? Colors.orange : Colors.red,
                  ),
                ],
              ),
              leading: Icon(Icons.person, size: 40, color: Colors.indigo),
            ),
          );
        },
      ),
    );
  }
}