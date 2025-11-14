import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static bool _notificationsEnabled = true;
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static bool get areNotificationsEnabled => _notificationsEnabled;

  static Future<void> initializeWithPreference(bool enabled) async {
  _notificationsEnabled = enabled;
  await initialize(); 
}
  
  static Future<void> initialize() async {
    // Load preference from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    _notificationsEnabled = prefs.getBool('notificationsEnabled') ?? true;
    
    // Request runtime permission on Android 13+ (POST_NOTIFICATIONS)
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final status = await Permission.notification.status;
        if (status.isDenied) {
          await Permission.notification.request();
        }
      }
    } catch (e) {
      debugPrint('Notification permission error: $e');
    }

    const AndroidInitializationSettings androidInitializationSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosInitializationSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: androidInitializationSettings,
      iOS: iosInitializationSettings,
    );

    // Create notification channels
    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      const AndroidNotificationChannel defaultChannel = AndroidNotificationChannel(
        'default_channel',
        'General Notifications',
        description: 'Notifications for messages, friend requests, and sessions',
        importance: Importance.high,
      );

      const AndroidNotificationChannel callsChannel = AndroidNotificationChannel(
        'calls_channel',
        'Call Notifications',
        description: 'Notifications for audio and video calls',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
      );

      const AndroidNotificationChannel sessionsChannel = AndroidNotificationChannel(
        'sessions_channel',
        'Session Notifications',
        description: 'Notifications for session updates',
        importance: Importance.high,
      );

      await androidPlugin.createNotificationChannel(defaultChannel);
      await androidPlugin.createNotificationChannel(callsChannel);
      await androidPlugin.createNotificationChannel(sessionsChannel);
    }

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification taps - you can navigate to specific screens
        debugPrint('Notification tapped: ${response.payload}');
      },
    );
  }

  static Future<bool> shouldShowNotificationForUser(String? userId) async {
    if (userId == null) return _notificationsEnabled;
    
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('profiles_new')
          .select('notifications_enabled')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 3));
      
      return response?['notifications_enabled'] as bool? ?? _notificationsEnabled;
    } catch (e) {
      debugPrint('❌ Error checking user notification preference: $e');
      return _notificationsEnabled; 
    }
  }

  static Future<void> updateNotificationPreference(bool enabled) async {
    _notificationsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notificationsEnabled', enabled);
    debugPrint('🔔 Notification preference updated: $enabled');
  }

  static bool get areNotificationsAllowed => _notificationsEnabled;

  static bool shouldShowNotification() {
  return _notificationsEnabled;
}

  static Future<void> showFriendRequestNotification({
    required String fromUserName,
    String? payload,
  }) async {
    if (!shouldShowNotification()) {
      debugPrint('🔕 Notifications disabled - ignoring friend request from $fromUserName');
      return;
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'default_channel',
      'General Notifications',
      channelDescription: 'Notifications for messages, friend requests, and sessions',
      importance: Importance.high,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'New Friend Request',
      '$fromUserName wants to connect with you',
      details,
      payload: payload ?? 'friend_requests',
    );
  }

  // 🔔 MENTOR FRIEND REQUEST NOTIFICATION
  static Future<void> showMentorFriendRequestNotification({
    required String fromUserName,
    required String fromUserRole,
    String? payload,
  }) async {
    if (!shouldShowNotification()) {
      debugPrint('🔕 Notifications disabled - ignoring mentor friend request from $fromUserName');
      return;
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'default_channel',
      'General Notifications',
      channelDescription: 'Notifications for messages, friend requests, and sessions',
      importance: Importance.high,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'New Connection Request',
      '$fromUserName ($fromUserRole) wants to connect with you',
      details,
      payload: payload ?? 'mentor_friend_requests',
    );
  }

  // 🔔 MENTOR FRIEND REQUEST ACCEPTED NOTIFICATION
  static Future<void> showMentorFriendRequestAcceptedNotification({
    required String userName,
    String? payload,
  }) async {
    if (!_notificationsEnabled) return;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'default_channel',
      'General Notifications',
      channelDescription: 'Notifications for messages, friend requests, and sessions',
      importance: Importance.high,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'Connection Accepted!',
      '$userName accepted your connection request',
      details,
      payload: payload ?? 'mentor_friends',
    );
  }

  // 🔔 MESSAGE NOTIFICATION
  static Future<void> showMessageNotification({
    required String fromUserName,
    required String message,
    String? payload,
  }) async {
    if (!shouldShowNotification()) return;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'default_channel',
      'General Notifications',
      channelDescription: 'Notifications for messages, friend requests, and sessions',
      importance: Importance.high,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'New Message from $fromUserName',
      message.length > 50 ? '${message.substring(0, 50)}...' : message,
      details,
      payload: payload ?? 'messages',
    );
  }

  // 🔔 SESSION STATUS NOTIFICATION (Mentor Accept/Decline)
  static Future<void> showSessionStatusNotification({
    required String mentorName,
    required String status, // 'accepted' or 'declined'
    required String sessionType,
    String? payload,
  }) async {
    if (!shouldShowNotification()) return;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'sessions_channel',
      'Session Notifications',
      channelDescription: 'Notifications for session updates',
      importance: Importance.high,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    String title = 'Session $status';
    String body = 'Your $sessionType session with $mentorName has been $status';

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      details,
      payload: payload ?? 'sessions',
    );
  }

  static Future<void> showIncomingCallNotification({
    required int id,
    required String callerName,
    required String callType, 
    String? payload,
  }) async {
    if (!shouldShowNotification()) {
      debugPrint('🔕 Notifications disabled - ignoring $callType call from $callerName');
      return;
    }

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'calls_channel',
      'Call Notifications',
      channelDescription: 'Notifications for audio and video calls',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      id,
      'Incoming ${callType == 'audio' ? 'Audio' : 'Video'} Call',
      '$callerName is calling you',
      details,
      payload: payload ?? 'call_$callType',
    );
    
    debugPrint('📞 Incoming call notification shown for $callerName');
  }

  static Future<void> showMissedCallNotification({
    required String callerName,
    required String callType,
    String? payload,
  }) async {
    if (!shouldShowNotification()) return;

    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'calls_channel',
      'Call Notifications',
      channelDescription: 'Notifications for audio and video calls',
      importance: Importance.high,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      'Missed ${callType == 'audio' ? 'Audio' : 'Video'} Call',
      '$callerName called you',
      details,
      payload: payload ?? 'missed_call',
    );
  }

  static Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!shouldShowNotification()) return;

    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'default_channel',
      'General Notifications', 
      channelDescription: 'Notifications for messages, friend requests, and sessions',
      importance: Importance.high,
      priority: Priority.high,
    );

    const DarwinNotificationDetails iosNotificationDetails =
        DarwinNotificationDetails();

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
      iOS: iosNotificationDetails,
    );

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  static Future<bool> areSystemNotificationsEnabled() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final bool? result = await _notificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.areNotificationsEnabled();
      return result ?? false;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      // For iOS, you might want to check permission status differently
      return true; // Placeholder - implement proper iOS check if needed
    }
    return true;
  }

  static Future<void> cancelAll() async {
    await _notificationsPlugin.cancelAll();
  }

  static Future<void> cancel(int id) async {
    await _notificationsPlugin.cancel(id);
  }
}