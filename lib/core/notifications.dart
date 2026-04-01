import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../firebase_options.dart';

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

/// Android notification channel (same ID used in AndroidManifest.xml)
const AndroidNotificationChannel kBookingHighChannel = AndroidNotificationChannel(
  'book_my_tables_default_channel',
  'Book My Tables Notifications',
  description: 'Channel for new table booking notifications.',
  importance: Importance.high,
  playSound: true,
);

/// 🔹 Background FCM handler — must be top-level
@pragma("vm:entry-point")
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  debugPrint("🌙 [BG MESSAGE] data = ${message.data}, "
      "notif = ${message.notification?.title} | ${message.notification?.body}");

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint('❌ Firebase init failed in background handler: $e');
    return;
  }

  // If there is no notification payload (data-only message), show manually.
  // When a notification payload IS present, Android shows it automatically.
  final hasSystemNotification = message.notification != null;
  if (!hasSystemNotification) {
    try {
      await _showBookingHeadsUp(message.data);
    } catch (e) {
      debugPrint('❌ Error showing background notification: $e');
    }
  }
}

/// 🔹 Saves FCM token + email to Firestore under users/{uid}.
/// Call after every login and on token refresh.
Future<void> saveFcmToken() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;

    final email = FirebaseAuth.instance.currentUser?.email;

    await FirebaseFirestore.instance.collection("users").doc(uid).set({
      "fcmTokens": FieldValue.arrayUnion([token]),
      if (email != null) "email": email,
    }, SetOptions(merge: true));

    debugPrint("✅ FCM token saved for $uid");
  } catch (e) {
    debugPrint("⚠️ Could not save FCM token: $e");
  }
}

/// 🔹 Init notifications — call once from main() before runApp()
Future<void> initNotifications({
  required void Function(String? deepLink) onNavigate,
}) async {
  // ── Local notifications setup ──────────────────────────────────────────────
  const androidSettings =
      AndroidInitializationSettings('@drawable/ic_notification');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  await _localNotifications.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
    onDidReceiveNotificationResponse: (resp) async {
      final payload = resp.payload;
      if (payload == null) return;
      try {
        final map = jsonDecode(payload) as Map<String, dynamic>;
        final deepLink = map["deepLink"] as String?;
        onNavigate(deepLink?.isNotEmpty == true ? deepLink : "/dashboard");
      } catch (_) {
        onNavigate("/dashboard");
      }
    },
  );

  // Create the Android high-importance channel
  await _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(kBookingHighChannel);

  // ── Permissions ────────────────────────────────────────────────────────────
  await FirebaseMessaging.instance
      .requestPermission(alert: true, badge: true, sound: true);

  // Android 13+ runtime permission
  final androidImpl = _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  if (androidImpl != null) {
    await androidImpl.requestNotificationsPermission();
  }

  // iOS: show alerts/sounds even while app is in foreground
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: true,
    badge: true,
    sound: true,
  );

  // ── Foreground messages ────────────────────────────────────────────────────
  FirebaseMessaging.onMessage.listen((msg) async {
    debugPrint("📩 [onMessage] ${msg.notification?.title} | ${msg.notification?.body}");
    try {
      // Merge FCM notification fields into data map so _showBookingHeadsUp
      // can use title/body from either source.
      final merged = Map<String, dynamic>.from(msg.data);
      if (msg.notification?.title != null) {
        merged["title"] = msg.notification!.title!;
      }
      if (msg.notification?.body != null) {
        merged["body"] = msg.notification!.body!;
      }
      await _showBookingHeadsUp(merged);
    } catch (e) {
      debugPrint('❌ Error handling foreground message: $e');
    }
  });

  // ── Background tap (app was in background) ─────────────────────────────────
  FirebaseMessaging.onMessageOpenedApp.listen((msg) {
    debugPrint("📬 [onMessageOpenedApp] data = ${msg.data}");
    final deepLink = (msg.data["deep_link"] ?? "/dashboard").toString();
    onNavigate(deepLink);
  });

  // ── Terminated tap (app was fully closed) ──────────────────────────────────
  final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    final deepLink =
        (initialMessage.data["deep_link"] ?? "/dashboard").toString();
    onNavigate(deepLink);
  }
}

/// 🔹 Public helper called from dashboard when a new request arrives locally.
Future<void> showBookingNotification({
  required String customerName,
  required int guests,
  required String datetime,
}) async {
  await _showBookingHeadsUp({
    "title": "New Table Booking!",
    "body": "$customerName requested a table for $guests — $datetime",
    "deep_link": "/dashboard",
  });
}

/// 🔹 Shows a heads-up notification for a new booking.
Future<void> _showBookingHeadsUp(Map<String, dynamic> data) async {
  debugPrint("🔔 [_showBookingHeadsUp] data = $data");

  final bookingIdRaw = (data["bookingId"] ?? "").toString();
  final hasBookingId = bookingIdRaw.isNotEmpty;

  final title = (data["title"] ?? "New Table Booking!").toString();
  final body = (data["body"] ?? "A customer is waiting — Tap to view").toString();
  final deepLink = (data["deep_link"] ?? "/dashboard").toString();

  // Use a stable ID when we have a bookingId so duplicate notifications
  // replace the previous one instead of stacking.
  final notificationId = hasBookingId
      ? bookingIdRaw.hashCode
      : DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);

  final android = AndroidNotificationDetails(
    kBookingHighChannel.id,
    kBookingHighChannel.name,
    channelDescription: kBookingHighChannel.description,
    importance: Importance.high,
    priority: Priority.high,
    icon: "@drawable/ic_notification",
  );

  const ios = DarwinNotificationDetails(
    interruptionLevel: InterruptionLevel.timeSensitive,
    presentAlert: true,
    presentSound: true,
  );

  // Cancel the previous notification for this booking before re-showing.
  if (hasBookingId) {
    await _localNotifications.cancel(notificationId);
  }

  await _localNotifications.show(
    notificationId,
    title,
    body,
    NotificationDetails(android: android, iOS: ios),
    payload: jsonEncode({
      "bookingId": hasBookingId ? bookingIdRaw : "",
      "deepLink": deepLink,
    }),
  );
}
