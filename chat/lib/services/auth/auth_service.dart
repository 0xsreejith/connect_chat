import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  User? getCurrentUser() => _auth.currentUser;

  /// Emits the current user, then updates when the user signs in or out.
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<UserCredential> signInWithEmailPassword(
    String email,
    String password,
  ) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _saveUserProfile(credential.user);
    return credential;
  }

  /// Creates an account and signs the new user in.
  Future<UserCredential> signUpWithEmailPassword(
    String email,
    String password,
  ) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await _saveUserProfile(credential.user);
    return credential;
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> _saveUserProfile(User? user) async {
    if (user == null) {
      throw StateError('Firebase did not return an authenticated user.');
    }
    try {
      await _firestore.collection('Users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName,
      }, SetOptions(merge: true));
    } on FirebaseException catch (error) {
      // Authentication has already succeeded; do not report an account failure.
      throw FirebaseException(
        plugin: error.plugin,
        code: error.code,
        message:
            'You are signed in, but your chat profile could not be saved. '
            'Please try signing in again.',
      );
    }
  }

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
      _ =>
        error.message != null && error.message!.isNotEmpty
            ? error.message!
            : 'Authentication failed (${error.code}). Please try again.',
    };
  }
}
