import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
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
  bool _obscurePassword = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Shared post-login routing: loads profile then goes to Dashboard or Setup.
  Future<void> _afterSignIn() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

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

    // New user — no slug yet → Setup
    if (slug == null || slug.isEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SetupWizardPage()),
      );
      return;
    }

    // Existing user — load profile into AppState then Dashboard
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

    await saveFcmToken();

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const DashboardPage()),
    );
  }

  Future<void> _signInWithEmail() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );

      if (!mounted) return;
      await _afterSignIn();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e.code, e.message));
    } catch (_) {
      setState(() => _error = "Unable to sign in right now. Please try again.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signUpWithEmail() async {
    FocusScope.of(context).unfocus();

    if (_email.text.trim().isEmpty || _password.text.trim().isEmpty) {
      setState(() => _error = "Please enter your email and password.");
      return;
    }

    if (_password.text.trim().length < 6) {
      setState(() => _error = "Password must be at least 6 characters.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text.trim(),
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SetupWizardPage()),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyAuthError(e.code, e.message));
    } catch (_) {
      setState(
            () => _error = "Unable to create account right now. Please try again.",
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider()
          ..setCustomParameters({'prompt': 'select_account'});
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        final account = await GoogleSignIn.instance.authenticate();
        final credential = GoogleAuthProvider.credential(
          idToken: account.authentication.idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }

      if (!mounted) return;
      await _afterSignIn();
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyGoogleError(e));
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) {
        setState(() => _error =
            "Google sign-in failed. Check Firebase Google Sign-In configuration.");
      }
    } catch (e) {
      setState(() => _error =
          "Google sign-in failed. Check Firebase Google Sign-In configuration.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    FocusScope.of(context).unfocus();

    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = "Enter your email first, then tap Forgot Password.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Password reset email sent to $email"),
        ),
      );
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _friendlyResetError(e.code, e.message));
    } catch (_) {
      setState(
            () => _error =
        "Could not send password reset email right now. Please try again.",
      );
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

  String _friendlyGoogleError(FirebaseAuthException e) {
    switch (e.code) {
      case 'popup-closed-by-user':
        return 'Google sign-in popup was closed before completion.';
      case 'popup-blocked':
        return 'Popup was blocked by the browser. Please allow popups and try again.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using another sign-in method.';
      case 'operation-not-allowed':
        return 'Google Sign-In is not enabled in Firebase Authentication.';
      case 'invalid-credential':
        return 'Invalid Google credentials. Please try again.';
      case 'web-context-cancelled':
        return 'Google sign-in was cancelled.';
      case 'web-context-already-presented':
        return 'Google sign-in is already open. Close the previous window and try again.';
      default:
        final raw = (e.message ?? '').toLowerCase();

        if (raw.contains('invalid_cert_hash')) {
          return 'Google sign-in SHA configuration is missing or incorrect in Firebase.';
        }
        if (raw.contains('sign_in_failed')) {
          return 'Google sign-in failed. Check Firebase Google provider, SHA keys, and OAuth setup.';
        }

        return e.message ??
            'Google sign-in failed. Check Firebase Google Sign-In configuration.';
    }
  }

  String _friendlyResetError(String code, String? message) {
    switch (code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
        return 'No account found for this email.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait and try again.';
      default:
        return message ?? 'Failed to send password reset email.';
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
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: "Password",
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                          ),
                        ),
                      ),
                    ),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _loading ? null : _resetPassword,
                        child: const Text("Forgot Password?"),
                      ),
                    ),

                    const SizedBox(height: 8),

                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),

                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      )
                    else ...[
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _signInWithEmail,
                          child: const Text("Sign In"),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _signUpWithEmail,
                          child: const Text("Create New Account"),
                        ),
                      ),
                      const Divider(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _signInWithGoogle,
                          icon: const Icon(
                            Icons.login,
                            color: Color(0xFF7B1E12),
                          ),
                          label: const Text(
                            "Continue with Google",
                            style: TextStyle(color: Color(0xFF7B1E12)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}