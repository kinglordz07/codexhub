import 'dart:async';
import 'package:flutter/material.dart';
import 'package:codexhub01/services/messageservice.dart';
import 'package:codexhub01/services/call_services.dart';
import 'package:codexhub01/parts/call_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MenteeMessagingScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUserName;

  const MenteeMessagingScreen({
    super.key,
    required this.otherUserId,
    required this.otherUserName,
  });

  @override
  State<MenteeMessagingScreen> createState() => _MenteeMessagingScreenState();
}

class _MenteeMessagingScreenState extends State<MenteeMessagingScreen> {
  final MessageService service = MessageService();
  final CallService _callService = CallService();

  final TextEditingController messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> messages = [];
  StreamSubscription? _messageSub;
  StreamSubscription? _incomingCallSub;

  bool isDialogOpen = false;
  bool isSending = false;
  final Set<String> _showingDialogs = {};
  // REMOVED: _currentCallID since it's unused

  @override
  void initState() {
    super.initState();
    _listenMessages();
    _listenIncomingCalls();
  }

  void _listenMessages() {
    _messageSub?.cancel();
    _messageSub = service.messageStream(widget.otherUserId).listen((newMsgs) {
      if (mounted) {
        setState(() => messages = newMsgs);
        _scrollToBottom();
      }
    });
  }

  void _listenIncomingCalls() {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) return;

    _incomingCallSub?.cancel();
    _incomingCallSub = Supabase.instance.client
        .from('calls')
        .stream(primaryKey: ['id'])
        .listen((events) {
      if (!mounted) return;
      
      final ringingCalls = events.where((call) {
        return call['receiver_id'] == currentUser.id && 
               call['status'] == 'ringing';
      }).toList();

      for (final call in ringingCalls) {
        final callID = call['id'].toString();
        if (!_showingDialogs.contains(callID)) {
          _showingDialogs.add(callID);
          _showIncomingCallDialog(call);
        }
      }
    });
  }

  // In the _showIncomingCallDialog method, update the decline part:
Future<void> _showIncomingCallDialog(Map<String, dynamic> call) async {
  final callID = call['id'].toString();
  final callerName = call['caller_name'] ?? 'Unknown';
  final callType = call['call_type'] ?? 'audio';

  if (isDialogOpen || !mounted) {
    _showingDialogs.remove(callID);
    return;
  }

  isDialogOpen = true;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text("Incoming ${callType == 'video' ? 'Video' : 'Audio'} Call"),
      content: Text("$callerName is calling you"),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text("Decline", style: TextStyle(color: Colors.red)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text("Accept", style: TextStyle(color: Colors.green)),
        ),
      ],
    ),
  );

  isDialogOpen = false;
  _showingDialogs.remove(callID);

  if (!mounted) return;

  if (result == true) {
    await _handleCallAcceptance(call);
  } else {
    // FIXED: Properly handle call decline
    try {
      await _callService.declineCall(callID);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Call declined")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to decline call: $e")),
        );
      }
    }
  }
}

  Future<void> _handleCallAcceptance(Map<String, dynamic> call) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null || !mounted) return;

    final callID = call['id'].toString();
    
    try {
      // Accept call first
      await _callService.acceptCall(callID);
      
      // Navigate immediately without waiting for stream updates
      if (!mounted) return;
      
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallPage(
            callID: callID,
            userID: currentUser.id,
            userName: currentUser.userMetadata?['username'] ?? 
                     currentUser.email ?? 'User',
            callType: call['call_type'] ?? 'audio',
            // REMOVED: isCaller parameter since it's not defined in CallPage
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to accept call: $e")),
        );
      }
    }
  }

  Future<void> _startCall(String type) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null || !mounted) return;

    try {
      final callID = await _callService.startCall(
        callerId: currentUser.id,
        receiverId: widget.otherUserId,
        callType: type,
      );

      if (!mounted) return;

      // Navigate directly to call page as caller
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CallPage(
            callID: callID,
            userID: currentUser.id,
            userName: currentUser.userMetadata?['username'] ?? 
                     currentUser.email ?? 'User',
            callType: type,
            // REMOVED: isCaller parameter since it's not defined in CallPage
          ),
        ),
      );

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to start call: $e")),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && mounted) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty || isSending) return;

    setState(() => isSending = true);
    messageController.clear();

    try {
      await service.sendMessage(widget.otherUserId, text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isSending = false);
    }
  }

  @override
  void dispose() {
    _messageSub?.cancel();
    _incomingCallSub?.cancel();
    _callService.dispose();
    messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = service.currentUserId;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screen = MediaQuery.of(context).size;
    // USED: isSmall variable is now being used
    final isSmall = screen.width < 400;

    final bubbleColorMe = isDark ? Colors.indigoAccent.shade400 : Colors.indigo;
    final bubbleColorOther = isDark ? Colors.grey.shade800 : Colors.grey[300]!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.otherUserName,
          style: TextStyle(fontSize: isSmall ? 16 : 18),
        ),
        backgroundColor: isDark ? Colors.indigo.shade700 : Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.call),
            onPressed: () => _startCall('audio'),
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => _startCall('video'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isSmall ? 8 : 12,
                vertical: isSmall ? 4 : 8,
              ),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final isMe = msg['sender_id'] == currentUserId;
                  
                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: EdgeInsets.symmetric(
                        vertical: isSmall ? 2 : 4, 
                        horizontal: isSmall ? 2 : 4,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: isSmall ? 12 : 16,
                        vertical: isSmall ? 8 : 12,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: isSmall ? screen.width * 0.8 : screen.width * 0.7,
                      ),
                      decoration: BoxDecoration(
                        color: isMe ? bubbleColorMe : bubbleColorOther,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg['message'] ?? '',
                            style: TextStyle(
                              fontSize: isSmall ? 14 : 16,
                              color: isMe ? Colors.white : 
                                    (isDark ? Colors.white : Colors.black87),
                            ),
                          ),
                          if (msg['status'] == 'sending') ...[
                            const SizedBox(height: 4),
                            Text(
                              'Sending...',
                              style: TextStyle(
                                fontSize: isSmall ? 10 : 12,
                                color: isMe ? Colors.white70 : 
                                      (isDark ? Colors.white70 : Colors.black54),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(isSmall ? 8 : 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      hintStyle: TextStyle(
                        fontSize: isSmall ? 14 : 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: isSmall ? 16 : 20,
                        vertical: isSmall ? 12 : 16,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: isSmall ? 20 : 24,
                  backgroundColor: isDark ? Colors.indigoAccent.shade400 : Colors.indigo,
                  child: IconButton(
                    icon: Icon(
                      Icons.send,
                      size: isSmall ? 18 : 22,
                      color: Colors.white,
                    ),
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