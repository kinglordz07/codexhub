import 'package:flutter/material.dart';

class CallScreen extends StatelessWidget {
  final Map<String, dynamic> callData;
  
  const CallScreen({super.key, required this.callData});

  @override
  Widget build(BuildContext context) {
    final isVideoCall = callData['call_type'] == 'video';
    final otherUserName = callData['caller_name'] ?? 'User';
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'In Call with $otherUserName',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
            SizedBox(height: 20),
            if (isVideoCall)
              Container(
                width: 200,
                height: 200,
                color: Colors.grey,
                child: Center(child: Text('Video Feed')),
              ),
            SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // End call button
                FloatingActionButton(
                  onPressed: () => Navigator.pop(context),
                  backgroundColor: Colors.red,
                  child: Icon(Icons.call_end),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}