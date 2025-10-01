import 'package:flutter/material.dart';
import 'package:codexhub01/mentorship/livecodereview_screen.dart';
import 'package:codexhub01/mentorship/menteemessaging_screen.dart';
import 'package:codexhub01/mentorship/resourcelibrary_screen.dart';
import 'package:codexhub01/mentorship/performanceanalytics_screen.dart';
import 'package:codexhub01/mentorship/schedulesession_screen.dart';
import 'package:codexhub01/mentorship/progresstrackerscreen.dart';
import 'package:codexhub01/parts/friendlist.dart';
import 'package:codexhub01/parts/profilescreen.dart'; // Add this import
// Add if you have theme manager

class MentorDashboardScreen extends StatelessWidget {
  final List<Map<String, dynamic>> mentorFeatures = [
    {
      'title': 'Progress Tracker',
      'icon': Icons.show_chart,
      'route': ProgressTrackerScreen(),
    },
    {
      'title': 'Resource Library',
      'icon': Icons.library_books,
      'route': ResourceLibraryScreen(),
    },
    {
      'title': 'Live Code Review',
      'icon': Icons.code,
      'route': LiveCodeReviewScreen(),
    },
    {
      'title': 'Schedule Sessions',
      'icon': Icons.calendar_today,
      'route': ScheduleSessionScreen(),
    },
    {
      'title': 'Mentee Messaging',
      'icon': Icons.message,
      'route': MenteeMessagingScreen(),
    },
    {
      'title': 'Analytics',
      'icon': Icons.analytics,
      'route': PerformanceAnalyticsScreen(),
    },
    {
      'title': 'Friend List',
      'icon': Icons.smart_toy_outlined,
      'route': FriendList(),
    },
    {
      'title': 'My Profile',
      'icon': Icons.person,
      'route': ProfileScreen(), // Add profile to dashboard
    },
  ];

  MentorDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mentor Dashboard'),
        centerTitle: true,
        elevation: 4,
        backgroundColor: Colors.indigo,
        automaticallyImplyLeading: false,
        actions: [
          // Add profile icon to app bar
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
            tooltip: "Profile Settings",
          ),
        ],
      ),
      body: Column(
        children: [
          // Welcome message
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.indigo.shade50, Colors.blue.shade50],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome, Mentor!',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Manage your mentorship activities and help others grow',
                  style: TextStyle(fontSize: 16, color: Colors.indigo.shade700),
                ),
              ],
            ),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: GridView.builder(
                itemCount: mentorFeatures.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  return DashboardTile(
                    title: mentorFeatures[index]['title'],
                    iconData: mentorFeatures[index]['icon'],
                    screen: mentorFeatures[index]['route'],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardTile extends StatelessWidget {
  final String title;
  final IconData iconData;
  final Widget screen;

  const DashboardTile({
    super.key,
    required this.title,
    required this.iconData,
    required this.screen,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (context) => screen));
      },
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(iconData, size: 50, color: Colors.indigo),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
