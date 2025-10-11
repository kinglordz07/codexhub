import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PrivateChatScreen extends StatefulWidget {
  final String receiverId;
  final String receiverName;

  const PrivateChatScreen({
    super.key,
    required this.receiverId,
    required this.receiverName,
  });

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final SupabaseClient supabase = Supabase.instance.client;
  final TextEditingController _controller = TextEditingController();
  List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final response = await supabase
        .from('private_messages')
        .select()
        .or('sender_id.eq.${user.id},receiver_id.eq.${user.id}')
        .or(
          'sender_id.eq.${widget.receiverId},receiver_id.eq.${widget.receiverId}',
        )
        .order('created_at', ascending: true);

    setState(() => _messages = response);
  }

  Future<void> _sendMessage() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    final text = _controller.text.trim();
    if (text.isEmpty) return;

    await supabase.from('private_messages').insert({
      'sender_id': user.id,
      'receiver_id': widget.receiverId,
      'content': text,
    });

    _controller.clear();
    _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Chat with ${widget.receiverName}")),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg['sender_id'] == supabase.auth.currentUser?.id;
                return Align(
                  alignment:
                      isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.all(6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blue[200] : Colors.grey[300],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(msg['content']),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: "Type message...",
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
