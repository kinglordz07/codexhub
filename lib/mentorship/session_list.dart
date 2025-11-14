import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import '../services/sessionservice.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

class SessionListScreen extends StatefulWidget {
  const SessionListScreen({super.key});

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen>
    with SingleTickerProviderStateMixin {
  final SessionService _sessionService = SessionService();
  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  final SupabaseClient _supabase = Supabase.instance.client;
  
  bool isLoading = true;
  List<Map<String, dynamic>> sessions = [];
  int _pendingCount = 0;
  String? _loadingSessionId;

  late TabController _tabController;
  late RealtimeChannel _mentorNotificationChannel;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initializeNotifications();
    _setupMentorNotificationListener();
    _loadSessions();
  }

  @override
  void dispose() {
    _mentorNotificationChannel.unsubscribe();
    _tabController.dispose();
    super.dispose();
  }

 void _setupMentorNotificationListener() {
  final currentUserId = _sessionService.currentUserId;
  if (currentUserId == null) {
    debugPrint('❌ Mentor notification listener: No current user ID');
    return;
  }

  debugPrint('🎯 Setting up mentor notification listener for: $currentUserId');

  _mentorNotificationChannel = _supabase.channel('mentor_new_sessions_$currentUserId');
  
  _mentorNotificationChannel.onPostgresChanges(
    event: PostgresChangeEvent.insert,
    schema: 'public',
    table: 'notifications',
    filter: PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'user_id',
      value: currentUserId,
    ),
    callback: (payload) async {
      debugPrint('📨 Mentor RECEIVED notification: ${payload.newRecord}');
      
      final notification = payload.newRecord;
      final title = notification['title']?.toString() ?? 'New Notification';
      final message = notification['message']?.toString() ?? 'You have a new notification';
      
      debugPrint('📢 Notification details - Title: $title, Message: $message');
      
      // Show local notification
      await _showLocalNotification(title, message);
      
      // Show in-app snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      
      // Reload sessions to show new pending requests
      _loadSessions();
    },
  ).subscribe((status, error) {
    if (status == RealtimeSubscribeStatus.subscribed) {
      debugPrint('✅ Mentor notification listener SUBSCRIBED successfully');
    } else if (status == RealtimeSubscribeStatus.closed) {
      debugPrint('🛑 Mentor notification listener closed');
    }
    if (error != null) {
      debugPrint('❌ Mentor notification listener error: $error');
    }
  });
}



  Future<void> _showLocalNotification(String title, String body) async {
   AndroidNotificationDetails androidDetails =
      AndroidNotificationDetails(
    'mentor_notifications',
    'Mentor Notifications',
    channelDescription: 'Notifications for new session requests and updates',
    importance: Importance.max, 
    priority: Priority.max, 
    enableVibration: true,
    playSound: true,
    showWhen: true,
    autoCancel: true,
    styleInformation: BigTextStyleInformation(body), 
  );

  const DarwinNotificationDetails iosDetails =
      DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
    sound: 'default',
  );

   NotificationDetails details = NotificationDetails(
    android: androidDetails,
    iOS: iosDetails,
  );

  await _notifications.show(
    DateTime.now().millisecondsSinceEpoch.remainder(100000),
    title,
    body,
    details,
  );
  
  debugPrint('📢 HIGH PRIORITY NOTIFICATION SENT: $title');
}

  Future<void> _initializeNotifications() async {
  try {
    debugPrint('🔔 STARTING NOTIFICATION INITIALIZATION...');
    
    tz.initializeTimeZones();
    debugPrint('✅ Time zones initialized');
    
const AndroidNotificationChannel mentorChannel = AndroidNotificationChannel(
  'mentor_notifications',
  'Mentor Notifications', 
  description: 'Notifications for new session requests and updates',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  showBadge: true,
);

const AndroidNotificationChannel studentChannel = AndroidNotificationChannel(
  'student_session_updates',
  'Session Status Updates',
  description: 'Notifications when your session status changes',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  showBadge: true,
);

const AndroidNotificationChannel sessionStartChannel = AndroidNotificationChannel(
  'session_start',
  'Session Start',
  description: 'Notifications when sessions start',
  importance: Importance.max,
  playSound: true,
  enableVibration: true,
  showBadge: true,
);

    // Initialize Android settings with channels
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    debugPrint('📱 Initializing notifications plugin...');
    await _notifications.initialize(initSettings);
    debugPrint('✅ Notifications plugin initialized');
    
    // Create channels (Android 8.0+)
    final androidPlugin = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    if (androidPlugin != null) {
      debugPrint('📱 Creating notification channels...');
      await androidPlugin.createNotificationChannel(mentorChannel);
      await androidPlugin.createNotificationChannel(studentChannel);
      await androidPlugin.createNotificationChannel(sessionStartChannel);
      debugPrint('✅ Notification channels created successfully');
      
      // Check if notifications are enabled
      final bool? notificationsEnabled = await androidPlugin.areNotificationsEnabled();
      debugPrint('📱 System notifications enabled: $notificationsEnabled');
    } else {
      debugPrint('❌ Android notifications plugin not available');
    }
    
    // Request notification permission
    debugPrint('🔐 Requesting notification permission...');
    final status = await Permission.notification.request();
    debugPrint('🔐 Notification permission status: $status');
    
    debugPrint('🎉 NOTIFICATION INITIALIZATION COMPLETE');
    
  } catch (e) {
    debugPrint('💥 ERROR in notification initialization: $e');
  }
}

  Future<void> _scheduleSessionStartNotification(Map<String, dynamic> session) async {
    try {
      final sessionDate = DateTime.parse(session['session_date']);
      final sessionTimeParts = session['session_time'].split(':');
      
      if (sessionTimeParts.length < 2) {
        debugPrint('⚠️ Invalid session time format: ${session['session_time']}');
        return;
      }
      
      final sessionDateTime = DateTime(
        sessionDate.year,
        sessionDate.month,
        sessionDate.day,
        int.parse(sessionTimeParts[0]),
        int.parse(sessionTimeParts[1]),
      );

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'session_start',
        'Session Start',
        channelDescription: 'Notifications when sessions start',
        importance: Importance.high,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          sound: 'default',
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      final location = tz.local;
      final scheduledDate = tz.TZDateTime.from(sessionDateTime, location);

      await _notifications.zonedSchedule(
        session['id'].hashCode + 5000, 
        'Session Starting Now! 🚀',
        'Your ${session['session_type']} with ${session['profiles_new']?['username'] ?? 'Mentor'} is starting now',
        scheduledDate,
        platformDetails,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      debugPrint('Session start notification scheduled for ${session['id']} at $scheduledDate'); // FIXED: Added debugPrint
    } catch (e) {
      debugPrint('Error scheduling session start notification: $e'); // FIXED: Added debugPrint
    }
  }

  Future<void> _loadSessions() async {
    setState(() => isLoading = true);
    try {
      final data = await _sessionService.getMentorSessions();
      setState(() {
        sessions = data;
        isLoading = false;
        _pendingCount = _filterByStatus('pending').length;
      });
    } catch (e) {
      setState(() => isLoading = false);
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load sessions: $e")),
        );
      }
    }
  }

  Future<void> _updateSessionStatus(String sessionId, String status) async {
    setState(() => _loadingSessionId = sessionId);
    try {
      await _sessionService.updateSessionStatus(sessionId, status);
      
      final session = sessions.firstWhere((s) => s['id'] == sessionId);
      
      try {
        final studentProfile = await _supabase 
            .from('profiles_new')
            .select('username')
            .eq('id', session['user_id']) 
            .single();
        
        final studentName = studentProfile['username'] ?? 'Student';
        debugPrint('🎯 Notification target: Student $studentName');
        
      } catch (e) {
        debugPrint('⚠️ Could not fetch student profile: $e');
      }
      
      if (status == 'accepted') {
        await _scheduleSessionStartNotification(session);
      }

      _loadSessions(); 
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Session $status")),
        );
      }
    } catch (e) {
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update session: $e")),
        );
      }
    } finally {
      setState(() => _loadingSessionId = null);
    }
  }

  Future<void> _rescheduleSession(Map<String, dynamic> session) async {
    final DateTime? newDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (!mounted || newDate == null) return;

    final TimeOfDay? newTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );

    if (newTime == null) return;

    final DateTime newDateTime = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      newTime.hour,
      newTime.minute,
    );

    try {
      await _sessionService.rescheduleSession(
        session['id'],
        newDateTime.toIso8601String().split('T')[0],
        "${newTime.hour.toString().padLeft(2, '0')}:${newTime.minute.toString().padLeft(2, '0')}",
        newDateTime.toIso8601String(),
        tz.local.name,
      );
      
      await _sessionService.updateSessionStatus(session['id'], 'rescheduled');
      
      final updatedSession = {...session};
      updatedSession['session_date'] = newDateTime.toIso8601String().split('T')[0];
      updatedSession['session_time'] = "${newTime.hour.toString().padLeft(2, '0')}:${newTime.minute.toString().padLeft(2, '0')}";
      await _scheduleSessionStartNotification(updatedSession);

      _loadSessions();
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Session rescheduled successfully!")),
        );
      }
    } catch (e) {
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to reschedule session: $e")),
        );
      }
    }
  }

  List<Map<String, dynamic>> _filterByStatus(String status) {
    return sessions.where((s) => s['status'] == status).toList();
  }

  ScreenType get _screenType {
    final double width = MediaQuery.of(context).size.width;
    if (width < 600) return ScreenType.small;
    if (width < 1024) return ScreenType.medium;
    return ScreenType.large;
  }

  EdgeInsets get _screenPadding {
    switch (_screenType) {
      case ScreenType.small: return const EdgeInsets.all(16);
      case ScreenType.medium: return const EdgeInsets.all(20);
      case ScreenType.large: return const EdgeInsets.all(24);
    }
  }

  double get _titleFontSize {
    switch (_screenType) {
      case ScreenType.small: return 16;
      case ScreenType.medium: return 18;
      case ScreenType.large: return 20;
    }
  }

  double get _bodyFontSize {
    switch (_screenType) {
      case ScreenType.small: return 14;
      case ScreenType.medium: return 16;
      case ScreenType.large: return 16;
    }
  }

  double get _iconSize {
    switch (_screenType) {
      case ScreenType.small: return 16;
      case ScreenType.medium: return 18;
      case ScreenType.large: return 20;
    }
  }

  EdgeInsets get _buttonPadding {
    switch (_screenType) {
      case ScreenType.small: return const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
      case ScreenType.medium: return const EdgeInsets.symmetric(horizontal: 16, vertical: 12);
      case ScreenType.large: return const EdgeInsets.symmetric(horizontal: 20, vertical: 14);
    }
  }

  double get _minTouchSize => 44;

  Widget _buildSessionList(List<Map<String, dynamic>> list) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (list.isEmpty) {
      return Center(
        child: Padding(
          padding: _screenPadding,
          child: Text(
            "No sessions here.",
            style: TextStyle(
              fontSize: _bodyFontSize,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_screenType == ScreenType.large) {
      return _buildGridView(list);
    } else {
      return _buildListView(list);
    }
  }

  Widget _buildListView(List<Map<String, dynamic>> list) {
    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: ListView.builder(
        padding: _screenPadding.copyWith(top: 12, bottom: 12),
        itemCount: list.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: EdgeInsets.only(bottom: _screenType == ScreenType.small ? 12 : 16),
            child: _buildSessionCard(list[index]),
          );
        },
      ),
    );
  }

  Widget _buildGridView(List<Map<String, dynamic>> list) {
    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: GridView.builder(
        padding: _screenPadding,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _screenType == ScreenType.large ? 3 : 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: _screenType == ScreenType.large ? 1.6 : 1.4,
        ),
        itemCount: list.length,
        itemBuilder: (context, index) {
          return _buildSessionCard(list[index]);
        },
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final status = session['status'] ?? 'pending';
    final isPending = status == 'pending';
    final isAccepted = status == 'accepted' || status == 'rescheduled';
    final isLoading = _loadingSessionId == session['id'];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? Colors.grey[850] : Colors.white,
      child: Padding(
        padding: _screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Icon(
                  Icons.person,
                  color: Colors.indigo,
                  size: _iconSize + 2,
                ),
                SizedBox(width: _screenType == ScreenType.small ? 12 : 16),
                Expanded(
                  child: Text(
                    "${session['profiles_new']?['username'] ?? 'Unknown User'} "
                    "(${session['session_type'] ?? 'N/A'})",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: _titleFontSize,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isPending)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: _screenType == ScreenType.small ? 8 : 12,
                      vertical: _screenType == ScreenType.small ? 4 : 6,
                    ),
                    decoration: BoxDecoration(
                      color: status == 'accepted' 
                          ? Colors.green.withAlpha(25)
                          : status == 'rescheduled'
                          ? Colors.orange.withAlpha(25)
                          : Colors.red.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: _screenType == ScreenType.small ? 10 : 12,
                        color: status == 'accepted' 
                            ? Colors.green 
                            : status == 'rescheduled'
                            ? Colors.orange
                            : Colors.red,
                      ),
                    ),
                  ),
              ],
            ),
            
            SizedBox(height: _screenType == ScreenType.small ? 12 : 16),
            
            // Session Details
            _buildDetailRow(
              Icons.calendar_today,
              "Date: ${session['session_date'] ?? 'N/A'} at ${session['session_time'] ?? 'N/A'}",
            ),
            
            SizedBox(height: _screenType == ScreenType.small ? 8 : 12),
            
            _buildDetailRow(
              Icons.note,
              "Notes: ${session['notes'] ?? 'None'}",
            ),

            if (session['rescheduled_at'] != null) ...[
              SizedBox(height: _screenType == ScreenType.small ? 8 : 12),
              _buildDetailRow(
                Icons.schedule,
                "Rescheduled on: ${_formatRescheduledDate(session['rescheduled_at'])}",
              ),
            ],
            
            // Action Buttons
            SizedBox(height: _screenType == ScreenType.small ? 16 : 20),
            if (isLoading)
              const Center(child: CircularProgressIndicator()) // FIXED: Added const
            else
              _buildActionButtons(session, isPending, isAccepted),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: _iconSize,
          color: isDark ? Colors.white60 : Colors.black54,
        ),
        SizedBox(width: _screenType == ScreenType.small ? 8 : 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: _bodyFontSize,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(Map<String, dynamic> session, bool isPending, bool isAccepted) {
    if (_screenType == ScreenType.small && (isPending || isAccepted)) {
      return Column(
        children: _buildButtonChildren(session, isPending, isAccepted, true),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: _buildButtonChildren(session, isPending, isAccepted, false),
    );
  }

  List<Widget> _buildButtonChildren(Map<String, dynamic> session, bool isPending, bool isAccepted, bool isVertical) {
    final children = <Widget>[];
    
    if (isPending) {
      children.addAll([
        _buildActionButton(
          icon: Icons.check,
          label: "Accept",
          color: Colors.green,
          onPressed: () => _updateSessionStatus(session['id'], 'accepted'),
          isVertical: isVertical,
        ),
        if (isVertical) SizedBox(height: 8) else SizedBox(width: 12),
        _buildActionButton(
          icon: Icons.schedule,
          label: "Reschedule",
          color: Colors.orange,
          onPressed: () => _rescheduleSession(session),
          isVertical: isVertical,
        ),
        if (isVertical) SizedBox(height: 8) else SizedBox(width: 12),
        _buildActionButton(
          icon: Icons.close,
          label: "Decline",
          color: Colors.red,
          onPressed: () => _updateSessionStatus(session['id'], 'declined'),
          isVertical: isVertical,
        ),
      ]);
    } else if (isAccepted) {
      children.addAll([
        _buildActionButton(
          icon: Icons.schedule,
          label: "Reschedule",
          color: Colors.orange,
          onPressed: () => _rescheduleSession(session),
          isVertical: isVertical,
        ),
        if (isVertical) SizedBox(height: 8) else SizedBox(width: 12),
        _buildActionButton(
          icon: Icons.cancel,
          label: "Cancel",
          color: Colors.red,
          onPressed: () => _updateSessionStatus(session['id'], 'cancelled'),
          isVertical: isVertical,
        ),
      ]);
    }
    
    return children;
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
    required bool isVertical,
  }) {
    return SizedBox(
      width: isVertical ? double.infinity : null,
      height: _minTouchSize,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: _iconSize),
        label: Text(
          label,
          style: TextStyle(fontSize: _bodyFontSize),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: _buttonPadding,
          minimumSize: Size(_minTouchSize, _minTouchSize),
        ),
        onPressed: onPressed,
      ),
    );
  }

  String _formatRescheduledDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Stack(
          children: [
            const Text("My Session Requests"),
            if (_pendingCount > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$_pendingCount',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
        backgroundColor: primaryColor,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: TextStyle(
            fontSize: _bodyFontSize,
            fontWeight: FontWeight.w500,
          ),
          tabs: const [
            Tab(text: "Pending"),
            Tab(text: "Accepted"),
            Tab(text: "Rescheduled"),
            Tab(text: "Declined"),
          ],
        ),
      ),
      body: SafeArea(
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildSessionList(_filterByStatus('pending')),
                  _buildSessionList(_filterByStatus('accepted')),
                  _buildSessionList(_filterByStatus('rescheduled')),
                  _buildSessionList(_filterByStatus('declined')),
                ],
              ),
      ),
    );
  }
}

enum ScreenType { small, medium, large }