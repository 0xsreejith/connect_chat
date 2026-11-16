import 'package:chat/components/report_dialog.dart';
import 'package:chat/services/auth/auth_service.dart';
import 'package:chat/services/chat/chat_service.dart';
import 'package:material_ui/material_ui.dart';

class ReportUserPage extends StatelessWidget {
  ReportUserPage({super.key});

  final _chatService = ChatService();
  final _authService = AuthService();

  Future<void> _report(BuildContext context, String userId) async {
    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ReportDialog(userId: userId, chatService: _chatService),
    );
    if (submitted == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Report submitted.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report a user')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _chatService.getUserStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Unable to load users.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snapshot.data!
              .where(
                (user) => user['uid'] != _authService.getCurrentUser()?.uid,
              )
              .toList();
          if (users.isEmpty) {
            return const Center(child: Text('No other users found.'));
          }
          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              return ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(user['email']?.toString() ?? 'Unknown user'),
                trailing: const Icon(Icons.flag_outlined),
                onTap: () => _report(context, user['uid'] as String),
              );
            },
          );
        },
      ),
    );
  }
}
