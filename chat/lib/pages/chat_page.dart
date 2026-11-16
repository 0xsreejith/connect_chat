import 'package:chat/components/chat_bubble.dart';
import 'package:chat/components/my_textfield.dart';
import 'package:chat/components/report_dialog.dart';
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

  // Scroll controller
  final ScrollController _scrollController = ScrollController();

  // Chat & auth services
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();
  late final Stream<List<Map<String, dynamic>>> _blockedUsers;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _messages;
  bool _sending = false;
  bool _changingBlock = false;

  @override
  void initState() {
    super.initState();
    _blockedUsers = _chatService.getBlockedUsers();
    _messages = _chatService.getMessages(widget.receiverID);

    // Add listener to focus node for keyboard adjustment
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        // Cause a delay so that the keyboard has time to show up
        // then the amount of remaining space will be calculated,
        // then scroll down
        Future.delayed(const Duration(milliseconds: 500), () => scrollDown());
      }
    });

    // Wait a bit for listview to be built, then scroll to bottom
    Future.delayed(const Duration(milliseconds: 500), () => scrollDown());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Scroll to bottom of chat
  void scrollDown() {
    if (mounted && _scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(seconds: 1),
        curve: Curves.fastOutSlowIn,
      );
    }
  }

  // Send message
  Future<void> sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);

    try {
      await _chatService.sendMessage(widget.receiverID, text);
      if (!mounted) return;
      if (_messageController.text.trim() == text) _messageController.clear();
      scrollDown();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showError(Object error) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AuthService.getErrorMessage(error))),
      );
    }
  }

  Future<void> _changeBlock(bool block) async {
    if (block) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Block user?'),
          content: Text(
            'New messages between you and ${widget.receiverEmail} will be blocked. You can unblock them in Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _changingBlock = true);
    try {
      if (block) {
        await _chatService.blockUser(widget.receiverID, widget.receiverEmail);
      } else {
        await _chatService.unblockUser(widget.receiverID);
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _changingBlock = false);
    }
  }

  Future<void> _report({String? messageId}) async {
    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReportDialog(
        userId: widget.receiverID,
        chatService: _chatService,
        messageId: messageId,
      ),
    );
    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Report submitted.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _blockedUsers,
      builder: (context, snapshot) {
        final blocked =
            snapshot.data?.any((user) => user['userId'] == widget.receiverID) ??
            false;
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBar(
            title: Text(widget.receiverEmail),
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.grey,
            elevation: 0,
            actions: [
              PopupMenuButton<String>(
                enabled:
                    snapshot.hasData && !snapshot.hasError && !_changingBlock,
                onSelected: (value) {
                  if (value == 'report') {
                    _report();
                  } else {
                    _changeBlock(!blocked);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'block',
                    child: Text(blocked ? 'Unblock user' : 'Block user'),
                  ),
                  const PopupMenuItem(
                    value: 'report',
                    child: Text('Report user'),
                  ),
                ],
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // Display all messages
                Expanded(child: _buildMessageList()),

                // User input bar
                if (snapshot.hasError)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Unable to check blocked users. Reopen this chat to retry.',
                    ),
                  )
                else if (!snapshot.hasData)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  )
                else if (blocked)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        const Text('You blocked this user.'),
                        TextButton(
                          onPressed: _changingBlock
                              ? null
                              : () => _changeBlock(false),
                          child: const Text('Unblock'),
                        ),
                      ],
                    ),
                  )
                else
                  _buildUserInput(),
              ],
            ),
          ),
        );
      },
    );
  }

  // Build message list
  Widget _buildMessageList() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _messages,
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
          return const Center(child: Text("No messages yet. Say hello!"));
        }

        // Reverse so oldest messages are at the top, newest at the bottom
        final messages = docs.reversed.toList();

        return ListView.builder(
          controller: _scrollController,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            return _buildMessageItem(messages[index]);
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
    final alignment = isCurrentUser
        ? Alignment.centerRight
        : Alignment.centerLeft;

    return Container(
      alignment: alignment,
      child: GestureDetector(
        onLongPress: isCurrentUser ? null : () => _report(messageId: doc.id),
        child: ChatBubble(
          message: data['message'] ?? '',
          isCurrentUser: isCurrentUser,
        ),
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
              onPressed: _sending ? null : sendMessage,
              icon: const Icon(Icons.arrow_upward, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
