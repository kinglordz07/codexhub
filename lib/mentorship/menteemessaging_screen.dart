import 'dart:async';
import 'package:flutter/material.dart';
import 'package:codexhub01/services/messageservice.dart';
import 'package:codexhub01/services/call_service.dart';

class ChatScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUserName;

  const ChatScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final MessageService service = MessageService();
  final CallService callService = CallService();
  final TextEditingController messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> messages = [];
  StreamSubscription? _messageSub;

 @override
void initState() {
  super.initState();

  // 1️⃣ Listen to real-time messages sa conversation
  _messageSub = service.messageStream(widget.otherUserId).listen((newMsgs) {
    if (!mounted) return;

    bool updated = false;

    for (var msg in newMsgs) {
      // Iwasan ang duplicates
      if (!messages.any((m) => m['id'] == msg['id'])) {
        messages.add(msg);
        updated = true;
      }
    }

    if (updated) {
      setState(() {});       // UI updates agad
      _scrollToBottom();     // auto scroll sa latest
    }
  });
}

/// Send a message with instant local echo
Future<void> _sendMessage() async {
  final text = messageController.text.trim();
  if (text.isEmpty) return;

  final currentUserId = service.currentUserId;

  // 1️⃣ Local echo: temporary message para makita agad sa UI
  final localMsg = {
    'id': DateTime.now().millisecondsSinceEpoch, // temporary ID
    'sender_id': currentUserId,
    'receiver_id': widget.otherUserId,
    'message': text,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  };

  setState(() {
    messages.add(localMsg);
  });
  _scrollToBottom();

  messageController.clear();

  // 2️⃣ Send sa Supabase
  try {
    await service.sendMessage(widget.otherUserId, text);
    // Real-time stream ng Supabase ang magpapatunay at magre-replace ng temp message kung kailangan
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to send message: $e')),
    );
  }
}
  /// Start an audio or video call
  Future<void> _startCall(String type) async {
    try {
      await callService.startCall(widget.otherUserId, type);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Calling ${widget.otherUserName} ($type)...')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start $type call: $e')),
      );
    }
  }

  /// Scroll to bottom of chat
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 50,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Format timestamp
  String _formatTime(String? timestamp) {
    if (timestamp == null) return '';
    final dateTime = DateTime.tryParse(timestamp)?.toLocal();
    if (dateTime == null) return '';
    final hour = dateTime.hour % 12 == 0 ? 12 : dateTime.hour % 12;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final ampm = dateTime.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = service.currentUserId;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final backgroundColor = isDark ? const Color(0xFF121212) : Colors.white;
    final bubbleColorMe = isDark ? Colors.indigoAccent.shade400 : Colors.indigo;
    final bubbleColorOther = isDark ? Colors.grey.shade800 : Colors.grey[300];
    final textColorMe = Colors.white;
    final textColorOther = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(widget.otherUserName),
        backgroundColor: isDark ? Colors.indigo.shade700 : Colors.indigo,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            tooltip: "Audio Call",
            onPressed: () => _startCall('audio'),
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: "Video Call",
            onPressed: () => _startCall('video'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                final isMe = msg['sender_id'].toString() == currentUserId;
                final messageText = msg['message'] ?? '';
                final createdAt = msg['created_at'] ?? '';

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isMe ? bubbleColorMe : bubbleColorOther,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isMe ? 'You' : widget.otherUserName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isMe ? textColorMe : textColorOther,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          messageText,
                          style: TextStyle(
                            color: isMe ? textColorMe : textColorOther,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatTime(createdAt),
                          style: TextStyle(
                            fontSize: 10,
                            color: isMe ? Colors.white70 : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade900 : Colors.grey[100],
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.grey.shade800 : Colors.grey[300]!,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white70 : Colors.grey,
                      ),
                      filled: true,
                      fillColor: isDark ? Colors.grey.shade800 : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor:
                      isDark ? Colors.indigoAccent.shade400 : Colors.indigo,
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
