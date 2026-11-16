import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    this.functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions? functions;

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

  Future<void> deleteAccount(String password) async {
    final user = _auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw StateError('Please sign in again.');
    }
    if (password.isEmpty) throw ArgumentError('Please enter your password.');

    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
    await user.getIdToken(true);
    await (functions ?? FirebaseFunctions.instance)
        .httpsCallable(
          'deleteAccount',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
        )
        .call();
    await _auth.signOut();
  }

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

  static String getErrorMessage(Object error) {
    if (error is StateError) return error.message;
    if (error is ArgumentError) return error.message.toString();
    if (error is FirebaseFunctionsException) {
      return switch (error.code) {
        'not-found' || 'unimplemented' =>
          'Account deletion is currently unavailable. Please try again later.',
        'unauthenticated' ||
        'failed-precondition' => 'Please confirm your password and try again.',
        _ => 'Account deletion could not be completed. Please try again.',
      };
    }
    if (error is! FirebaseAuthException) {
      if (error is FirebaseException && error.code == 'permission-denied') {
        return 'This action is not available for this account or conversation.';
      }
      return 'Could not complete this action. Please try again.';
    }
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
