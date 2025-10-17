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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    final width = MediaQuery.of(context).size.width;
    final crossAxis = width > 600 ? 2 : 1; // adaptive for mobile

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mentor Dashboard'),
        centerTitle: true,
        elevation: 4,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            tooltip: "Profile Settings",
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      ProfileScreen(themeNotifier: themeNotifier)),
            ),
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
                colors: isDark
                    ? [Colors.grey[850]!, Colors.grey[800]!]
                    : [primary.withAlpha(30), primary.withAlpha(15)],
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
                      color: isDark ? Colors.white : primary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Manage your mentorship activities and help others grow',
                  style: TextStyle(
                      fontSize: 16,
                      color: isDark ? Colors.white70 : primary.withAlpha(200)),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: GridView.builder(
                itemCount: mentorFeatures.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxis,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1,
                ),
                itemBuilder: (context, index) {
                  final feature = mentorFeatures[index];
                  return _DashboardTile(
                    title: feature['title'],
                    iconData: feature['icon'],
                    primaryColor: primary,
                    isDark: isDark,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => feature['route'])),
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

class _DashboardTile extends StatelessWidget {
  final String title;
  final IconData iconData;
  final VoidCallback onTap;
  final Color primaryColor;
  final bool isDark;

  const _DashboardTile({
    required this.title,
    required this.iconData,
    required this.onTap,
    required this.primaryColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      splashColor: primaryColor.withAlpha((0.2 * 255).toInt()),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 6,
        color: isDark ? Colors.grey[850] : Colors.white,
        shadowColor: isDark ? Colors.black45 : Colors.black12,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(iconData, size: 50, color: primaryColor),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

