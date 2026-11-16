import 'package:chat/services/auth/auth_service.dart';
import 'package:chat/services/chat/chat_service.dart';
import 'package:material_ui/material_ui.dart';

class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  final _chatService = ChatService();
  late final _users = _chatService.getBlockedUsers();
  final _unblocking = <String>{};

  Future<void> _unblock(String userId) async {
    setState(() => _unblocking.add(userId));
    try {
      await _chatService.unblockUser(userId);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AuthService.getErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _unblocking.remove(userId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Blocked users')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _users,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load blocked users.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snapshot.data!;
          if (users.isEmpty) {
            return const Center(child: Text('No blocked users.'));
          }
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final userId = user['userId'] as String;
              return ListTile(
                leading: const Icon(Icons.block),
                title: Text(user['email']?.toString() ?? 'Deleted account'),
                trailing: TextButton(
                  onPressed: _unblocking.contains(userId)
                      ? null
                      : () => _unblock(userId),
                  child: const Text('Unblock'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
