// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:codexhub01/services/messageservice.dart';
import 'package:codexhub01/services/call_services.dart';
import 'package:codexhub01/parts/call_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final CallService _callService = CallService();

  final TextEditingController messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> messages = [];
  StreamSubscription? _messageSub;
  StreamSubscription? _callStatusSub;
  StreamSubscription? _incomingCallSub;

  bool isDialogOpen = false;
  bool isSending = false;
  final Set<String> activeCallIDs = {};

  @override
  void initState() {
    super.initState();
    _listenMessages();
    _listenIncomingCalls();
  }

  // 🟢 Real-time listener for chat messages
  void _listenMessages() {
    _messageSub?.cancel(); // ensure old listeners are removed first
    _messageSub = service.messageStream(widget.otherUserId).listen((newMsgs) {
      setState(() {
        messages = newMsgs;
      });
      _scrollToBottom();
    });
  }

  // 🟢 Real-time incoming call listener
  void _listenIncomingCalls() {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;
    final currentUserId = currentUser.id;

    _incomingCallSub = Supabase.instance.client
        .from('calls')
        .stream(primaryKey: ['id'])
        .eq('receiver_id', currentUserId)
        .listen((events) async {
      if (events.isEmpty) return;

      for (final call in events) {
        final callID = call['id']?.toString() ?? '';
        final status = call['status'] ?? '';

        if (status == 'ringing' && !activeCallIDs.contains(callID) && mounted) {
          activeCallIDs.add(callID);
          await _showIncomingCallDialog(call);
          activeCallIDs.remove(callID);
        }
      }
    });
  }

  // 🟢 Handles call accept/decline dialogs
  Future<void> _showIncomingCallDialog(Map<String, dynamic> call) async {
    if (isDialogOpen) return;
    isDialogOpen = true;

    try {
      final callerName = call['caller_name'] ?? 'Unknown';
      final callType = call['call_type'] ?? 'audio';

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: Text("Incoming $callType call"),
            content: Text("$callerName is calling you"),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _callService.declineCall(call);
                },
                child: const Text("Decline"),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  final currentUser = Supabase.instance.client.auth.currentUser;
                  if (!mounted || currentUser == null) return;

                  await _callService.acceptCall(call);

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CallPage(
                        callID: call['id'],
                        userID: currentUser.id,
                        userName: currentUser.userMetadata?['username'] ??
                            currentUser.email ??
                            'User',
                        callType: callType,
                      ),
                    ),
                  );
                },
                child: const Text("Accept"),
              ),
            ],
          );
        },
      );
    } finally {
      if (mounted) isDialogOpen = false;
    }
  }

  // 🟢 Send message logic (with indicator)
  Future<void> _sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty || isSending) return;

    setState(() => isSending = true);

    final currentUserId = service.currentUserId;
    final localMsg = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'sender_id': currentUserId,
      'receiver_id': widget.otherUserId,
      'message': text,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'status': 'sending',
    };

    setState(() {
      messages.add(localMsg);
    });
    _scrollToBottom();
    messageController.clear();

    try {
      await service.sendMessage(widget.otherUserId, text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  // 🟢 Call setup logic
  Future<void> _startCall(String type) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    final currentUserId = currentUser.id;
    final currentUserName =
        currentUser.userMetadata?['username'] ?? currentUser.email ?? 'User';

    try {
      final callID = await _callService.startCall(
        callerId: currentUserId,
        receiverId: widget.otherUserId,
        callType: type,
      );

      if (callID.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("Failed to create call")));
        return;
      }

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Text("Calling ${widget.otherUserName}..."),
        ),
      );

      _callStatusSub?.cancel();

      _callStatusSub = _callService.listenCallStatus(callID).listen((events) async {
        if (events.isEmpty) return;
        final call = events.first;
        final status = call['status'];

        if (status == 'accepted' && mounted) {
          Navigator.of(context).pop();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CallPage(
                callID: callID,
                userID: currentUserId,
                userName: currentUserName,
                callType: type,
              ),
            ),
          );
        } else if (status == 'declined' && mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("Call declined")));
        } else if (status == 'ended' && mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text("Call ended")));
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Failed to start call: $e")));
      }
    }
  }

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
  void dispose() {
    _messageSub?.cancel();
    _callStatusSub?.cancel();
    _incomingCallSub?.cancel();
    messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final isVerySmallScreen = screenSize.width < 400;

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
        title: Text(
          widget.otherUserName,
          style: TextStyle(fontSize: isSmallScreen ? 18 : 20),
        ),
        backgroundColor: isDark ? Colors.indigo.shade700 : Colors.indigo,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            size: isSmallScreen ? 20 : 24,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!isVerySmallScreen)
            IconButton(
              icon: Icon(
                Icons.call,
                size: isSmallScreen ? 20 : 24,
              ),
              tooltip: "Audio Call",
              onPressed: () async => _startCall('audio'),
            ),
          IconButton(
            icon: Icon(
              Icons.videocam,
              size: isSmallScreen ? 20 : 24,
            ),
            tooltip: "Video Call",
            onPressed: () async => _startCall('video'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final isMe = msg['sender_id'].toString() == currentUserId;
                  final messageText = msg['message'] ?? '';
                  final createdAt = msg['created_at'] ?? '';

                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: screenSize.width * 0.75,
                      ),
                      margin: EdgeInsets.symmetric(
                        vertical: isSmallScreen ? 2 : 4,
                        horizontal: isSmallScreen ? 4 : 8,
                      ),
                      padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                      decoration: BoxDecoration(
                        color: isMe ? bubbleColorMe : bubbleColorOther,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!isVerySmallScreen)
                            Text(
                              isMe ? 'You' : widget.otherUserName,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: isSmallScreen ? 12 : 14,
                                color: isMe ? textColorMe : textColorOther,
                              ),
                            ),
                          if (!isVerySmallScreen) SizedBox(height: isSmallScreen ? 2 : 4),
                          Text(
                            messageText,
                            style: TextStyle(
                              fontSize: isSmallScreen ? 14 : 16,
                              color: isMe ? textColorMe : textColorOther,
                            ),
                          ),
                          SizedBox(height: isSmallScreen ? 1 : 2),
                          Text(
                            _formatTime(createdAt),
                            style: TextStyle(
                              fontSize: isSmallScreen ? 9 : 10,
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
              padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
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
                        fontSize: isSmallScreen ? 14 : 16,
                      ),
                      decoration: InputDecoration(
                        hintText: isSending ? "Sending..." : "Type a message...",
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white70 : Colors.grey,
                          fontSize: isSmallScreen ? 14 : 16,
                        ),
                        filled: true,
                        fillColor: isDark ? Colors.grey.shade800 : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: isSmallScreen ? 14 : 16,
                          vertical: isSmallScreen ? 12 : 14,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                      enabled: !isSending,
                    ),
                  ),
                  SizedBox(width: isSmallScreen ? 6 : 8),
                  CircleAvatar(
                    radius: isSmallScreen ? 20 : 24,
                    backgroundColor:
                        isDark ? Colors.indigoAccent.shade400 : Colors.indigo,
                    child: IconButton(
                      icon: Icon(
                        Icons.send,
                        color: Colors.white,
                        size: isSmallScreen ? 18 : 20,
                      ),
                      onPressed: isSending ? null : _sendMessage,
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