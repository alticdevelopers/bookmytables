// ======================= BOOK MY TABLES =======================
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

// ==================== PUSH NOTIFICATIONS =====================
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (_) {} // Already initialized — safe to ignore
  debugPrint("🔔 Background FCM message: ${message.messageId}");
}


// ==================== GLOBAL NAVIGATOR =====================
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ==================== URL SLUG =============================
String? _extractPublicSlugFromUrl() {
  final uri = Uri.base;

  List<String> segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();

  if (segs.isEmpty && uri.fragment.isNotEmpty) {
    final frag = uri.fragment.startsWith('/')
        ? uri.fragment
        : '/${uri.fragment}';
    segs = Uri.parse(frag).pathSegments.where((s) => s.isNotEmpty).toList();
  }

  if (segs.isEmpty) return null;

  const reserved = {
    'login',
    'setup',
    'dashboard',
    'menu',
    'tables',
    'public',
    'assets'
  };

  final first = segs.first.toLowerCase();
  if (reserved.contains(first)) return null;

  return segs.first;
}

// ==================== MAIN ==============================
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ FIXED Firebase init — try/catch handles native-layer duplicate on Android
  FirebaseApp app;
  try {
    app = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    app = Firebase.app(); // Already initialized by native SDK — reuse it
  }

  // Web persistence
  if (kIsWeb) {
    await FirebaseAuth.instanceFor(app: app)
        .setPersistence(Persistence.LOCAL);
  }

  // Background messages
  FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);

  // RevenueCat
  await Purchases.configure(
    PurchasesConfiguration("public_sdk_key_here"),
  );

  // Notifications
  await initNotifications(
    onNavigate: (deepLink) {
      if (deepLink != null && deepLink.isNotEmpty) {
        navigatorKey.currentState?.pushNamed(deepLink);
      } else {
        navigatorKey.currentState?.pushNamed("/dashboard");
      }
    },
  );

  // Save FCM token to Firestore so Cloud Function can send notifications
  await saveFcmToken();

  // Refresh token whenever FCM issues a new one
  FirebaseMessaging.instance.onTokenRefresh.listen((_) => saveFcmToken());

  runApp(const BookMyTablesApp());
}

// ==================== APP ===============================
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

// ==================== BOOTSTRAPPER =======================
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
      final pathSlug = _extractPublicSlugFromUrl();
      if (pathSlug != null) {
        _go(PublicBookingPage(slug: pathSlug));
        return;
      }

      User? user;
      try {
        user = await FirebaseAuth.instance
            .authStateChanges()
            .first
            .timeout(const Duration(seconds: 3));
      } on TimeoutException {
        user = FirebaseAuth.instance.currentUser;
      }

      if (!mounted || _navigated) return;

      if (user == null) {
        _go(const LoginPage());
        return;
      }

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
      } catch (e) {
        debugPrint("Profile error: $e");
      }

      if (!mounted || _navigated) return;

      _go(const DashboardPage());
    } catch (e) {
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
          child: Text(_fatal!),
        ),
      );
    }

    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}