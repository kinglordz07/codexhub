import 'package:flutter/material.dart';
import '../services/call_manger.dart';

class CallScreen extends StatelessWidget {
  final Map<String, dynamic> callData;
  
  const CallScreen({super.key, required this.callData});

  @override
  Widget build(BuildContext context) {
    final isVideoCall = callData['call_type'] == 'video';
    final otherUserName = callData['caller_name'] ?? 'User';
    final callId = callData['id'];
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header with call info
            Container(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'In Call with $otherUserName',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  SizedBox(height: 8),
                  Text(
                    isVideoCall ? 'Video Call' : 'Audio Call',
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
            
            // Video preview (if video call)
            if (isVideoCall)
              Expanded(
                child: Container(
                  margin: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam, size: 64, color: Colors.white54),
                        SizedBox(height: 16),
                        Text(
                          'Video Feed',
                          style: TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.indigo,
                        child: Icon(
                          Icons.person,
                          size: 60,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 20),
                      Text(
                        otherUserName,
                        style: TextStyle(color: Colors.white, fontSize: 24),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Audio Call',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            
            // Call controls
            Container(
              padding: EdgeInsets.all(24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute button
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.grey[700],
                    child: IconButton(
                      icon: Icon(Icons.mic_off, color: Colors.white),
                      onPressed: () {},
                    ),
                  ),
                  
                  // End call button
                  CircleAvatar(
                    radius: 35,
                    backgroundColor: Colors.red,
                    child: IconButton(
                      icon: Icon(Icons.call_end, color: Colors.white, size: 30),
                      onPressed: () {
                        // End the call and pop back
                        CallManager().endCall(callId);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                  
                  // Speaker button
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.grey[700],
                    child: IconButton(
                      icon: Icon(Icons.volume_up, color: Colors.white),
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}