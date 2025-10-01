import 'package:flutter/material.dart';

class LiveCodeReviewScreen extends StatefulWidget {
  const LiveCodeReviewScreen({super.key});

  @override
  LiveCodeReviewScreenState createState() => LiveCodeReviewScreenState();
}

class LiveCodeReviewScreenState extends State<LiveCodeReviewScreen> {
  final String sampleCode = """
void main() {
  print('Hello, CodeXHub!');
}
""";

  final TextEditingController feedbackController = TextEditingController();
  bool hasError = false;

  void _submitFeedback() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Feedback Submitted: ${feedbackController.text}")),
    );
    feedbackController.clear();
  }

  void _toggleErrorStatus() {
    setState(() => hasError = !hasError);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Live Code Review'), backgroundColor: Colors.indigo),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Mentee Code:", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(border: Border.all(color: Colors.black)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(sampleCode, style: TextStyle(fontFamily: 'monospace', fontSize: 16)),
                  if (hasError)
  Padding(
    padding: EdgeInsets.only(top: 6),
    child: Text(
      "⚠️ Possible Error Detected!",
      style: TextStyle(
        color: hasError ? Colors.red : Colors.green, // Red when error, Green otherwise
        fontWeight: FontWeight.bold,
      ),
    ),
  ),
                ],
              ),
            ),
            SizedBox(height: 12),
            
            // Toggle error indicator
            ElevatedButton(
  onPressed: _toggleErrorStatus,
  style: ElevatedButton.styleFrom(
    backgroundColor: hasError ? Colors.red : Colors.orange, // Button background color
  ),
  child: Text(
    hasError ? "Clear Error Indicator" : "Mark Error",
    style: TextStyle(color: Colors.white), // Explicitly setting text color
  ),
),
            SizedBox(height: 12),

            // Feedback Input
            TextField(
              controller: feedbackController,
              decoration: InputDecoration(labelText: "Provide Feedback", border: OutlineInputBorder()),
              maxLines: 3,
            ),
            SizedBox(height: 12),

            // Submit Feedback Button
            ElevatedButton(
              onPressed: _submitFeedback,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: Text("Submit Feedback",style: TextStyle(color: Colors.white),),
            ),
          ],
        ),
      ),
    );
  }
}