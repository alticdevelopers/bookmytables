// Book My Tables — Complete Flutter App (Part 1)

// ignore_for_file: use_build_context_synchronously
import "dart:async";
import "dart:convert";
import "package:flutter/foundation.dart";
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:purchases_flutter/purchases_flutter.dart";

// Firebase
import "package:firebase_core/firebase_core.dart";
import "package:firebase_auth/firebase_auth.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:cloud_firestore/cloud_firestore.dart";

// Utilities / Sub-pages
import "firebase_options.dart";
import "register_token.dart";
import "revenuecat_init.dart";
import "notifications.dart";
import "auth_service.dart";
import "menu_offers_page.dart";
import "tables_page.dart";
import "public_booking_page.dart";

// ===== Scroll behavior fix =====
class AppScrollBehavior extends MaterialScrollBehavior {
@override
Set<PointerDeviceKind> get dragDevices => {
PointerDeviceKind.touch,
PointerDeviceKind.mouse,
PointerDeviceKind.trackpad,
};
}

// ===== Global navigator key =====
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
WidgetsFlutterBinding.ensureInitialized();
await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

// Background push handler
FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);

await initRevenueCat(); // RevenueCat setup

runApp(const BookMyTablesApp());
}

class BookMyTablesApp extends StatelessWidget {
const BookMyTablesApp({super.key});

@override
Widget build(BuildContext context) {
final base = ThemeData(
useMaterial3: true,
colorScheme: ColorScheme.fromSeed(
seedColor: const Color(0xFF7B1E12), // deep red
brightness: Brightness.light,
),
scaffoldBackgroundColor: const Color(0xFFFFF8F3),
fontFamily: "Roboto",
);

    return MaterialApp(
      title: "Book My Tables",
      theme: base.copyWith(
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF7B1E12),
          foregroundColor: Colors.white,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF7B1E12),
            foregroundColor: Colors.white,
          ),
        ),
      ),
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scrollBehavior: AppScrollBehavior(),
      home: const Bootstrapper(),
    );
}
}