import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  User? getCurrentUser() => _auth.currentUser;

  /// Emits the current user, then updates when the user signs in or out.
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<UserCredential> signInWithEmailPassword(
    String email,
    String password,
  ) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Creates an account and signs the new user in.
  Future<UserCredential> signUpWithEmailPassword(
    String email,
    String password,
  ) {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> signOut() => _auth.signOut();

  static String getErrorMessage(FirebaseAuthException error) {
    return switch (error.code) {
      'invalid-email' => 'Please enter a valid email address.',
      'user-disabled' =>
        'This account has been disabled. Please contact support.',
      'user-not-found' ||
      'wrong-password' ||
      'invalid-credential' ||
      'INVALID_LOGIN_CREDENTIALS' => 'The email or password is incorrect.',
      'email-already-in-use' => 'An account already exists with this email.',
      'weak-password' => 'Please choose a stronger password.',
      'operation-not-allowed' =>
        'Email and password sign-in is not enabled in Firebase Console.',
      'too-many-requests' => 'Too many attempts. Please try again later.',
      'network-request-failed' =>
        'Please check your internet connection and try again.',
      _ => error.message != null && error.message!.isNotEmpty
          ? error.message!
          : 'Authentication failed (${error.code}). Please try again.',
    };
  }
}
