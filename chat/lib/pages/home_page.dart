import 'package:chat/components/my_drawer.dart';
import 'package:chat/components/user_tile.dart';
import 'package:chat/pages/chat_page.dart';
import 'package:chat/services/auth/auth_service.dart';
import 'package:chat/services/chat/chat_service.dart';
import 'package:material_ui/material_ui.dart';

class HomePage extends StatelessWidget {
  HomePage({super.key});

  // Chat & Auth services
  final ChatService _chatService = ChatService();
  final AuthService _authService = AuthService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text("Home"),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.grey,
        elevation: 0,
      ),
      drawer: const MyDrawer(),
      body: _buildUserList(),
    );
  }

  // Build a list of users except for the current logged-in user
  Widget _buildUserList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _chatService.getUserStream(),
      builder: (context, snapshot) {
        // Error
        if (snapshot.hasError) {
          return const Center(
            child: Text("Error loading users"),
          );
        }

        // Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        final currentUserId = _authService.getCurrentUser()?.uid;
        final currentUserEmail = _authService.getCurrentUser()?.email;

        // Filter out current logged in user
        final otherUsers = (snapshot.data ?? []).where((user) {
          final uid = user['uid'];
          final email = user['email'];
          return uid != currentUserId && email != currentUserEmail;
        }).toList();

        if (otherUsers.isEmpty) {
          return const Center(
            child: Text("No other users found"),
          );
        }

        // Return user list
        return ListView.builder(
          itemCount: otherUsers.length,
          itemBuilder: (context, index) {
            return _buildUserListItem(otherUsers[index], context);
          },
        );
      },
    );
  }

  // Build individual list tile for user
  Widget _buildUserListItem(
    Map<String, dynamic> userData,
    BuildContext context,
  ) {
    return UserTile(
      text: userData["email"]?.toString() ?? "Unknown",
      onTap: () {
        // Navigate to ChatPage
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatPage(
              receiverEmail: userData["email"]?.toString() ?? "Unknown",
              receiverID: userData["uid"]?.toString() ?? "",
            ),
          ),
        );
      },
    );
  }
}
