import 'package:chat/components/chat_bubble.dart';
import 'package:chat/components/my_textfield.dart';
import 'package:chat/services/auth/auth_service.dart';
import 'package:chat/services/chat/chat_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';

class ChatPage extends StatefulWidget {
  final String receiverEmail;
  final String receiverID;

  const ChatPage({
    super.key,
    required this.receiverEmail,
    required this.receiverID,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  // Text controller & focus node
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // Chat & auth services
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();

  @override
  void dispose() {
    _messageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Send message
  void sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    // Clear controller immediately for snappy UX
    _messageController.clear();

    try {
      await _chatService.sendMessage(widget.receiverID, text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.receiverEmail),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.grey,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Display all messages
            Expanded(
              child: _buildMessageList(),
            ),

            // User input bar
            _buildUserInput(),
          ],
        ),
      ),
    );
  }

  // Build message list
  Widget _buildMessageList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _chatService.getMessages(widget.receiverID),
      builder: (context, snapshot) {
        // Error
        if (snapshot.hasError) {
          return const Center(child: Text("Error loading messages"));
        }

        // Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const Center(
            child: Text("No messages yet. Say hello!"),
          );
        }

        // Display newest messages at bottom using reverse: true
        return ListView.builder(
          reverse: true,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            return _buildMessageItem(docs[index]);
          },
        );
      },
    );
  }

  // Build individual message item
  Widget _buildMessageItem(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return const SizedBox.shrink();

    final isCurrentUser =
        data['senderID'] == _authService.getCurrentUser()?.uid;
    final alignment =
        isCurrentUser ? Alignment.centerRight : Alignment.centerLeft;

    return Container(
      alignment: alignment,
      child: ChatBubble(
        message: data['message'] ?? '',
        isCurrentUser: isCurrentUser,
      ),
    );
  }

  // Build user input row
  Widget _buildUserInput() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 25.0, top: 10.0),
      child: Row(
        children: [
          // Textfield takes up remaining space
          Expanded(
            child: MyTextField(
              hintText: "Type a message",
              obscureText: false,
              controller: _messageController,
              focusNode: _focusNode,
            ),
          ),

          // Send button
          Container(
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
            margin: const EdgeInsets.only(right: 25.0),
            child: IconButton(
              onPressed: sendMessage,
              icon: const Icon(
                Icons.arrow_upward,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
