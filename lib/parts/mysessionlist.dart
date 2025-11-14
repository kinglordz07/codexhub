// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import '../services/sessionservice.dart';
import 'package:codexhub01/parts/schedulesession_screen.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class MySessionsScreen extends StatefulWidget {
  const MySessionsScreen({super.key});

  @override
  State<MySessionsScreen> createState() => _MySessionsScreenState();
}

class _MySessionsScreenState extends State<MySessionsScreen>
    with SingleTickerProviderStateMixin {
  final SessionService _sessionService = SessionService();
  final SupabaseClient _supabase = Supabase.instance.client;
  final DeviceCalendarPlugin _deviceCalendarPlugin = DeviceCalendarPlugin();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  
  bool isLoading = true;
  List<Map<String, dynamic>> activeSessions = [];
  List<Map<String, dynamic>> rescheduledSessions = [];
  List<Map<String, dynamic>> completedSessions = [];
  late TabController _tabController;
  StreamSubscription? _sessionSub;
  StreamSubscription? _mentorSub;
  bool _isDisposed = false;

  late RealtimeChannel _studentNotificationChannel;
  late RealtimeChannel _studentDirectChannel;

 @override
void initState() {
  super.initState();
  _tabController = TabController(length: 4, vsync: this); 
  tz.initializeTimeZones(); 
  _initializeNotifications();
  _loadAllSessions().then((_) {
    if (!_isDisposed) {
      _setupSessionNotifications();
      _setupMentorSessionNotifications(); 
      // Add a small delay to ensure proper initialization
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_isDisposed) {
          _setupStudentNotificationListener();
          _setupDirectNotificationListener();
          _listenForSessionStatusNotifications();
        }
      });
    }
  });
}

@override
void didChangeDependencies() {
  super.didChangeDependencies();
  // Re-setup listeners if they were disposed (e.g., during navigation)
  if (_isDisposed && mounted) {
    _isDisposed = false;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted && !_isDisposed) {
        _setupStudentNotificationListener();
        _setupDirectNotificationListener();
        _listenForSessionStatusNotifications();
      }
    });
  }
}

  void _initializeNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    
    await _notificationsPlugin.initialize(settings);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _tabController.dispose();
    _sessionSub?.cancel();
    _mentorSub?.cancel();
    _studentNotificationChannel.unsubscribe();
    _studentDirectChannel.unsubscribe();
    super.dispose();
  }

  void _setupDirectNotificationListener() {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    debugPrint('🎯 Setting up DIRECT student notification listener for: $currentUserId');

    _studentDirectChannel = _supabase.channel('student_direct_$currentUserId');
    
    _studentDirectChannel.onBroadcast(
      event: 'session_status_update',
      callback: (payload) async {
        debugPrint('📡 Student received DIRECT notification: $payload');
        
        final data = payload['payload'];
        final title = data['title']?.toString() ?? 'Session Update';
        final message = data['message']?.toString() ?? 'Your session status has been updated';
        final status = data['status']?.toString();
        
        // Show local notification
        await _showLocalNotification(title, message);
        
        // Show in-app snackbar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: status == 'accepted' ? Colors.green : Colors.orange,
            ),
          );
        }
        
        // Reload sessions to reflect status changes
        _loadAllSessions();
      },
    ).subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint('✅ Student DIRECT notification listener SUBSCRIBED');
      } else if (status == RealtimeSubscribeStatus.closed) {
        debugPrint('🛑 Student DIRECT notification listener closed');
      }
      if (error != null) {
        debugPrint('❌ Student DIRECT notification listener error: $error');
      }
    });
  }

void _setupStudentNotificationListener() {
  final currentUserId = _supabase.auth.currentUser?.id;
  if (currentUserId == null) return;

  debugPrint('🎯 Setting up student notification listener for: $currentUserId');

  _studentNotificationChannel = _supabase.channel('student_session_updates_$currentUserId');
  
  _studentNotificationChannel.onPostgresChanges(
    event: PostgresChangeEvent.all, 
    schema: 'public',
    table: 'notifications',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'user_id',
      value: currentUserId,
    ),
    callback: (payload) async {
      debugPrint('📨 Student received DB notification: ${payload.eventType} - ${payload.newRecord}');

      if (payload.eventType == PostgresChangeEvent.insert) {
        final notification = payload.newRecord;
        final title = notification['title']?.toString() ?? 'Session Update';
        final message = notification['message']?.toString() ?? 'Your session status has been updated';
        final type = notification['type']?.toString();
        
        if (type == 'session_status') {

          await _showLocalNotification(title, message);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: title.contains('Accepted') ? Colors.green : Colors.orange,
              ),
            );
          }
          
          _loadAllSessions();
        }
      }
    },
  ).subscribe((status, error) {
    if (status == RealtimeSubscribeStatus.subscribed) {
      debugPrint('✅ Student DB notification listener SUBSCRIBED');
    } else if (status == RealtimeSubscribeStatus.closed) {
      debugPrint('🛑 Student DB notification listener closed');
    }
    if (error != null) {
      debugPrint('❌ Student DB notification listener error: $error');
    }
  });
}

  Future<void> _showLocalNotification(String title, String body) async {
    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'student_session_updates',
        'Session Status Updates',
        channelDescription: 'Notifications when your session status changes',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
        colorized: true,
        color: Colors.green,
      );

      const DarwinNotificationDetails iosDetails =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const NotificationDetails details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        body,
        details,
      );

      debugPrint('📱 Local notification shown: $title');
    } catch (e) {
      debugPrint('❌ Error showing local notification: $e');
    }
  }

 // In student side - MySessionsScreen
void checkStudentNotificationStatus() {
  final currentUserId = _supabase.auth.currentUser?.id;
  if (currentUserId == null) {
    debugPrint('❌ Student: No user ID available');
    return;
  }
  
  debugPrint('🎯 STUDENT DEBUG INFO:');
  debugPrint('   User ID: $currentUserId');
  debugPrint('   Notification channel: student_session_updates_$currentUserId');
  debugPrint('   Direct channel: student_direct_$currentUserId');
  debugPrint('   Status channel: student_session_status_$currentUserId');
  
  // Check if we have any existing notifications
  _supabase
      .from('notifications')
      .select('*')
      .eq('user_id', currentUserId)
      .order('created_at', ascending: false)
      .limit(5)
      .then((notifications) {
    debugPrint('   Recent notifications: ${notifications.length}');
    for (var notif in notifications) {
      debugPrint('     - ${notif['title']}: ${notif['message']}');
    }
  });
}


  void _setupSessionNotifications() {
    if (_isDisposed) return;
    
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    _sessionSub?.cancel();
    _sessionSub = _supabase
        .from('mentor_sessions')
        .stream(primaryKey: ['id'])
        .listen((sessions) {
      if (_isDisposed) return;
      _loadAllSessions();
    }, onError: (error) {
      debugPrint('Session stream error: $error');
    });
  }

  void _setupMentorSessionNotifications() {
    if (_isDisposed) return;
    
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    _mentorSub?.cancel();
    _mentorSub = _supabase
        .from('mentor_sessions')
        .stream(primaryKey: ['id'])
        .listen((sessions) {
      if (_isDisposed) return;
      _loadAllSessions();
    }, onError: (error) {
      debugPrint('Mentor stream error: $error');
    });
  }

  Future<void> _loadAllSessions() async {
    if (_isDisposed) return;
    
    setState(() => isLoading = true);

    try {
      // ✅ LOAD ALL SESSION TYPES SEPARATELY
      final activeData = await _sessionService.getActiveSessions();
      final rescheduledData = await _sessionService.getRescheduledSessions();
      final completedData = await _sessionService.getCompletedSessions();

      if (!_isDisposed) {
        setState(() {
          activeSessions = activeData;
          rescheduledSessions = rescheduledData;
          completedSessions = completedData;
          isLoading = false;
        });
        
        _addAcceptedSessionsToCalendar(activeData);
      }
    } catch (e) {
      if (!_isDisposed) {
        setState(() => isLoading = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to load sessions: $e"))
          );
        }
      }
    }
  }

  Future<void> _addAcceptedSessionsToCalendar(List<Map<String, dynamic>> sessions) async {
    try {
      final permissionStatus = await Permission.calendarWriteOnly.request();
      if (!permissionStatus.isGranted) {
        debugPrint('Calendar permission denied');
        return;
      }

      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();

      if (!calendarsResult.isSuccess || calendarsResult.data == null || calendarsResult.data!.isEmpty) {
        debugPrint('No calendars found');
        return;
      }

      final Calendar calendar = calendarsResult.data!.first;

      for (final session in sessions) {
        if (session['status'] == 'accepted') {
          await _addSessionToCalendar(session, calendar);
        }
      }
    } catch (e) {
      debugPrint('Error adding sessions to calendar: $e');
    }
  }

  Future<void> _addSessionToCalendar(Map<String, dynamic> session, Calendar calendar) async {
    try {
      final sessionDate = session['session_date'] as String;
      final sessionTime = session['session_time'] as String;
      
      final startDateTime = DateTime.parse('$sessionDate $sessionTime');
      final endDateTime = startDateTime.add(const Duration(hours: 1));
      
      final startTz = tz.TZDateTime.from(startDateTime, tz.local);
      final endTz = tz.TZDateTime.from(endDateTime, tz.local);

      final Event event = Event(calendar.id)
        ..title = 'Mentorship Session: ${session['session_type']}'
        ..description = 'Mentor: ${session['mentor_name']}\nNotes: ${session['notes'] ?? 'No notes'}'
        ..start = startTz
        ..end = endTz;

      final createEventResult = await _deviceCalendarPlugin.createOrUpdateEvent(event);

      final eventSuccess = createEventResult?.isSuccess;
      if (eventSuccess == true) {
        debugPrint('Session added to calendar: ${session['session_type']}');
        await _scheduleLocalNotification(session, startTz); 
      } else {
        final errorMessages = createEventResult?.errors;
        final errorText = errorMessages?.join(', ') ?? 'Unknown error';
        debugPrint('Failed to add session to calendar: $errorText');
      }
    } catch (e) {
      debugPrint('Error adding session to calendar: $e');
    }
  }

  Future<void> _scheduleLocalNotification(Map<String, dynamic> session, DateTime sessionTime) async {
    final scheduledTime = sessionTime.subtract(const Duration(minutes: 30));
    
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'mentorship_channel',
      'Mentorship Sessions',
      channelDescription: 'Notifications for mentorship sessions',
      importance: Importance.high,
      priority: Priority.high,
    );
    
    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails();
    
    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    
    final scheduledNotificationTime = tz.TZDateTime.from(scheduledTime, tz.local);
    
    await _notificationsPlugin.zonedSchedule(
      session['id'].hashCode,
      'Upcoming Mentorship Session',
      'You have a session with ${session['mentor_name']} in 30 minutes',
      scheduledNotificationTime,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  void _listenForSessionStatusNotifications() {
    if (_isDisposed) return;
    
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    debugPrint('🎯 Student session status listener started for user: $currentUserId');

    // Listen for direct session updates
    final statusChannel = _supabase.channel('student_session_status_$currentUserId');
    
    statusChannel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'mentor_sessions',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: currentUserId,
      ),
      callback: (payload) async {
        if (_isDisposed) return;
        
        debugPrint('📡 Student received session update: ${payload.eventType}');
        debugPrint('📦 Session data: ${payload.newRecord}');
        
        final updatedSession = payload.newRecord;
        final newStatus = updatedSession['status']?.toString();
        final mentorId = updatedSession['mentor_id']?.toString();
        final sessionUserId = updatedSession['user_id']?.toString();
        
        debugPrint('🔍 Status: $newStatus, Session User: $sessionUserId, Current User: $currentUserId');
        
        // Check if this session belongs to current student AND status changed to accepted/declined
        if (sessionUserId == currentUserId && (newStatus == 'accepted' || newStatus == 'declined')) {
          debugPrint('✅ Conditions met - showing notification to student');
          
          try {
            String mentorName = 'Mentor';
            
            if (mentorId != null && mentorId.isNotEmpty) {
              final mentorProfile = await _supabase
                  .from('profiles_new')
                  .select('username')
                  .eq('id', mentorId)
                  .single();

              mentorName = mentorProfile['username'] ?? 'Mentor';
            }

            final sessionType = updatedSession['session_type']?.toString() ?? 'session';
            final sessionDate = updatedSession['session_date']?.toString() ?? '';
            final sessionTime = updatedSession['session_time']?.toString() ?? '';
            
            debugPrint('👨‍🏫 Mentor: $mentorName, Session Type: $sessionType');

            String title = '';
            String body = '';

            if (newStatus == 'accepted') {
              title = 'Session Accepted! 🎉';
              body = '$mentorName accepted your $sessionType session on $sessionDate at $sessionTime';
            } else {
              title = 'Session Declined';
              body = '$mentorName declined your $sessionType session request';
            }

            // Show both local and in-app notification
            await _showLocalNotification(title, body);
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(body),
                  backgroundColor: newStatus == 'accepted' ? Colors.green : Colors.orange,
                  duration: const Duration(seconds: 5),
                ),
              );
            }
            
            // Reload sessions
            _loadAllSessions();
            
            debugPrint('🔔 Student notification shown: $newStatus from $mentorName');
          } catch (e) {
            debugPrint('❌ Error showing student notification: $e');
          }
        } else {
          debugPrint('🔕 Conditions not met - skipping notification');
        }
      },
    ).subscribe((status, error) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        debugPrint('✅ Student session status listener SUBSCRIBED successfully');
      } else if (status == RealtimeSubscribeStatus.closed) {
        debugPrint('🛑 Student session status listener closed');
      }
      if (error != null) {
        debugPrint('❌ Student session status listener error: $error');
      }
    });
  }

  Future<void> _addToCalendar(BuildContext context, Map<String, dynamic> session) async {
    final currentContext = context;
    
    if (session['status'] != 'accepted') {
      if (mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          const SnackBar(content: Text('Only accepted sessions can be added to calendar'))
        );
      }
      return;
    }

    try {    
      final permissionStatus = await Permission.calendarWriteOnly.request();
      if (!permissionStatus.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(currentContext).showSnackBar(
            const SnackBar(content: Text('Calendar permission is required'))
          );
        }
        return;
      }

      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();
      
      if (!calendarsResult.isSuccess || calendarsResult.data == null || calendarsResult.data!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(currentContext).showSnackBar(
            const SnackBar(content: Text('No calendars available'))
          );
        }
        return;
      }

      final Calendar calendar = calendarsResult.data!.first;
      await _addSessionToCalendar(session, calendar);

      if (mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          const SnackBar(content: Text('Session added to calendar!'))
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(content: Text('Failed to add to calendar: $e'))
        );
      }
    }
  }

  List<Map<String, dynamic>> _filterByStatus(List<Map<String, dynamic>> sessions, String status) {
    return sessions.where((s) => s['status'] == status).toList();
  }


  Widget _buildSessionList(
    List<Map<String, dynamic>> sessions, 
    Size screenSize, 
    bool isSmallScreen, {
    bool showOriginalInfo = false,
  }) {
    if (sessions.isEmpty) {
      return _buildEmptyState("No sessions here", "Schedule a new session to get started", isSmallScreen);
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 8 : 12,
        vertical: isSmallScreen ? 6 : 8,
      ),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        return _buildSessionCard(session, screenSize, isSmallScreen, showOriginalInfo: showOriginalInfo);
      },
    );
  }

  Widget _buildRescheduledSessionList(List<Map<String, dynamic>> sessions, Size screenSize, bool isSmallScreen) {
    if (sessions.isEmpty) {
      return _buildEmptyState("No rescheduled sessions", "Rescheduled sessions will appear here", isSmallScreen);
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 8 : 12,
        vertical: isSmallScreen ? 6 : 8,
      ),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        return _buildSessionCard(session, screenSize, isSmallScreen, showOriginalInfo: true);
      },
    );
  }

  Widget _buildSessionCard(
    Map<String, dynamic> session, 
    Size screenSize, 
    bool isSmallScreen, {
    bool showOriginalInfo = false,
  }) {
    Color statusColor;
    IconData statusIcon;
    
    switch (session['status']) {
      case 'accepted':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'declined':
      case 'rejected':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        break;
      case 'rescheduled':
        statusColor = Colors.orange;
        statusIcon = Icons.schedule;
        break;
      case 'completed':
        statusColor = Colors.blue;
        statusIcon = Icons.done_all;
        break;
      case 'pending':
      default:
        statusColor = Colors.amber;
        statusIcon = Icons.pending;
    }

    return Card(
      color: Theme.of(context).cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 4 : 0,
        vertical: isSmallScreen ? 6 : 8,
      ),
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with session type and status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    session['session_type'] ?? 'Session',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: isSmallScreen ? 16 : 18,
                      color: Theme.of(context).textTheme.titleMedium?.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isSmallScreen ? 8 : 12,
                    vertical: isSmallScreen ? 4 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        statusIcon,
                        size: isSmallScreen ? 14 : 16,
                        color: statusColor,
                      ),
                      if (!isSmallScreen) ...[
                        const SizedBox(width: 4),
                        Text(
                          session['status'],
                          style: TextStyle(
                            fontSize: isSmallScreen ? 12 : 14,
                            fontWeight: FontWeight.w600,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            
            SizedBox(height: isSmallScreen ? 8 : 12),
            
            // Mentor info
            Row(
              children: [
                Icon(
                  Icons.person,
                  size: isSmallScreen ? 16 : 18,
                  color: Colors.grey[600],
                ),
                SizedBox(width: isSmallScreen ? 6 : 8),
                Expanded(
                  child: Text(
                    "Mentor: ${session['mentor_name'] ?? 'Unknown'}",
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            
            SizedBox(height: isSmallScreen ? 6 : 8),
            
            // ✅ SHOW ORIGINAL DATE/TIME FOR RESCHEDULED SESSIONS
            if (showOriginalInfo && session['original_date'] != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.history,
                        size: isSmallScreen ? 16 : 18,
                        color: Colors.orange,
                      ),
                      SizedBox(width: isSmallScreen ? 6 : 8),
                      Expanded(
                        child: Text(
                          "Original: ${session['original_date']} at ${session['original_time']}",
                          style: TextStyle(
                            fontSize: isSmallScreen ? 13 : 14,
                            color: Colors.orange[700],
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isSmallScreen ? 4 : 6),
                ],
              ),
            
            // Current/New Date and time
            Row(
              children: [
                Icon(
                  session['status'] == 'rescheduled' ? Icons.update : Icons.calendar_today,
                  size: isSmallScreen ? 16 : 18,
                  color: session['status'] == 'rescheduled' ? Colors.orange : Colors.grey[600],
                ),
                SizedBox(width: isSmallScreen ? 6 : 8),
                Expanded(
                  child: Text(
                    session['status'] == 'rescheduled' 
                      ? "New Date: ${session['session_date']} at ${session['session_time']}"
                      : "Date: ${session['session_date']} at ${session['session_time']}",
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                      fontWeight: session['status'] == 'rescheduled' ? FontWeight.w600 : FontWeight.normal,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            
            SizedBox(height: isSmallScreen ? 6 : 8),
            
            // Rescheduled timestamp
            if (session['status'] == 'rescheduled' && session['rescheduled_at'] != null)
              Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: isSmallScreen ? 14 : 16,
                    color: Colors.grey[500],
                  ),
                  SizedBox(width: isSmallScreen ? 6 : 8),
                  Text(
                    "Rescheduled: ${_formatRescheduledDate(session['rescheduled_at'])}",
                    style: TextStyle(
                      fontSize: isSmallScreen ? 12 : 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            
            if (session['status'] == 'rescheduled' && session['rescheduled_at'] != null)
              SizedBox(height: isSmallScreen ? 6 : 8),
            
            // Notes
            if (session['notes'] != null && session['notes'].toString().isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.note,
                        size: isSmallScreen ? 16 : 18,
                        color: Colors.grey[600],
                      ),
                      SizedBox(width: isSmallScreen ? 6 : 8),
                      Text(
                        "Notes:",
                        style: TextStyle(
                          fontSize: isSmallScreen ? 14 : 16,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isSmallScreen ? 4 : 6),
                  Padding(
                    padding: EdgeInsets.only(left: isSmallScreen ? 24 : 28),
                    child: Text(
                      session['notes'] ?? 'None',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 13 : 15,
                        color: Colors.grey[700],
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

            // Add to Calendar button for accepted sessions
            if (session['status'] == 'accepted') ...[
              SizedBox(height: isSmallScreen ? 12 : 16),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  icon: Icon(
                    Icons.calendar_today,
                    size: isSmallScreen ? 16 : 18,
                  ),
                  label: Text(
                    'Add to Calendar',
                    style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      horizontal: isSmallScreen ? 12 : 16,
                      vertical: isSmallScreen ? 8 : 12,
                    ),
                  ),
                  onPressed: () => _addToCalendar(context, session),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle, bool isSmallScreen) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isSmallScreen ? 16 : 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_today,
              size: isSmallScreen ? 48 : 64,
              color: Colors.grey[400],
            ),
            SizedBox(height: isSmallScreen ? 12 : 16),
            Text(
              title,
              style: TextStyle(
                color: Theme.of(context).textTheme.bodyMedium?.color,
                fontSize: isSmallScreen ? 16 : 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: isSmallScreen ? 8 : 12),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: isSmallScreen ? 14 : 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatRescheduledDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isSmallScreen = screenSize.width < 600;
    final isVerySmallScreen = screenSize.width < 400;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "My Sessions",
          style: TextStyle(fontSize: isSmallScreen ? 18 : 20),
        ),
        backgroundColor: Colors.indigo,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.lightBlueAccent,
          tabs: [
            Tab(
              text: isVerySmallScreen ? "Pending" : "Pending",
              icon: isVerySmallScreen ? const Icon(Icons.pending) : null,
            ),
            Tab(
              text: isVerySmallScreen ? "Accepted" : "Accepted",
              icon: isVerySmallScreen ? const Icon(Icons.check_circle) : null,
            ),
            Tab( 
              text: isVerySmallScreen ? "Rescheduled" : "Rescheduled",
              icon: isVerySmallScreen ? const Icon(Icons.schedule) : null,
            ),
            Tab(
              text: isVerySmallScreen ? "Declined" : "Declined",
              icon: isVerySmallScreen ? const Icon(Icons.cancel) : null,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.add,
              color: Colors.white,
              size: isSmallScreen ? 20 : 24,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ScheduleSessionScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Pending Sessions
                  _buildSessionList(
                    _filterByStatus(activeSessions, 'pending'), 
                    screenSize, 
                    isSmallScreen,
                    showOriginalInfo: false,
                  ),
                  
                  // Tab 2: Accepted Sessions
                  _buildSessionList(
                    _filterByStatus(activeSessions, 'accepted'), 
                    screenSize, 
                    isSmallScreen,
                    showOriginalInfo: false,
                  ),
                  
                  // Tab 3: Rescheduled Sessions ✅ NEW TAB
                  _buildRescheduledSessionList(rescheduledSessions, screenSize, isSmallScreen),
                  
                  // Tab 4: Declined (only declined sessions)
                  _buildSessionList(
                    _filterByStatus(completedSessions, 'declined'), 
                    screenSize, 
                    isSmallScreen,
                    showOriginalInfo: false,
                  ),
                ],
              ),
      ),
    );
  }
}