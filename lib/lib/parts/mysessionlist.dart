// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import '../services/sessionservice.dart';
import 'package:codexhub01/mentorship/schedulesession_screen.dart'; 
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
  List<Map<String, dynamic>> sessions = [];
  late TabController _tabController;
  StreamSubscription? _sessionSub;
  StreamSubscription? _mentorSub;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    tz.initializeTimeZones(); // Initialize timezone data
    _initializeNotifications();
    _loadSessions().then((_) {
      if (!_isDisposed) {
        _setupSessionNotifications();
        _setupMentorSessionNotifications(); 
      }
    });
  }

  // Initialize local notifications
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
    super.dispose();
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
      _loadSessions();
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
      _loadSessions();
    }, onError: (error) {
      debugPrint('Mentor stream error: $error');
    });
  }

  Future<void> _loadSessions() async {
    if (_isDisposed) return;
    
    setState(() => isLoading = true);

    try {
      final data = await _sessionService.getUserSessions();
      if (!_isDisposed) {
        setState(() {
          sessions = data;
          isLoading = false;
        });
        
        // Add accepted sessions to calendar
        _addAcceptedSessionsToCalendar(data);
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

      // Get device calendars
      final calendarsResult = await _deviceCalendarPlugin.retrieveCalendars();

      if (!calendarsResult.isSuccess || calendarsResult.data == null || calendarsResult.data!.isEmpty) {
  debugPrint('No calendars found');
  return;
}

      // Use first available calendar
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
    // Parse session date and time
    final sessionDate = session['session_date'] as String;
    final sessionTime = session['session_time'] as String;
    
    // Combine date and time to create DateTime objects
    final startDateTime = DateTime.parse('$sessionDate $sessionTime');
    final endDateTime = startDateTime.add(const Duration(hours: 1)); // Assuming 1 hour sessions
    
    // Convert to TZDateTime
    final startTz = tz.TZDateTime.from(startDateTime, tz.local);
    final endTz = tz.TZDateTime.from(endDateTime, tz.local);

    final Event event = Event(calendar.id)
      ..title = 'Mentorship Session: ${session['session_type']}'
      ..description = 'Mentor: ${session['mentor_name']}\nNotes: ${session['notes'] ?? 'No notes'}'
      ..start = startTz
      ..end = endTz;

    final createEventResult = await _deviceCalendarPlugin.createOrUpdateEvent(event);

    // FIXED: Use null-aware access
    final eventSuccess = createEventResult?.isSuccess;
    if (eventSuccess == true) {
      debugPrint('Session added to calendar: ${session['session_type']}');
      await _scheduleLocalNotification(session, startTz); // Pass TZDateTime instead of DateTime
    } else {
      final errorMessages = createEventResult?.errors;
      final errorText = errorMessages?.join(', ') ?? 'Unknown error';
      debugPrint('Failed to add session to calendar: $errorText');
    }
  } catch (e) {
    debugPrint('Error adding session to calendar: $e');
  }
}

  // Schedule local notification for session
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
    
    // FIXED: Proper timezone handling
    final scheduledNotificationTime = tz.TZDateTime.from(scheduledTime, tz.local);
    
    // FIXED: Removed undefined parameters
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

 Future<void> _addToCalendar(BuildContext context, Map<String, dynamic> session) async {
  // Store context in local variable immediately and use it everywhere
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

  List<Map<String, dynamic>> _filterByStatus(String status) {
    return sessions.where((s) => s['status'] == status).toList();
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
                  _buildSessionList(_filterByStatus('pending'), screenSize, isSmallScreen),
                  _buildSessionList(_filterByStatus('accepted'), screenSize, isSmallScreen),
                  _buildSessionList(_filterByStatus('declined'), screenSize, isSmallScreen),
                ],
              ),
      ),
    );
  }

  Widget _buildSessionList(List<Map<String, dynamic>> sessions, Size screenSize, bool isSmallScreen) {
    if (sessions.isEmpty) {
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
                "No sessions here",
                style: TextStyle(
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                  fontSize: isSmallScreen ? 16 : 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: isSmallScreen ? 8 : 12),
              Text(
                "Schedule a new session to get started",
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

    return ListView.builder(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 8 : 12,
        vertical: isSmallScreen ? 6 : 8,
      ),
      itemCount: sessions.length,
      itemBuilder: (context, index) {
        final session = sessions[index];
        Color statusColor;
        IconData statusIcon;
        
        switch (session['status']) {
          case 'accepted':
            statusColor = Colors.green;
            statusIcon = Icons.check_circle;
            break;
          case 'declined':
            statusColor = Colors.red;
            statusIcon = Icons.cancel;
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
                
                // Date and time
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: isSmallScreen ? 16 : 18,
                      color: Colors.grey[600],
                    ),
                    SizedBox(width: isSmallScreen ? 6 : 8),
                    Expanded(
                      child: Text(
                        "Date: ${session['session_date']} at ${session['session_time']}",
                        style: TextStyle(
                          fontSize: isSmallScreen ? 14 : 16,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                
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
      },
    );
  }
}