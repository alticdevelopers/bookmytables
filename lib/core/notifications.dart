import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Initializes and manages push notifications (FCM + Local)
/// for the Book My Tables app.

final FlutterLocalNotificationsPlugin _localNotifications =
FlutterLocalNotificationsPlugin();

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

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
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
          icon: '@mipmap/ic_launcher',
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