import 'package:flutter/material.dart';

class CollaborationScreen extends StatefulWidget {
  const CollaborationScreen({super.key});

  @override
  State<CollaborationScreen> createState() => _CollaborationScreenState();
}

class _CollaborationScreenState extends State<CollaborationScreen> {
  final List<String> _chatMessages = [];
  final TextEditingController _messageController = TextEditingController();

  final List<String> _collaborators = [];

  bool isInCollaboration = false;
  String? currentGroup;

  void _sendMessage() {
    if (_messageController.text.isNotEmpty) {
      setState(() {
        _chatMessages.add("You: ${_messageController.text}");
      });
      _messageController.clear();
    }
  }

  void _startCollaboration() {
    setState(() {
      isInCollaboration = true;
      currentGroup = "New Collaboration";
      _chatMessages.clear();
      _collaborators.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You have started a collaboration session!'),
      ),
    );
  }

  void _leaveCollaboration() {
    setState(() {
      isInCollaboration = false;
      currentGroup = null;
      _chatMessages.clear();
      _collaborators.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You left the collaboration.')),
    );
  }

  void _inviteCollaborator(String user) {
    setState(() {
      _collaborators.add(user);
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$user has been invited!')));
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(currentGroup ?? 'Collaboration'),
        backgroundColor: Colors.indigo,
        automaticallyImplyLeading: !isInCollaboration,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child:
                isInCollaboration
                    ? ElevatedButton.icon(
                      onPressed: _leaveCollaboration,
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text(
                        'Leave Collaboration',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                    )
                    : ElevatedButton.icon(
                      onPressed: _startCollaboration,
                      icon: const Icon(Icons.add),
                      label: const Text(
                        'Start Collaboration',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
          ),

          if (isInCollaboration) ...[
            const Text(
              'Collaborators',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_collaborators.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text("No collaborators yet. Invite someone!"),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _collaborators.length,
                  itemBuilder:
                      (context, index) => ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(_collaborators[index]),
                      ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ElevatedButton.icon(
                onPressed:
                    () => _inviteCollaborator(
                      "New User ${_collaborators.length + 1}",
                    ),
                icon: const Icon(Icons.person_add),
                label: const Text("Invite Collaborator"),
              ),
            ),

            const Divider(),

            const Text(
              'Collaboration Chat',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _chatMessages.length,
                itemBuilder:
                    (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Text(
                        _chatMessages[index],
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: "Type a message...",
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _sendMessage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                    ),
                    child: const Text(
                      "Send",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
