import 'package:flutter/material.dart';
import '../services/call_manager.dart';
import '../services/call_screen.dart';

class GlobalCallNotification extends StatefulWidget {
  final CallManager callManager;

  const GlobalCallNotification({super.key, required this.callManager});

  @override
  State<GlobalCallNotification> createState() => _GlobalCallNotificationState();
}

class _GlobalCallNotificationState extends State<GlobalCallNotification> {

  
 
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.callManager.showNotification,
      builder: (context, showNotification, child) {
        if (!showNotification) return const SizedBox.shrink();

        return ValueListenableBuilder<Map<String, dynamic>?>(
          valueListenable: widget.callManager.currentCall,
          builder: (context, callData, child) {
            if (callData == null) return const SizedBox.shrink();

            final callerName = callData['caller_name'] ?? 'Unknown';
            final callType = callData['call_type'] ?? 'audio';
            final isVideoCall = callType == 'video';

            return Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.indigo.shade600,
                        Colors.purple.shade600,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          // Call icon
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Color.lerp(Colors.transparent, Colors.white, 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isVideoCall ? Icons.videocam : Icons.phone,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Caller info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Incoming ${isVideoCall ? 'Video' : 'Audio'} Call',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  callerName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Close button
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => widget.callManager.declineCall(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Action buttons
                      Row(
                        children: [
                          // Decline button
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.call_end, size: 20),
                              label: const Text('Decline'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () => widget.callManager.declineCall(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Accept button
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: Icon(
                                isVideoCall ? Icons.videocam : Icons.phone,
                                size: 20,
                              ),
                              label: Text(isVideoCall ? 'Video' : 'Audio'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: () {
                              widget.callManager.acceptCall();
                               Navigator.of(context).push(MaterialPageRoute(
                               builder: (context) => CallScreen(callData: callData),
                              ));
                            },
                      ))],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}