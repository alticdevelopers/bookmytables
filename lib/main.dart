// ======================= BOOK MY TABLES =======================
// Main entry file: initializes Firebase, FCM, RevenueCat, and app routes.
// ==============================================================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // Web check
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/theme.dart';
import 'core/app_state.dart';
import 'firebase_options.dart';
import 'core/notifications.dart';

// Pages
import 'pages/login_page.dart';
import 'pages/setup_wizard_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/menu_offers_page.dart';
import 'pages/tables_page.dart';
import 'pages/public_booking_page.dart';

// ==================== PUSH NOTIFICATIONS (Background) =====================
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("🔔 Background FCM message: ${message.messageId}");
}

// ==================== GLOBAL NAVIGATOR =====================
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ==================== URL SLUG HELPER (PUBLIC) ============================
String? _extractPublicSlugFromUrl() {
  final uri = Uri.base;

  // Support /slug and #/slug (hash routing)
  List<String> segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty && uri.fragment.isNotEmpty) {
    final frag = uri.fragment.startsWith('/') ? uri.fragment : '/${uri.fragment}';
    segs = Uri.parse(frag).pathSegments.where((s) => s.isNotEmpty).toList();
  }
  if (segs.isEmpty) return null;

  const reserved = {
    'login', 'setup', 'dashboard', 'menu', 'tables', 'public', 'assets'
  };
  final first = segs.first.toLowerCase();
  if (reserved.contains(first)) return null;

  return segs.first; // treat the first segment as the restaurant slug
}

// ==================== APP ENTRY ==============================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1️⃣ Initialize Firebase
  final app = await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ✅ Web: ensure auth persistence so sign-in doesn’t break on refresh
  if (kIsWeb) {
    await FirebaseAuth.instanceFor(app: app)
        .setPersistence(Persistence.LOCAL); // or Persistence.SESSION
  }

  // 2️⃣ Set background message handler
  FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);

  // 3️⃣ Initialize RevenueCat (for subscriptions) — replace with your real key
  await Purchases.configure(
    PurchasesConfiguration("public_sdk_key_here"),
  );

  // 4️⃣ Initialize FCM + local notifications
  await initNotifications(
    onNavigate: (deepLink) {
      if (deepLink != null && deepLink.isNotEmpty) {
        navigatorKey.currentState?.pushNamed(deepLink);
      } else {
        navigatorKey.currentState?.pushNamed("/dashboard");
      }
    },
  );

  // 5️⃣ (Optional) Print device token for testing
  try {
    final token = await FirebaseMessaging.instance.getToken();
    debugPrint("🔥 FCM Token: $token");
  } catch (e) {
    debugPrint("⚠️ Failed to fetch FCM token: $e");
  }

  // 6️⃣ Run app
  runApp(const BookMyTablesApp());
}

// ==================== APP ROOT ===============================
class BookMyTablesApp extends StatelessWidget {
  const BookMyTablesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Book My Tables",
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      navigatorKey: navigatorKey,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
        },
      ),
      home: const Bootstrapper(),
      routes: {
        "/login": (_) => const LoginPage(),
        "/setup": (_) => const SetupWizardPage(),
        "/dashboard": (_) => const DashboardPage(),
        "/menu": (_) => const MenuOffersPage(),
        "/tables": (_) => const TablesPage(),
      },
    );
  }
}

// ==================== BOOTSTRAPPER (robust, slug-first) ===================
class Bootstrapper extends StatefulWidget {
  const Bootstrapper({super.key});
  @override
  State<Bootstrapper> createState() => _BootstrapperState();
}

class _BootstrapperState extends State<Bootstrapper> {
  String? _fatal;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      // 0) PUBLIC SLUG? → go straight to PublicBookingPage
      final pathSlug = _extractPublicSlugFromUrl();
      if (pathSlug != null) {
        _go(PublicBookingPage(slug: pathSlug));
        return;
      }

      // 1) Auth state (nullable + timeout handled via catch)
      User? user;
      try {
        user = await FirebaseAuth.instance
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 3));
      } on TimeoutException {
        user = FirebaseAuth.instance.currentUser; // fallback
      }

      if (!mounted || _navigated) return;

      if (user == null) {
        _go(const LoginPage());
        return;
      }

      // 2) user -> slug (nullable + timeout handled via catch)
      DocumentSnapshot<Map<String, dynamic>>? snap;
      try {
        snap = await FirebaseFirestore.instance
            .collection("users")
            .doc(user.uid)
            .get()
            .timeout(const Duration(seconds: 3));
      } on TimeoutException {
        snap = null;
      }

      final slug = snap?.data()?["slug"] as String?;
      if (!mounted || _navigated) return;

      if (slug == null || slug.isEmpty) {
        _go(const SetupWizardPage());
        return;
      }

      // 3) Load profile (non-blocking best-effort)
      AppState.instance.profileSlugOverride = slug;
      try {
        final p = await AppState.instance
            .loadProfileBySlug(slug)
            .timeout(const Duration(seconds: 3));
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
      } on TimeoutException {
        // ignore, proceed to dashboard
      } catch (e) {
        debugPrint("Profile load error: $e");
      }

      if (!mounted || _navigated) return;
      _go(const DashboardPage());
    } catch (e, st) {
      debugPrint("Bootstrap fatal: $e\n$st");
      if (!mounted) return;
      setState(() => _fatal = e.toString());
    }
  }

  void _go(Widget page) {
    if (_navigated) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_fatal != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Something went wrong",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SelectableText(_fatal!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => _go(const LoginPage()),
                  child: const Text("Go to Login"),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Visible loader (not a tiny dot)
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 44,
          height: 44,
          child: CircularProgressIndicator(strokeWidth: 4),
        ),
      ),
    );
  }
}