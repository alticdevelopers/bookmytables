import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Initializes and manages push notifications (FCM + Local)
/// for the Book My Tables app.

final FlutterLocalNotificationsPlugin _localNotifications =
FlutterLocalNotificationsPlugin();

/// Shows a local notification for a new booking request.
/// Call this whenever a new request arrives in the Firestore stream.
Future<void> showBookingNotification({
  required String customerName,
  required int guests,
  required String datetime,
}) async {
  await _localNotifications.show(
    DateTime.now().microsecond,
    "🍽️ New Table Booking!",
    "$customerName requested a table for $guests on $datetime",
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'book_my_tables_default_channel',
        'Book My Tables Notifications',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_notification',
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    ),
    payload: '/dashboard',
  );
}

/// Saves the current FCM token + email to Firestore under users/{uid}.
/// Call this after every login and on token refresh.
Future<void> saveFcmToken() async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return; // not logged in yet

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

Future<void> initNotifications({
  required void Function(String? deepLink) onNavigate,
}) async {
  final fcm = FirebaseMessaging.instance;

  // ✅ Request permission (iOS + Android 13+)
  await fcm.requestPermission(alert: true, badge: true, sound: true);

  // ✅ Create Android channel for local notifications
  const androidChannel = AndroidNotificationChannel(
    'book_my_tables_default_channel', // same ID as in AndroidManifest.xml
    'Book My Tables Notifications',
    description: 'Notification channel for new table bookings',
    importance: Importance.high,
  );

  const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
  const iosSettings = DarwinInitializationSettings();
  const initSettings =
  InitializationSettings(android: androidSettings, iOS: iosSettings);

  await _localNotifications.initialize(initSettings,
      onDidReceiveNotificationResponse: (response) {
        final deepLink = response.payload;
        if (deepLink != null && deepLink.isNotEmpty) {
          onNavigate(deepLink);
        }
      });

  await _localNotifications
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidChannel);

  // ✅ Foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    final title = message.notification?.title ?? "New Booking Request";
    final body = message.notification?.body ?? "You have a new table booking.";

    _localNotifications.show(
      DateTime.now().microsecond,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'book_my_tables_default_channel',
          'Book My Tables Notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
      payload: message.data['deep_link'],
    );
  });

  // ✅ App opened from background via push tap
  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    final deepLink = message.data['deep_link'];
    onNavigate(deepLink);
  });

  // ✅ Handle message when app is terminated
  final initialMessage = await fcm.getInitialMessage();
  if (initialMessage != null) {
    final deepLink = initialMessage.data['deep_link'];
    onNavigate(deepLink);
  }
}