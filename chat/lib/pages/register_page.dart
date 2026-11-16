import 'package:chat/auth/auth_service.dart';
import 'package:chat/components/my_button.dart';
import 'package:chat/components/my_textfield.dart';
import 'package:chat/pages/login_page.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

class RegisterPage extends StatelessWidget {
  final void Function()? onTap;

  RegisterPage({
    super.key,
    this.onTap,
  });

  // Text controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  // Register method
  void register(BuildContext context) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // Validate empty fields
    if (email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      showDialog(
        context: context,
        builder: (context) => const AlertDialog(
          title: Text("Please fill in all fields"),
        ),
      );
      return;
    }

    // Validate password match
    if (password != confirmPassword) {
      showDialog(
        context: context,
        builder: (context) => const AlertDialog(
          title: Text("Passwords do not match!"),
        ),
      );
      return;
    }

    final authService = AuthService();

    try {
      await authService.signUpWithEmailPassword(email, password);
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
      debugPrint('Register error: $e');
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
                  "Let's create an account for you",
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

                const SizedBox(height: 10),

                // Confirm password textfield
                MyTextField(
                  hintText: "Confirm password",
                  obscureText: true,
                  controller: _confirmPasswordController,
                ),

                const SizedBox(height: 25),

                // Register button
                MyButton(
                  text: "Register",
                  onTap: () => register(context),
                ),

                const SizedBox(height: 50),

                // Login prompt
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Already have an account? ",
                      style: TextStyle(color: colorScheme.primary),
                    ),
                    GestureDetector(
                      onTap: onTap ??
                          () {
                            if (Navigator.canPop(context)) {
                              Navigator.pop(context);
                            } else {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => LoginPage(),
                                ),
                              );
                            }
                          },
                      child: Text(
                        "Login now",
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
