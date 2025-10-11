import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/sessionservice.dart';

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

  // Mentors list
  List<Map<String, dynamic>> mentors = [];
  String? selectedMentorId;

  final List<String> sessionTypes = [
    'One-on-One Mentorship',
    'Group Session',
    'Live Code Review',
  ];

  @override
  void initState() {
    super.initState();
    _fetchMentors();
  }

  Future<void> _fetchMentors() async {
    final response = await Supabase.instance.client
        .from('profiles')
        .select('id, username')
        .eq('role', 'mentor');

    setState(() {
      mentors = List<Map<String, dynamic>>.from(response);
      if (mentors.isNotEmpty) {
        selectedMentorId = mentors.first['id'] as String;
      }
    });
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("User not logged in.")));
      return;
    }

    if (selectedMentorId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please select a mentor.")));
      return;
    }

    if (selectedDate == null || selectedTime == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a date and time.")),
      );
      return;
    }

    final mentorId = selectedMentorId!;
    final menteeId = currentUserId;

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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Session Scheduled Successfully!")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Schedule Mentorship Session"),
        backgroundColor: Colors.indigo,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Mentor Dropdown
            DropdownButtonFormField<String>(
              initialValue: selectedMentorId,
              decoration: const InputDecoration(
                labelText: "Select Mentor",
                border: OutlineInputBorder(),
              ),
              items:
                  mentors
                      .map<DropdownMenuItem<String>>(
                        (m) => DropdownMenuItem<String>(
                          value: m['id'] as String,
                          child: Text(m['username']),
                        ),
                      )
                      .toList(),
              onChanged: (val) => setState(() => selectedMentorId = val),
            ),
            const SizedBox(height: 20),

            // Session Type Dropdown
            DropdownButtonFormField<String>(
              initialValue: selectedSessionType,
              decoration: const InputDecoration(
                labelText: "Select Session Type",
                border: OutlineInputBorder(),
              ),
              items:
                  sessionTypes
                      .map<DropdownMenuItem<String>>(
                        (e) =>
                            DropdownMenuItem<String>(value: e, child: Text(e)),
                      )
                      .toList(),
              onChanged: (val) => setState(() => selectedSessionType = val!),
            ),
            const SizedBox(height: 20),

            // Date Picker
            Row(
              children: [
                const Icon(Icons.calendar_today, color: Colors.indigo),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _selectDate(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      foregroundColor: Colors.black87,
                    ),
                    child: Text(
                      selectedDate == null
                          ? "Select Date"
                          : "Date: ${selectedDate!.toLocal().toString().split(' ')[0]}",
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Time Picker
            Row(
              children: [
                const Icon(Icons.access_time, color: Colors.indigo),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _selectTime(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[200],
                      foregroundColor: Colors.black87,
                    ),
                    child: Text(
                      selectedTime == null
                          ? "Select Time"
                          : "Time: ${selectedTime!.format(context)}",
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Notes
            const Text(
              "Session Notes (Optional):",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: "Add topics or questions...",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),

            // Confirm Button
            ElevatedButton(
              onPressed: _scheduleSession,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                "Confirm & Schedule Session",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
