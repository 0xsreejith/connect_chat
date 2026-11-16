import 'package:chat/services/auth/auth_service.dart';
import 'package:chat/components/my_button.dart';
import 'package:chat/components/my_textfield.dart';
import 'package:chat/pages/register_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

class LoginPage extends StatelessWidget {
  final void Function()? onTap;

  LoginPage({
    super.key,
    this.onTap,
  });

  // Text controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // Login method
  void login(BuildContext context) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => const AlertDialog(
          title: Text("Please fill in both email and password"),
        ),
      );
      return;
    }

    final authService = AuthService();

    try {
      await authService.signInWithEmailPassword(email, password);
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException [${e.code}]: ${e.message}');
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(AuthService.getErrorMessage(e)),
        ),
      );
    } catch (e) {
      debugPrint('Login error: $e');
      if (!context.mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(e.toString()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo / App Icon
                Icon(
                  Icons.message,
                  size: 60,
                  color: colorScheme.primary,
                ),

                const SizedBox(height: 50),

                // Welcome message
                Text(
                  "Welcome back, you've been missed!",
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 25),

                // Email textfield
                MyTextField(
                  hintText: "Email",
                  obscureText: false,
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                ),

                const SizedBox(height: 10),

                // Password textfield
                MyTextField(
                  hintText: "Password",
                  obscureText: true,
                  controller: _passwordController,
                ),

                const SizedBox(height: 25),

                // Login button
                MyButton(
                  text: "Login",
                  onTap: () => login(context),
                ),

                const SizedBox(height: 50),

                // Register prompt
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Not a member? ",
                      style: TextStyle(color: colorScheme.primary),
                    ),
                    GestureDetector(
                      onTap: onTap ??
                          () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => RegisterPage(),
                              ),
                            );
                          },
                      child: Text(
                        "Register now",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
