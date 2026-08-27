import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationsService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    await _messaging.requestPermission(alert: true, badge: true, sound: true);

    final token = await _messaging.getToken();

    if (token != null) {
      print('FCM Token: $token');
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('Notification received: ${message.notification?.title}');
      print('Notification body: ${message.notification?.body}');
    });
  }

  static Future<void> saveToken(String uid) async {
    try {
      final token = await _messaging.getToken();

      if (token == null) return;

      await FirebaseDatabase.instance.ref('users/$uid/fcmToken').set(token);

      print('FCM token saved successfully');
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }
}
