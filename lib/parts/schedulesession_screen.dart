import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/sessionservice.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

class ScheduleSessionScreen extends StatefulWidget {
  const ScheduleSessionScreen({super.key});

  @override
  State<ScheduleSessionScreen> createState() => _ScheduleSessionScreenState();
}

class _ScheduleSessionScreenState extends State<ScheduleSessionScreen> {
  DateTime? selectedDate;
  TimeOfDay? selectedTime;
  String selectedSessionType = 'One-on-One Mentorship';
  final TextEditingController notesController = TextEditingController();
  List<Map<String, dynamic>> mentors = [];
  String? selectedMentorId;
  bool _isLoadingMentors = true;
  final List<String> sessionTypes = [
    'One-on-One Mentorship',
    'Group Session',
    'Live Code Review',
  ];

  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin;

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    _initializeNotifications(); 
    _fetchMentors();
  }

  Future<void> _initializeNotifications() async {
    flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) {
        ('Notification tapped!');
      },
    );
  }

Future<void> _scheduleSessionNotification(DateTime sessionDateTime, String mentorName) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'session_reminders',
    'Session Reminders',
    channelDescription: 'Reminders for your mentorship sessions',
    importance: Importance.high,
    priority: Priority.high,
    enableVibration: true,
    playSound: true,
  );

  const DarwinNotificationDetails iosPlatformChannelSpecifics =
      DarwinNotificationDetails(
    sound: 'default',
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
    iOS: iosPlatformChannelSpecifics,
  );

  try {
    final location = tz.local;
    final scheduledDate = tz.TZDateTime.from(sessionDateTime, location);

    await flutterLocalNotificationsPlugin.zonedSchedule(
      0, 
      'Mentorship Session Starting Now!',
      'Your $selectedSessionType with $mentorName is starting now',
      scheduledDate,
      platformChannelSpecifics,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle, 
    );

    ('Notification scheduled for exact session time: $scheduledDate');
  } catch (e) {
    ('Error scheduling notification: $e');
  }
}

  Future<void> _fetchMentors() async {
    try {
      final response = await Supabase.instance.client
          .from('profiles_new')
          .select('id, username')
          .eq('role', 'mentor');

      setState(() {
        mentors = List<Map<String, dynamic>>.from(response);
        if (mentors.isNotEmpty) {
          selectedMentorId = mentors.first['id'] as String;
        }
        _isLoadingMentors = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingMentors = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load mentors: $e")),
        );
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  Future<void> _selectTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) setState(() => selectedTime = picked);
  }

  void _scheduleSession() async {
    final sessionService = SessionService();
    final currentUserId = sessionService.currentUserId;

    if (currentUserId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User not logged in.")),
      );
      return;
    }

    if (selectedMentorId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a mentor.")),
      );
      return;
    }

    if (selectedDate == null || selectedTime == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a date and time.")),
      );
      return;
    }

    final sessionDateTime = DateTime(
      selectedDate!.year,
      selectedDate!.month,
      selectedDate!.day,
      selectedTime!.hour,
      selectedTime!.minute,
    );

    if (sessionDateTime.isBefore(DateTime.now())) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Cannot schedule session in the past.")),
      );
      return;
    }

    final mentorId = selectedMentorId!;
    final menteeId = currentUserId;
    final selectedMentor = mentors.firstWhere(
      (m) => m['id'] == selectedMentorId,
      orElse: () => {'username': 'Your Mentor'},
    );
    final mentorName = selectedMentor['username'] ?? 'Your Mentor';

    final timeString =
        "${selectedTime!.hour.toString().padLeft(2, '0')}:${selectedTime!.minute.toString().padLeft(2, '0')}";

    try {
      await sessionService.scheduleSession(
        mentorId: mentorId,
        userId: menteeId,
        sessionType: selectedSessionType,
        date: selectedDate!,
        timeString: timeString,
        notes: notesController.text,
      );

      await _scheduleSessionNotification(sessionDateTime, mentorName);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session Scheduled Successfully! You will receive reminders before your session.")),
      );

      setState(() {
        selectedDate = null;
        selectedTime = null;
        selectedSessionType = 'One-on-One Mentorship';
        notesController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed: $e")),
      );
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
          "Schedule Mentorship Session",
          style: TextStyle(fontSize: isSmallScreen ? 18 : 20),
        ),
        backgroundColor: Colors.indigo,
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
          child: ListView(
            children: [
              // Mentor Dropdown
              _buildMentorDropdown(isSmallScreen),
              SizedBox(height: isSmallScreen ? 16 : 20),

              // Session Type Dropdown
              _buildSessionTypeDropdown(isSmallScreen),
              SizedBox(height: isSmallScreen ? 16 : 20),

              // Date Picker
              _buildDatePicker(isSmallScreen, isVerySmallScreen),
              SizedBox(height: isSmallScreen ? 16 : 20),

              // Time Picker
              _buildTimePicker(isSmallScreen, isVerySmallScreen),
              SizedBox(height: isSmallScreen ? 16 : 20),

              // Notes
              _buildNotesSection(isSmallScreen),
              SizedBox(height: isSmallScreen ? 20 : 30),

              // ADD NOTIFICATION INFO TEXT
              _buildNotificationInfo(isSmallScreen),
              SizedBox(height: isSmallScreen ? 10 : 15),

              // Confirm Button
              _buildConfirmButton(isSmallScreen),
            ],
          ),
        ),
      ),
    );
  }

Widget _buildNotificationInfo(bool isSmallScreen) {
  return Container(
    padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
    decoration: BoxDecoration(
      color: Colors.blue[50],
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.blue[100]!),
    ),
    child: Row(
      children: [
        Icon(Icons.notifications_active, color: Colors.blue[700], size: isSmallScreen ? 18 : 20),
        SizedBox(width: isSmallScreen ? 8 : 12),
        Expanded(
          child: Text(
            "You'll receive a notification when your session starts",
            style: TextStyle(
              fontSize: isSmallScreen ? 12 : 14,
              color: Colors.blue[800],
            ),
          ),
        ),
      ],
    ),
  );
}

  Widget _buildMentorDropdown(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Select Mentor",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isSmallScreen ? 14 : 16,
          ),
        ),
        SizedBox(height: isSmallScreen ? 6 : 8),
        _isLoadingMentors
            ? Container(
                height: isSmallScreen ? 50 : 56,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Center(
                  child: SizedBox(
                    width: isSmallScreen ? 20 : 24,
                    height: isSmallScreen ? 20 : 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : mentors.isEmpty
                ? Container(
                    height: isSmallScreen ? 50 : 56,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        "No mentors available",
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: isSmallScreen ? 14 : 16,
                        ),
                      ),
                    ),
                  )
                : DropdownButtonFormField<String>(
                    initialValue: selectedMentorId,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: isSmallScreen ? 12 : 16,
                        vertical: isSmallScreen ? 14 : 16,
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    dropdownColor: Colors.white,
                    style: TextStyle(
                      fontSize: isSmallScreen ? 14 : 16,
                      color: Colors.black,
                    ),
                    items: mentors.map<DropdownMenuItem<String>>((m) {
                      return DropdownMenuItem<String>(
                        value: m['id'] as String,
                        child: Text(
                          m['username'] ?? 'Unknown Mentor',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            color: Colors.black,
                          ),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => selectedMentorId = val),
                  ),
      ],
    );
  }

  Widget _buildSessionTypeDropdown(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Select Session Type",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isSmallScreen ? 14 : 16,
          ),
        ),
        SizedBox(height: isSmallScreen ? 6 : 8),
        DropdownButtonFormField<String>(
          initialValue: selectedSessionType,
          decoration: InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 12 : 16,
              vertical: isSmallScreen ? 14 : 16,
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          dropdownColor: Colors.white,
          style: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
            color: Colors.black,
          ),
          items: sessionTypes.map<DropdownMenuItem<String>>((e) {
            return DropdownMenuItem<String>(
              value: e,
              child: Text(
                e,
                style: TextStyle(
                  fontSize: isSmallScreen ? 14 : 16,
                  color: Colors.black,
                ),
              ),
            );
          }).toList(),
          onChanged: (val) => setState(() => selectedSessionType = val!),
        ),
      ],
    );
  }

  Widget _buildDatePicker(bool isSmallScreen, bool isVerySmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Select Date",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isSmallScreen ? 14 : 16,
          ),
        ),
        SizedBox(height: isSmallScreen ? 6 : 8),
        ElevatedButton(
          onPressed: () => _selectDate(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[200],
            foregroundColor: Colors.black87,
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 12 : 16,
              vertical: isSmallScreen ? 14 : 16,
            ),
            minimumSize: Size(double.infinity, isSmallScreen ? 50 : 56),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.calendar_today,
                size: isSmallScreen ? 18 : 20,
                color: Colors.indigo,
              ),
              SizedBox(width: isSmallScreen ? 8 : 12),
              Flexible(
                child: Text(
                  selectedDate == null
                      ? "Select Date"
                      : isVerySmallScreen
                          ? "${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}"
                          : "Date: ${selectedDate!.toLocal().toString().split(' ')[0]}",
                  style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTimePicker(bool isSmallScreen, bool isVerySmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Select Time",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isSmallScreen ? 14 : 16,
          ),
        ),
        SizedBox(height: isSmallScreen ? 6 : 8),
        ElevatedButton(
          onPressed: () => _selectTime(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.grey[200],
            foregroundColor: Colors.black87,
            padding: EdgeInsets.symmetric(
              horizontal: isSmallScreen ? 12 : 16,
              vertical: isSmallScreen ? 14 : 16,
            ),
            minimumSize: Size(double.infinity, isSmallScreen ? 50 : 56),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.access_time,
                size: isSmallScreen ? 18 : 20,
                color: Colors.indigo,
              ),
              SizedBox(width: isSmallScreen ? 8 : 12),
              Flexible(
                child: Text(
                  selectedTime == null
                      ? "Select Time"
                      : isVerySmallScreen
                          ? selectedTime!.format(context)
                          : "Time: ${selectedTime!.format(context)}",
                  style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNotesSection(bool isSmallScreen) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Session Notes (Optional):",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isSmallScreen ? 14 : 16,
          ),
        ),
        SizedBox(height: isSmallScreen ? 6 : 8),
        TextField(
          controller: notesController,
          maxLines: 4,
          style: TextStyle(fontSize: isSmallScreen ? 14 : 16),
          decoration: InputDecoration(
            hintText: "Add topics or questions...",
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.all(isSmallScreen ? 12 : 16),
          ),
        ),
      ],
    );
  }

  Widget _buildConfirmButton(bool isSmallScreen) {
    return ElevatedButton(
      onPressed: _scheduleSession,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 14 : 16),
        minimumSize: Size(double.infinity, isSmallScreen ? 50 : 56),
      ),
      child: Text(
        "Confirm & Schedule Session",
        style: TextStyle(
          fontSize: isSmallScreen ? 14 : 16,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}