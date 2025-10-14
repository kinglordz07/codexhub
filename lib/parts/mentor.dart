import 'package:flutter/material.dart';
import 'package:codexhub01/mentorship/resourcelibrary_screen.dart';
import 'package:codexhub01/parts/profilescreen.dart';
import 'package:codexhub01/mentorship/friendlst.dart';
import 'package:codexhub01/mentorship/session_list.dart';
import 'package:codexhub01/mentorship/mentor_invites.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
final supabase = Supabase.instance.client;

class MentorDashboardScreen extends StatelessWidget {
  MentorDashboardScreen({super.key});

  final List<Map<String, dynamic>> mentorFeatures = [
    {
      'title': 'Resource Library',
      'icon': Icons.library_books,
      'route': ResourceLibraryScreen(),
    },
    {
      'title': 'Friend List',
      'icon': Icons.smart_toy_outlined,
      'route': MentorFriendPage(),
    },
    {
      'title': 'Scheduled Session',
      'icon': Icons.calendar_today,
      'route': SessionListScreen(),
    },
    {
      'title': 'Live Invites',
      'icon': Icons.video_call,
      'route': MentorInvites(mentorId: supabase.auth.currentUser?.id ?? ''),
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mentor Dashboard'),
        centerTitle: true,
        backgroundColor: Colors.indigo,
        elevation: 4,
        automaticallyImplyLeading: false,
        actions: [
          // 👤 PROFILE BUTTON (dark mode will now be inside ProfileScreen)
          IconButton(
  icon: const Icon(Icons.person),
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ProfileScreen(themeNotifier: themeNotifier),
    ),
  ),
  tooltip: "Profile Settings",
),

        ],
      ),
      body: Column(
        children: [
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
                  final feature = mentorFeatures[index];
                  return DashboardTile(
                    title: feature['title'],
                    iconData: feature['icon'],
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => feature['route']),
                      );
                    },
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
  final VoidCallback onTap;

  const DashboardTile({
    super.key,
    required this.title,
    required this.iconData,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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
