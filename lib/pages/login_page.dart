import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/theme.dart';
import '../core/app_state.dart';
import '../core/notifications.dart';
import 'setup_wizard_page.dart';
import 'dashboard_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  String? _error;

  /// Shared post-login routing: loads profile then goes to Dashboard or Setup.
  Future<void> _afterSignIn() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Load the user's slug from Firestore
    String? slug;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection("users")
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 5));
      slug = userDoc.data()?["slug"] as String?;
    } catch (_) {}

    if (!mounted) return;

    // New user — no slug yet → go to Setup
    if (slug == null || slug.isEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SetupWizardPage()),
      );
      return;
    }

    // Existing user — load profile into AppState then go to Dashboard
    AppState.instance.profileSlugOverride = slug;
    try {
      final p = await AppState.instance
          .loadProfileBySlug(slug)
          .timeout(const Duration(seconds: 5));
      if (p != null) {
        AppState.instance.profile
          ..businessName = p.businessName
          ..email = p.email
          ..phone = p.phone
          ..city = p.city
          ..state = p.state
          ..country = p.country
          ..restaurantType = p.restaurantType
          ..about = p.about;
      }
    } catch (_) {}

    // Save FCM token now that user is confirmed logged in
    await saveFcmToken();

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DashboardPage()),
    );
  }

  Future<void> _signInWithEmail() async {
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );
      if (!mounted) return;
      await _afterSignIn();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e.code, e.message));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signUpWithEmail() async {
    if (_email.text.trim().isEmpty || _password.text.trim().isEmpty) {
      setState(() => _error = "Please enter your email and password.");
      return;
    }
    if (_password.text.trim().length < 6) {
      setState(() => _error = "Password must be at least 6 characters.");
      return;
    }
    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );
      if (!mounted) return;
      // Brand new account — always go to Setup
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SetupWizardPage()),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e.code, e.message));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Google Sign-in using FirebaseAuth only (no google_sign_in plugin).
  Future<void> _signInWithGoogle() async {
    setState(() => _loading = true);
    try {
      final provider = GoogleAuthProvider();
      provider.setCustomParameters({'prompt': 'select_account'});

      if (kIsWeb) {
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        await FirebaseAuth.instance.signInWithProvider(provider);
      }

      if (!mounted) return;
      // Route correctly: new Google users → Setup, existing → Dashboard with profile
      await _afterSignIn();
    } catch (e) {
      setState(() => _error = e.toString().contains('INVALID_CERT_HASH') || e.toString().contains('sign_in_failed')
          ? "Google sign-in is not configured yet.\nPlease use email/password to create an account."
          : "Google sign-in failed. Try email/password instead.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyAuthError(String code, String? message) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email already has an account. Please Sign In instead.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password. Please try again.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return message ?? 'Something went wrong. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = buildAppTheme();
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            elevation: 8,
            margin: const EdgeInsets.all(24),
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Book My Tables",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF7B1E12),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: "Email",
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: "Password",
                      prefixIcon: Icon(Icons.lock),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_error != null)
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    )
                  else ...[
                    FilledButton(
                      onPressed: _signInWithEmail,
                      child: const Text("Sign In"),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _signUpWithEmail,
                      child: const Text("Create New Account"),
                    ),
                    const Divider(height: 32),
                    TextButton.icon(
                      onPressed: _signInWithGoogle,
                      icon: const Icon(Icons.login, color: Color(0xFF7B1E12)),
                      label: const Text(
                        "Continue with Google",
                        style: TextStyle(color: Color(0xFF7B1E12)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
      ), // SingleChildScrollView
    );
  }
}