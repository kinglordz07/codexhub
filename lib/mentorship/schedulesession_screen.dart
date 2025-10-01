import 'package:flutter/material.dart';

class ScheduleSessionScreen extends StatefulWidget {
  const ScheduleSessionScreen({super.key});

  @override
  ScheduleSessionScreenState createState() => ScheduleSessionScreenState();
}

class ScheduleSessionScreenState extends State<ScheduleSessionScreen> {
  DateTime selectedDate = DateTime.now();
  TimeOfDay selectedTime = TimeOfDay.now();
  String selectedSessionType = 'One-on-One Mentorship';
  final List<String> sessionTypes = [
    'One-on-One Mentorship',
    'Group Session',
    'Live Code Review',
  ];
  final TextEditingController notesController = TextEditingController();

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (pickedDate != null && pickedDate != selectedDate) {
      setState(() {
        selectedDate = pickedDate;
      });
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: selectedTime,
    );
    if (pickedTime != null && pickedTime != selectedTime) {
      setState(() {
        selectedTime = pickedTime;
      });
    }
  }

  void _scheduleSession() {
    String scheduledDetails =
        "Session Type: $selectedSessionType\nDate: ${selectedDate.toLocal().toString().split(' ')[0]}\nTime: ${selectedTime.format(context)}\nNotes: ${notesController.text}";

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Session Scheduled!\n$scheduledDetails"),
        duration: const Duration(seconds: 5),
      ),
    );
    
    // Optional: Navigate back or reset the form
    // Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schedule Mentorship Session'),
        backgroundColor: Colors.indigo,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            // Session Type Dropdown
            DropdownButtonFormField<String>(
              initialValue: selectedSessionType,
              items: sessionTypes.map((String type) {
                return DropdownMenuItem<String>(
                  value: type,
                  child: Text(type),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  selectedSessionType = newValue!;
                });
              },
              decoration: const InputDecoration(
                labelText: "Select Session Type",
                border: OutlineInputBorder(),
              ),
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
                      "Select Date: ${selectedDate.toLocal().toString().split(' ')[0]}",
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
                    child: Text("Select Time: ${selectedTime.format(context)}"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Mentor Notes
            const Text(
              "Session Notes (Optional):",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                hintText: "Add any specific topics or questions for your session...",
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 30),

            // Schedule Button
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